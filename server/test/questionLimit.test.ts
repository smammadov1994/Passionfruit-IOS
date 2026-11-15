import { afterEach, describe, expect, it } from 'vitest';
import { compatiblePair, pairUp, startServer, TestClient, type TestServer } from './helpers.js';

let server: TestServer;
const clients: TestClient[] = [];

afterEach(async () => {
  await Promise.all(clients.splice(0).map((c) => c.close()));
  await server.close();
});

describe('staying for the whole date', () => {
  it('matches the two at once when the clock runs out, with no vote', async () => {
    server = await startServer({ matchOnFullDate: true, turnDurationSec: 0.2, dateDurationSec: 0.9 });
    const [a, b] = await compatiblePair(server);
    const { ca, cb } = await pairUp(server, a, b);
    clients.push(ca, cb);
    await ca.next('date.started');
    expect(await ca.next('date.ended', 4000)).toMatchObject({ reason: 'timer', matched: true });
    await cb.next('date.ended');
    expect(await ca.next('date.result', 1000)).toMatchObject({ outcome: 'match' });
    expect(await cb.next('date.result', 1000)).toMatchObject({ outcome: 'match' });
  });

  it('does not match when one of them leaves before the end', async () => {
    server = await startServer({ matchOnFullDate: true, turnDurationSec: 0.2, dateDurationSec: 2 });
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = await pairUp(server, a, b);
    clients.push(ca, cb);
    await ca.next('date.started');
    cb.send({ type: 'date.leave', dateId });
    expect(await ca.next('date.ended', 2000)).toMatchObject({ reason: 'partner_left' });
    await ca.expectNone('date.result', 300);
  });

  it('an optional question cap ends the date early, the same way the clock does', async () => {
    server = await startServer({ matchOnFullDate: true, questionsPerDate: 1, turnDurationSec: 0.15, dateDurationSec: 30 });
    const [a, b] = await compatiblePair(server);
    const { ca, cb } = await pairUp(server, a, b);
    clients.push(ca, cb);
    expect(await ca.next('date.ended', 3000)).toMatchObject({ reason: 'timer', matched: true });
    expect(ca.count('icebreaker.turn')).toBe(2);
    expect(await cb.next('date.result', 1000)).toMatchObject({ outcome: 'match' });
  });
});
