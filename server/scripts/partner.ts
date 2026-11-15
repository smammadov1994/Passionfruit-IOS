/**
 * One fake person to date, for trying the real app when nobody else is online.
 *
 * It signs in (dev auth), fills in a profile, goes online and waits. When the app is paired with
 * it, it is ready at once, never leaves early, says yes, and after a match answers every chat
 * message. It sends no video: the app shows its "no video yet" state for the partner.
 *
 *   npm run partner                                   # a woman interested in men, in New York
 *   npm run partner -- --gender man --interested woman --name Theo
 *   npm run partner -- --lat 51.5 --lng -0.12         # near you, if your distance limit is tight
 *
 * Needs ALLOW_DEV_AUTH=1 on the server. Stop it with Ctrl-C.
 */
import WebSocket from 'ws';

type Frame = { type: string } & Record<string, unknown>;

const argv = process.argv.slice(2);
const arg = (name: string, fallback: string): string => {
  const i = argv.indexOf(`--${name}`);
  return (i >= 0 ? argv[i + 1] : undefined) ?? fallback;
};

const url = arg('url', 'http://localhost:8080').replace(/\/+$/, '');
const gender = arg('gender', 'woman');
const interested = arg('interested', gender === 'woman' ? 'man' : 'woman');
const name = arg('name', gender === 'woman' ? 'Maya' : 'Theo');
const lat = Number(arg('lat', '40.73'));
const lng = Number(arg('lng', '-73.99'));

async function api<T>(method: string, route: string, token: string | null, body?: unknown): Promise<T> {
  const headers: Record<string, string> = {};
  if (token !== null) headers.authorization = `Bearer ${token}`;
  if (body !== undefined) headers['content-type'] = 'application/json';
  const res = await fetch(`${url}${route}`, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${route} -> HTTP ${res.status} ${text}`);
  return (text.length > 0 ? JSON.parse(text) : null) as T;
}

async function main(): Promise<void> {
  // A fresh identity each run, so the 24-hour re-pair cooldown never hides it from you.
  const deviceId = `partner-${Date.now().toString(36)}`;
  const auth = await api<{ token: string; user: { id: string } }>('POST', '/v1/auth/dev', null, { deviceId });
  const { token } = auth;
  await api('PUT', '/v1/me', token, {
    firstName: name,
    birthdate: '1996-05-15',
    gender,
    interestedIn: [interested],
    bio: 'A test partner. I always say yes.',
    city: 'New York',
    lat,
    lng,
    intention: 'long_term',
    onboardingComplete: true,
  });
  await api('PUT', '/v1/me/preferences', token, { ageMin: 18, ageMax: 99, maxDistanceKm: 20000, notifyOnlineSingles: false });

  const socket = new WebSocket(`${url.replace(/^http/, 'ws')}/v1/ws?token=${encodeURIComponent(token)}`);
  const send = (frame: Frame): void => {
    if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(frame));
  };
  await new Promise<void>((resolve, reject) => {
    socket.once('open', () => resolve());
    socket.once('error', reject);
  });
  setInterval(() => send({ type: 'ping' }), 20_000);
  const join = (): void => void setTimeout(() => send({ type: 'queue.join' }), 500);
  const replies = ['Ha, fair.', 'Tell me more.', 'Coffee on Saturday?', 'I was hoping you would say that.'];
  let replyIndex = 0;

  socket.on('message', (data) => {
    const m = JSON.parse(String(data)) as Frame;
    const dateId = typeof m.dateId === 'string' ? m.dateId : '';
    switch (m.type) {
      case 'date.matched':
        console.log(`${name}: paired, starting`);
        send({ type: 'date.ready', dateId });
        break;
      case 'date.started':
        console.log(`${name}: date started`);
        break;
      case 'date.checkpoint':
        // After the first question both vote; these scripted clients always carry on.
        send({ type: 'date.continue', dateId, choice: 'continue' });
        break;
      case 'date.ended':
        console.log(`${name}: date ended (${String(m.reason)})`);
        if (m.reason === 'timer') send({ type: 'date.decide', dateId, decision: 'yes' });
        else join();
        break;
      case 'date.result':
        console.log(`${name}: result ${String(m.outcome)}`);
        join();
        break;
      case 'chat.message': {
        const message = m.message as { matchId?: string; senderId?: string; text?: string } | undefined;
        if (message?.matchId && message.senderId !== auth.user.id) {
          console.log(`${name}: got "${String(message.text)}"`);
          const text = replies[replyIndex++ % replies.length] as string;
          setTimeout(() => {
            api('POST', `/v1/matches/${message.matchId}/messages`, token, { text }).catch((err: unknown) =>
              console.error(`${name}: reply failed: ${String(err)}`),
            );
          }, 1500);
        }
        break;
      }
      case 'error':
        console.error(`${name}: server error ${String(m.code)} ${String(m.message)}`);
        break;
      default:
        break;
    }
  });
  socket.on('close', () => {
    console.log(`${name}: disconnected`);
    process.exit(0);
  });

  send({ type: 'queue.join' });
  console.log(`${name} (${gender}, interested in ${interested}) is online at ${url}. Go online in the app.`);
}

main().catch((err: unknown) => {
  console.error(`partner: ${err instanceof Error ? err.message : String(err)}`);
  process.exit(1);
});
