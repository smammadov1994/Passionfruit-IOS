import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { APP_NAME } from '../appName.js';
import type { AppContext } from '../context.js';
import { forbidden, notFound } from '../errors.js';
import { RATE_RULES } from '../services/rateLimit.js';
import { toWireMatch, toWireMessage } from '../services/serialize.js';
import type { MatchRecord, UserRecord } from '../types.js';
import { errMessage } from '../util.js';
import { IdParams, parse } from './helpers.js';

const MessagesQuery = z.object({
  before: z.string().datetime({ offset: true }).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});
const MessageBody = z.object({
  text: z.string().trim().min(1).max(2000),
  clientId: z.string().trim().min(1).max(64).optional(),
});

export function registerMatchRoutes(app: FastifyInstance, ctx: AppContext): void {
  /** Loads a match the caller belongs to. Someone else's match looks exactly like a missing one. */
  async function ownMatch(user: UserRecord, params: unknown): Promise<{ match: MatchRecord; partnerId: string }> {
    const { id } = parse(IdParams, params);
    const match = await ctx.store.getMatch(id);
    if (!match || (match.userA !== user.id && match.userB !== user.id)) throw notFound('That match no longer exists.');
    return { match, partnerId: match.userA === user.id ? match.userB : match.userA };
  }

  app.get('/v1/matches', async (request) => {
    const user = await ctx.authenticate(request);
    const now = ctx.clock.now();
    const summaries = await ctx.store.listMatchSummaries(user.id);
    return { matches: summaries.map((s) => toWireMatch(s, user, now)) };
  });

  app.delete('/v1/matches/:id', async (request, reply) => {
    const user = await ctx.authenticate(request);
    const { match } = await ownMatch(user, request.params);
    await ctx.accounts.removeMatch(match);
    return reply.code(204).send();
  });

  app.get('/v1/matches/:id/messages', async (request) => {
    const user = await ctx.authenticate(request);
    const { match } = await ownMatch(user, request.params);
    const query = parse(MessagesQuery, request.query);
    const before = query.before !== undefined ? new Date(query.before) : null;
    const messages = await ctx.store.listMessages(match.id, before, query.limit);
    return { messages: messages.map(toWireMessage) };
  });

  app.post('/v1/matches/:id/messages', async (request) => {
    const user = await ctx.authenticate(request);
    ctx.rateLimiter.enforce(RATE_RULES.message, user.id);
    if (user.suspended) throw forbidden('account_suspended', 'Your account is paused while we review a report.');
    const { match, partnerId } = await ownMatch(user, request.params);
    const body = parse(MessageBody, request.body);
    const { message, created } = await ctx.store.addMessage({
      matchId: match.id,
      senderId: user.id,
      text: body.text,
      clientId: body.clientId ?? null,
      sentAt: new Date(ctx.clock.now()),
    });
    const wire = toWireMessage(message);
    if (created) {
      const delivered = ctx.hub.send(partnerId, { type: 'chat.message', message: wire });
      if (!delivered) {
        void notifyOffline(partnerId, user.firstName, match.id).catch((err: unknown) => {
          request.log.warn({ err: errMessage(err) }, 'message push failed');
        });
      }
    }
    return wire;
  });

  app.post('/v1/matches/:id/read', async (request, reply) => {
    const user = await ctx.authenticate(request);
    const { match } = await ownMatch(user, request.params);
    await ctx.store.markRead(match.id, user.id, new Date(ctx.clock.now()));
    return reply.code(204).send();
  });

  /** A message for someone who is not connected becomes a push (content is not included). */
  async function notifyOffline(partnerId: string, senderName: string, matchId: string): Promise<void> {
    const partner = await ctx.store.getUser(partnerId);
    if (!partner || !partner.pushEnabled || partner.apnsToken === null) return;
    const result = await ctx.push.send(partner.apnsToken, {
      title: APP_NAME,
      body: senderName.length > 0 ? `${senderName} sent you a message` : 'You have a new message',
      collapseId: `match-${matchId}`,
      data: { kind: 'chat_message', matchId },
    });
    if (!result.ok && result.unregistered === true) {
      await ctx.store.updateUser(partnerId, { apnsToken: null, pushEnabled: false });
    }
  }
}
