import type { FastifyInstance } from 'fastify';
import type { RawData, WebSocket } from 'ws';
import type { AppContext } from '../context.js';
import { errMessage } from '../util.js';
import { COPY } from './copy.js';
import { Hub, type Connection } from './Hub.js';
import { CALL_PREFIX, CLOSE, ClientMessageSchema, type ClientMessage } from './protocol.js';
import { resolveSuspension, suspendedMessage } from './QueueService.js';

/** Inbound flood control: generous enough for ICE candidate bursts. */
const FLOOD_WINDOW_MS = 10_000;
const FLOOD_MAX_MESSAGES = 300;
export const WS_MAX_PAYLOAD_BYTES = 256 * 1024;

function rawToString(data: RawData): string {
  if (typeof data === 'string') return data;
  if (Array.isArray(data)) return Buffer.concat(data).toString('utf8');
  if (data instanceof ArrayBuffer) return Buffer.from(data).toString('utf8');
  return data.toString('utf8');
}

async function dispatch(ctx: AppContext, userId: string, msg: ClientMessage): Promise<void> {
  switch (msg.type) {
    case 'ping':
      ctx.hub.send(userId, { type: 'pong' });
      return;
    case 'queue.join':
      await ctx.queue.join(userId);
      return;
    case 'queue.leave':
      ctx.queue.leave(userId);
      return;
    case 'date.ready':
      ctx.dates.handleReady(userId, msg.dateId);
      return;
    case 'rtc.signal':
      if (msg.dateId.startsWith(CALL_PREFIX)) ctx.calls.signal(userId, msg.dateId, msg.payload);
      else ctx.dates.handleSignal(userId, msg.dateId, msg.payload);
      return;
    case 'turn.pass':
      ctx.dates.handlePass(userId, msg.dateId);
      return;
    case 'date.leave':
      ctx.dates.handleLeave(userId, msg.dateId);
      return;
    case 'date.decide':
      ctx.dates.handleDecide(userId, msg.dateId, msg.decision);
      return;
    case 'date.continue':
      ctx.dates.handleContinue(userId, msg.dateId, msg.choice);
      return;
    case 'call.invite':
      await ctx.calls.invite(userId, msg.matchId);
      return;
    case 'call.accept':
      ctx.calls.accept(userId, msg.matchId);
      return;
    case 'call.decline':
      ctx.calls.decline(userId, msg.matchId);
      return;
    case 'call.end':
      ctx.calls.end(userId, msg.matchId);
      return;
  }
}

function onMessage(ctx: AppContext, connection: Connection, data: RawData): void {
  const now = ctx.clock.now();
  connection.lastSeen = now;
  if (now - connection.windowStart > FLOOD_WINDOW_MS) {
    connection.windowStart = now;
    connection.windowCount = 0;
  }
  connection.windowCount += 1;
  if (connection.windowCount > FLOOD_MAX_MESSAGES) {
    connection.socket.close(CLOSE.flood, 'too many messages');
    return;
  }

  let parsed: ReturnType<typeof ClientMessageSchema.safeParse>;
  try {
    parsed = ClientMessageSchema.safeParse(JSON.parse(rawToString(data)));
  } catch {
    Hub.sendTo(connection.socket, { type: 'error', code: 'bad_message', message: COPY.badMessage });
    return;
  }
  if (!parsed.success) {
    Hub.sendTo(connection.socket, { type: 'error', code: 'bad_message', message: COPY.badMessage });
    return;
  }
  const message = parsed.data;
  // One message at a time per connection, in arrival order; a failure never breaks the chain.
  connection.chain = connection.chain
    .then(async () => {
      // Messages from a socket that has since been replaced or closed are dropped.
      if (ctx.hub.get(connection.userId) !== connection) return;
      await dispatch(ctx, connection.userId, message);
    })
    .catch((err: unknown) => {
      ctx.log.error({ userId: connection.userId, type: message.type, err: errMessage(err) }, 'ws message failed');
      Hub.sendTo(connection.socket, { type: 'error', code: 'internal', message: COPY.internal });
    });
}

async function onOpen(ctx: AppContext, connection: Connection): Promise<void> {
  const { userId } = connection;
  const found = await ctx.store.getUser(userId);
  if (!found) {
    connection.socket.close(CLOSE.accountDeleted, 'account not found');
    return;
  }
  const user = await resolveSuspension(ctx.store, found, ctx.clock.now());
  if (ctx.hub.get(userId) !== connection) return;
  if (user.suspended) Hub.sendTo(connection.socket, suspendedMessage(user));
  await ctx.queue.handleConnect(userId);
  if (ctx.hub.get(userId) !== connection) return;
  ctx.dates.handleReconnect(userId);
}

function onClose(ctx: AppContext, connection: Connection): void {
  // A socket that was replaced by a newer one for the same user is not a disconnect.
  if (!ctx.hub.detach(connection)) return;
  ctx.queue.handleDisconnect(connection.userId);
  ctx.calls.handleDisconnect(connection.userId);
  ctx.dates.handleDisconnect(connection.userId);
}

/** Registers `GET /v1/ws?token=<token>` and the idle sweeper. Returns a stop function. */
export function registerWebSocket(app: FastifyInstance, ctx: AppContext): () => void {
  app.get<{ Querystring: { token?: string } }>(
    '/v1/ws',
    {
      websocket: true,
      // Runs before the upgrade: a bad token gets a plain HTTP 401, never an open socket.
      preValidation: async (request, reply) => {
        const token = typeof request.query.token === 'string' ? request.query.token : '';
        const userId = token.length > 0 ? await ctx.sessions.verify(token) : null;
        if (userId === null) {
          await reply.code(401).send({ error: { code: 'unauthorized', message: 'Please sign in again.' } });
          return;
        }
        wsUsers.set(request.raw, userId);
      },
    },
    (socket: WebSocket, request) => {
      const userId = wsUsers.get(request.raw);
      if (userId === undefined) {
        socket.close(1008, 'unauthorized');
        return;
      }
      const { connection, replaced } = ctx.hub.attach(userId, socket, ctx.clock.now());
      if (replaced) {
        try {
          replaced.socket.close(CLOSE.replaced, 'replaced by a newer connection');
        } catch {
          replaced.socket.terminate();
        }
      }
      socket.on('message', (data) => onMessage(ctx, connection, data));
      socket.on('close', () => onClose(ctx, connection));
      socket.on('error', (err) => ctx.log.debug({ userId, err: err.message }, 'ws socket error'));
      // Queue the open work on the connection's chain so early client messages wait for it.
      connection.chain = connection.chain
        .then(() => onOpen(ctx, connection))
        .catch((err: unknown) => ctx.log.error({ userId, err: errMessage(err) }, 'ws open failed'));
    },
  );

  // Drop connections that have been silent for longer than the idle timeout (client pings every 20 s).
  const idleMs = ctx.config.wsIdleTimeoutSec * 1000;
  const sweeper = setInterval(
    () => {
      const now = ctx.clock.now();
      for (const connection of ctx.hub.all()) {
        if (now - connection.lastSeen > idleMs) {
          try {
            connection.socket.close(CLOSE.idle, 'idle timeout');
          } catch {
            connection.socket.terminate();
          }
          // Do not wait for the close handshake of a dead peer before freeing their partner.
          onClose(ctx, connection);
        }
      }
    },
    Math.min(5000, Math.max(250, idleMs / 4)),
  );
  sweeper.unref();
  return () => clearInterval(sweeper);
}

const wsUsers = new WeakMap<object, string>();
