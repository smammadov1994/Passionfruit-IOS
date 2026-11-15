/**
 * Load/flow simulator: N fake clients sign in (dev auth), fill in a profile, go online and
 * speed-date each other over the real REST + WebSocket protocol.
 *
 *   ALLOW_DEV_AUTH=1 DATE_DURATION_SEC=6 TURN_DURATION_SEC=2 DECISION_WINDOW_SEC=3 npm run dev
 *   npm run sim -- --url http://localhost:8080 --clients 8 --seconds 40
 *
 * Exits non-zero if any client saw a protocol error.
 */
import WebSocket from 'ws';

interface Args {
  url: string;
  clients: number;
  seconds: number;
}

function parseArgs(argv: string[]): Args {
  const get = (name: string, fallback: string): string => {
    const i = argv.indexOf(`--${name}`);
    const value = i >= 0 ? argv[i + 1] : undefined;
    return value ?? fallback;
  };
  const clients = Number(get('clients', '6'));
  const seconds = Number(get('seconds', '30'));
  if (!Number.isInteger(clients) || clients < 2 || !Number.isFinite(seconds) || seconds <= 0) {
    throw new Error('usage: npm run sim -- [--url http://localhost:8080] [--clients 6] [--seconds 30]');
  }
  return { url: get('url', 'http://localhost:8080').replace(/\/+$/, ''), clients, seconds };
}

const stats = {
  connected: 0,
  matched: 0,
  started: 0,
  signalsRelayed: 0,
  turns: 0,
  passes: 0,
  endedTimer: 0,
  endedLeft: 0,
  endedOther: 0,
  matches: 0,
  noMatches: 0,
  limitReached: 0,
  moderationCalls: 0,
  errors: [] as string[],
};

type Frame = { type: string } & Record<string, unknown>;
const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));
const chance = (p: number): boolean => Math.random() < p;
const FAKE_JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 74, 70, 73, 70, 0, 0xff, 0xd9]).toString('base64');

async function api<T>(base: string, method: string, route: string, token: string | null, body?: unknown): Promise<T> {
  const headers: Record<string, string> = {};
  if (token !== null) headers.authorization = `Bearer ${token}`;
  if (body !== undefined) headers['content-type'] = 'application/json';
  const res = await fetch(`${base}${route}`, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${route} -> HTTP ${res.status} ${text}`);
  return (text.length > 0 ? JSON.parse(text) : null) as T;
}

async function runClient(args: Args, index: number, runId: string, stopAt: number): Promise<void> {
  const name = `sim-${index}`;
  const woman = index % 2 === 0;
  const auth = await api<{ token: string; user: { id: string } }>(args.url, 'POST', '/v1/auth/dev', null, {
    deviceId: `sim-${runId}-${index}`,
  });
  const { token } = auth;
  const myId = auth.user.id;
  await api(args.url, 'PUT', '/v1/me', token, {
    firstName: `${woman ? 'Ada' : 'Ben'}${index}`,
    birthdate: `${1985 + (index % 15)}-0${1 + (index % 9)}-15`,
    gender: woman ? 'woman' : 'man',
    interestedIn: [woman ? 'man' : 'woman'],
    city: 'New York',
    lat: 40.7 + index * 0.001,
    lng: -74,
    onboardingComplete: true,
  });
  await api(args.url, 'PUT', '/v1/me/preferences', token, {
    ageMin: 18,
    ageMax: 99,
    maxDistanceKm: 100,
    notifyOnlineSingles: false,
  });

  const socket = new WebSocket(`${args.url.replace(/^http/, 'ws')}/v1/ws?token=${encodeURIComponent(token)}`);
  const send = (frame: Frame): void => {
    if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(frame));
  };
  await new Promise<void>((resolve, reject) => {
    socket.once('open', () => resolve());
    socket.once('error', reject);
  });
  stats.connected += 1;
  const heartbeat = setInterval(() => send({ type: 'ping' }), 20_000);
  let stopped = false;
  const rejoin = (): void => {
    if (!stopped && Date.now() < stopAt) setTimeout(() => send({ type: 'queue.join' }), 300);
  };

  socket.on('message', (data) => {
    const m = JSON.parse(String(data)) as Frame;
    const dateId = typeof m.dateId === 'string' ? m.dateId : '';
    switch (m.type) {
      case 'date.matched':
        stats.matched += 1;
        send({ type: 'date.ready', dateId });
        if (m.role === 'caller') send({ type: 'rtc.signal', dateId, payload: { kind: 'offer', sdp: `offer-from-${name}` } });
        break;
      case 'rtc.signal': {
        stats.signalsRelayed += 1;
        const payload = m.payload as { kind?: string };
        if (payload.kind === 'offer') send({ type: 'rtc.signal', dateId, payload: { kind: 'answer', sdp: `answer-from-${name}` } });
        break;
      }
      case 'date.started':
        stats.started += 1;
        void (async () => {
          try {
            await api(args.url, 'POST', '/v1/moderation/frame', token, { dateId, imageBase64: FAKE_JPEG });
            await api(args.url, 'POST', '/v1/moderation/transcript', token, { dateId, text: 'So, what do you do for fun?' });
            stats.moderationCalls += 2;
          } catch (err) {
            stats.errors.push(`${name}: ${String(err)}`);
          }
        })();
        if (chance(0.15)) setTimeout(() => send({ type: 'date.leave', dateId }), 500 + Math.random() * 1500);
        break;
      case 'icebreaker.turn':
        stats.turns += 1;
        if (m.speakerId === myId && chance(0.5)) {
          stats.passes += 1;
          setTimeout(() => send({ type: 'turn.pass', dateId }), 200 + Math.random() * 600);
        }
        break;
      case 'date.checkpoint':
        // After the first question both vote; these scripted clients always carry on.
        send({ type: 'date.continue', dateId, choice: 'continue' });
        break;
      case 'date.ended':
        if (m.reason === 'timer') {
          stats.endedTimer += 1;
          setTimeout(() => send({ type: 'date.decide', dateId, decision: chance(0.6) ? 'yes' : 'no' }), 100 + Math.random() * 400);
        } else {
          if (m.reason === 'you_left' || m.reason === 'partner_left') stats.endedLeft += 1;
          else stats.endedOther += 1;
          rejoin();
        }
        break;
      case 'date.result':
        if (m.outcome === 'match') stats.matches += 1;
        else stats.noMatches += 1;
        rejoin();
        break;
      case 'queue.limit':
        stats.limitReached += 1;
        stopped = true;
        break;
      case 'error':
        // A pass or leave that races the end of a turn/date is expected; anything else is a bug.
        if (m.code !== 'not_your_turn' && m.code !== 'not_in_date') stats.errors.push(`${name}: ${String(m.code)} ${String(m.message)}`);
        break;
      default:
        break;
    }
  });
  socket.on('error', (err) => stats.errors.push(`${name}: socket ${err.message}`));

  send({ type: 'queue.join' });
  while (Date.now() < stopAt) await sleep(250);
  stopped = true;
  clearInterval(heartbeat);
  send({ type: 'queue.leave' });
  await sleep(100);
  socket.close();
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const health = await fetch(`${args.url}/health`).catch(() => null);
  if (!health || !health.ok) throw new Error(`No server answering at ${args.url}/health`);
  const runId = Math.random().toString(36).slice(2, 8);
  const stopAt = Date.now() + args.seconds * 1000;
  console.log(`sim: ${args.clients} clients against ${args.url} for ${args.seconds}s (run ${runId})`);
  const results = await Promise.allSettled(
    Array.from({ length: args.clients }, (_, i) => runClient(args, i, runId, stopAt)),
  );
  for (const r of results) if (r.status === 'rejected') stats.errors.push(String(r.reason));
  const { errors, ...numbers } = stats;
  console.table(numbers);
  if (errors.length > 0) {
    console.error(`sim: ${errors.length} error(s):`);
    for (const e of errors.slice(0, 20)) console.error(`  ${e}`);
    process.exit(1);
  }
  console.log('sim: OK');
}

main().catch((err: unknown) => {
  console.error(`sim: ${err instanceof Error ? err.message : String(err)}`);
  process.exit(1);
});
