import { afterEach, describe, expect, it } from 'vitest';
import { compatiblePair, pairUp, startServer, TestClient, type TestServer } from './helpers.js';

let server: TestServer;
const clients: TestClient[] = [];

afterEach(async () => {
  await Promise.all(clients.splice(0).map((c) => c.close()));
  await server.close();
});

/** A date with the checkpoint on: 0.2 s turns, so the first question is over after 0.4 s. */
async function dateWithCheckpoint(): Promise<{ ca: TestClient; cb: TestClient; dateId: string }> {
  server = await startServer({
    checkpointWindowSec: 0.6,
    turnDurationSec: 0.2,
    dateDurationSec: 3,
    decisionGraceMs: 100,
  });
  const [a, b] = await compatiblePair(server);
  const paired = await pairUp(server, a, b);
  clients.push(paired.ca, paired.cb);
  return paired;
}

describe('checkpoint after the first question', () => {
  it('pauses after both turns of question 1, and resumes with the clock paused when both continue', async () => {
    const { ca, cb, dateId } = await dateWithCheckpoint();
    const started = await ca.next('date.started');
    const checkpoint = await ca.next('date.checkpoint', 2000);
    expect(checkpoint.dateId).toBe(dateId);
    expect(Date.parse(String(checkpoint.deadline))).toBeGreaterThan(Date.now());
    await cb.next('date.checkpoint');
    // Only question 1 was asked before the pause: one turn each.
    expect(ca.count('icebreaker.turn')).toBe(2);

    // A pass during the pause is refused; nothing is revealed after one vote.
    ca.send({ type: 'turn.pass', dateId });
    expect(await ca.next('error')).toMatchObject({ code: 'not_your_turn' });
    ca.send({ type: 'date.continue', dateId, choice: 'continue' });
    await ca.expectNone('date.resumed', 150);

    cb.send({ type: 'date.continue', dateId, choice: 'continue' });
    const resumed = await ca.next('date.resumed');
    await cb.next('date.resumed');
    // The time spent voting was given back: the date now ends later than first announced.
    expect(Date.parse(String(resumed.endsAt))).toBeGreaterThan(Date.parse(String(started.endsAt)));
    // Question 2 follows, and the date still ends on the timer with the yes/no screen.
    await ca.next('icebreaker.turn'); // question 1, first speaker
    await ca.next('icebreaker.turn'); // question 1, second speaker
    const next = await ca.next('icebreaker.turn');
    expect(next.questionIndex).toBe(1);
    expect(await ca.next('date.ended', 5000)).toMatchObject({ reason: 'timer' });
  });

  it('ends for both at once when one person chooses to stop, without saying who', async () => {
    const { ca, cb, dateId } = await dateWithCheckpoint();
    await ca.next('date.checkpoint', 2000);
    await cb.next('date.checkpoint');
    cb.send({ type: 'date.continue', dateId, choice: 'end' });
    const endedA = await ca.next('date.ended');
    const endedB = await cb.next('date.ended');
    expect(endedA).toEqual({ type: 'date.ended', dateId, reason: 'checkpoint' });
    expect(endedB).toEqual(endedA);
    await server.ctx.dates.flush();
    expect(await server.ctx.store.getDate(dateId)).toMatchObject({ endReason: 'checkpoint', outcome: 'no_match' });
    expect(server.ctx.dates.activeCount()).toBe(0);
  });

  it('no answer by the deadline counts as stop', async () => {
    const { ca, cb, dateId } = await dateWithCheckpoint();
    await ca.next('date.checkpoint', 2000);
    ca.send({ type: 'date.continue', dateId, choice: 'continue' });
    expect(await ca.next('date.ended', 2000)).toMatchObject({ reason: 'checkpoint' });
    expect(await cb.next('date.ended')).toMatchObject({ reason: 'checkpoint' });
  });

  it('a first vote stands, and votes outside the checkpoint are refused', async () => {
    const { ca, cb, dateId } = await dateWithCheckpoint();
    ca.send({ type: 'date.continue', dateId, choice: 'end' }); // too early
    expect(await ca.next('error')).toMatchObject({ code: 'not_in_date' });
    await ca.next('date.checkpoint', 2000);
    ca.send({ type: 'date.continue', dateId, choice: 'continue' });
    ca.send({ type: 'date.continue', dateId, choice: 'end' }); // ignored
    cb.send({ type: 'date.continue', dateId, choice: 'continue' });
    await ca.next('date.resumed');
  });
});
