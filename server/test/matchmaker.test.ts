import { describe, expect, it } from 'vitest';
import { mutuallyCompatible, satisfies, type Candidate } from '../src/matchmaking/compat.js';
import { InMemoryMatchmaker } from '../src/matchmaking/Matchmaker.js';
import { affinity, mutualScore, yesProbability, yesRateGiven, yesRateReceived } from '../src/matchmaking/score.js';
import { DEFAULT_PREFERENCES, type Preferences } from '../src/types.js';
import { ageFromBirthdate, haversineKm } from '../src/util.js';

const NOW = Date.UTC(2026, 10, 14, 12, 0, 0); // 2026-11-14

function person(id: string, over: Partial<Candidate> = {}, prefs: Partial<Preferences> = {}): Candidate {
  return {
    userId: id,
    birthdate: '1996-01-01', // 30
    gender: 'woman',
    interestedIn: ['man'],
    lat: 40.75,
    lng: -73.99,
    intention: null,
    children: null,
    religion: null,
    education: null,
    smoking: null,
    drinking: null,
    display: { firstName: id, city: 'NYC', photoUrl: null },
    isPremium: false,
    exclusions: new Set(),
    stats: { answered: 0, yesGiven: 0, rated: 0, yesReceived: 0 },
    strikes: 0,
    ...over,
    preferences: { ...DEFAULT_PREFERENCES, ...prefs },
  };
}
const woman = (id = 'w', over: Partial<Candidate> = {}, prefs: Partial<Preferences> = {}): Candidate =>
  person(id, { gender: 'woman', interestedIn: ['man'], ...over }, prefs);
const man = (id = 'm', over: Partial<Candidate> = {}, prefs: Partial<Preferences> = {}): Candidate =>
  person(id, { gender: 'man', interestedIn: ['woman'], ...over }, prefs);

describe('age and distance', () => {
  it('computes age from birthdate, flipping on the birthday', () => {
    expect(ageFromBirthdate('2008-11-14', NOW)).toBe(18);
    expect(ageFromBirthdate('2008-11-15', NOW)).toBe(17);
    expect(ageFromBirthdate('1990-02-28', NOW)).toBe(36);
    expect(ageFromBirthdate('nonsense', NOW)).toBe(-1);
  });

  it('computes haversine distance', () => {
    // New York City to Los Angeles is about 3,936 km.
    expect(haversineKm(40.7128, -74.006, 34.0522, -118.2437)).toBeGreaterThan(3900);
    expect(haversineKm(40.7128, -74.006, 34.0522, -118.2437)).toBeLessThan(3970);
    expect(haversineKm(10, 10, 10, 10)).toBe(0);
  });
});

describe('compatibility matrix', () => {
  it('pairs two people who want each other', () => {
    expect(mutuallyCompatible(woman(), man(), NOW)).toBe(true);
  });

  it('never pairs someone with themselves', () => {
    const w = woman('same', { interestedIn: ['woman'] });
    expect(mutuallyCompatible(w, w, NOW)).toBe(false);
  });

  it.each([
    ['gender not in the other interestedIn', woman(), man('m', { interestedIn: ['man'] })],
    ['one-sided interest', woman('w', { interestedIn: ['woman'] }), man()],
    ['nonbinary not selected', person('n', { gender: 'nonbinary', interestedIn: ['man'] }), man()],
  ])('rejects: %s', (_name, a, b) => {
    expect(mutuallyCompatible(a, b, NOW)).toBe(false);
    expect(mutuallyCompatible(b, a, NOW)).toBe(false);
  });

  it('accepts nonbinary when both sides select it', () => {
    const n = person('n', { gender: 'nonbinary', interestedIn: ['man', 'nonbinary'] });
    const m = man('m', { interestedIn: ['woman', 'nonbinary'] });
    expect(mutuallyCompatible(n, m, NOW)).toBe(true);
  });

  it('enforces each side age range against the other computed age', () => {
    const w30 = woman('w'); // 30
    expect(mutuallyCompatible(w30, man('m', {}, { ageMin: 31, ageMax: 40 }), NOW)).toBe(false);
    expect(mutuallyCompatible(w30, man('m', {}, { ageMin: 30, ageMax: 30 }), NOW)).toBe(true);
    expect(mutuallyCompatible(w30, man('m', {}, { ageMin: 18, ageMax: 29 }), NOW)).toBe(false);
    // Range is checked in both directions.
    const m45 = man('m', { birthdate: '1981-03-03' });
    expect(mutuallyCompatible(woman('w', {}, { ageMax: 40 }), m45, NOW)).toBe(false);
    expect(mutuallyCompatible(woman('w', {}, { ageMax: 45 }), m45, NOW)).toBe(true);
  });

  it('never pairs anyone under 18, whatever the filters say', () => {
    const minor = man('m', { birthdate: '2008-11-15' }); // 17 on NOW
    expect(mutuallyCompatible(woman(), minor, NOW)).toBe(false);
    expect(mutuallyCompatible(woman(), man('m', { birthdate: '2008-11-14' }), NOW)).toBe(true);
  });

  it('enforces distance when both have coordinates, using the stricter of the two limits', () => {
    const boston = { lat: 42.3601, lng: -71.0589 }; // ~300 km from NYC
    expect(mutuallyCompatible(woman('w', {}, { maxDistanceKm: 100 }), man('m', boston, { maxDistanceKm: 500 }), NOW)).toBe(false);
    expect(mutuallyCompatible(woman('w', {}, { maxDistanceKm: 500 }), man('m', boston, { maxDistanceKm: 100 }), NOW)).toBe(false);
    expect(mutuallyCompatible(woman('w', {}, { maxDistanceKm: 500 }), man('m', boston, { maxDistanceKm: 500 }), NOW)).toBe(true);
  });

  it('skips the distance check when either side has no coordinates', () => {
    const nowhere = man('m', { lat: null, lng: null }, { maxDistanceKm: 1 });
    expect(mutuallyCompatible(woman('w', {}, { maxDistanceKm: 1 }), nowhere, NOW)).toBe(true);
  });

  it('enforces advanced filters only when the filter owner is premium', () => {
    const smoker = man('m', { smoking: 'regularly', intention: 'short_term', education: 'high_school' });
    const filters: Partial<Preferences> = { smokingOk: ['never'], intentions: ['long_term', 'marriage'], minEducation: 'bachelors' };
    expect(mutuallyCompatible(woman('w', { isPremium: false }, filters), smoker, NOW)).toBe(true);
    expect(mutuallyCompatible(woman('w', { isPremium: true }, filters), smoker, NOW)).toBe(false);
  });

  it.each([
    ['intentions', { intentions: ['marriage'] }, { intention: 'marriage' }, { intention: 'short_term' }],
    ['children', { children: ['wants', 'open'] }, { children: 'open' }, { children: 'doesnt_want' }],
    ['religions', { religions: ['jewish'] }, { religion: 'jewish' }, { religion: 'atheist' }],
    ['smokingOk', { smokingOk: ['never'] }, { smoking: 'never' }, { smoking: 'sometimes' }],
    ['drinkingOk', { drinkingOk: ['never', 'socially'] }, { drinking: 'socially' }, { drinking: 'regularly' }],
    ['minEducation', { minEducation: 'bachelors' }, { education: 'masters' }, { education: 'some_college' }],
  ] as Array<[string, Partial<Preferences>, Partial<Candidate>, Partial<Candidate>]>)(
    'premium filter %s passes a match and blocks a mismatch or a blank',
    (_name, filter, pass, fail) => {
      const owner = woman('w', { isPremium: true }, filter);
      expect(satisfies(man('m', pass), owner, NOW)).toBe(true);
      expect(satisfies(man('m', fail), owner, NOW)).toBe(false);
      expect(satisfies(man('m'), owner, NOW)).toBe(false); // unset attribute fails a set dealbreaker
    },
  );

  it('minEducation treats the minimum itself as passing', () => {
    const owner = woman('w', { isPremium: true }, { minEducation: 'bachelors' });
    expect(satisfies(man('m', { education: 'bachelors' }), owner, NOW)).toBe(true);
    expect(satisfies(man('m', { education: 'doctorate' }), owner, NOW)).toBe(true);
  });

  it('the other person being premium does not turn my stored filters on', () => {
    const w = woman('w', { isPremium: false }, { smokingOk: ['never'] });
    const m = man('m', { isPremium: true, smoking: 'regularly' });
    expect(mutuallyCompatible(w, m, NOW)).toBe(true);
  });

  it('respects exclusions (blocks, existing matches, 24 h cooldown) from either side', () => {
    expect(mutuallyCompatible(woman('w', { exclusions: new Set(['m']) }), man('m'), NOW)).toBe(false);
    expect(mutuallyCompatible(woman('w'), man('m', { exclusions: new Set(['w']) }), NOW)).toBe(false);
  });
});

describe('queue ordering and pairing', () => {
  function setup(...people: Candidate[]): InMemoryMatchmaker {
    const mm = new InMemoryMatchmaker();
    for (const p of people) mm.setOnline(p);
    return mm;
  }

  it('orders premium first, then longest wait', () => {
    const mm = setup(woman('w1'), woman('w2'), woman('wp', { isPremium: true }), woman('wp2', { isPremium: true }));
    mm.enqueue('w1', 1000);
    mm.enqueue('w2', 2000);
    mm.enqueue('wp', 3000);
    mm.enqueue('wp2', 4000);
    expect(mm.queuedUserIds()).toEqual(['wp', 'wp2', 'w1', 'w2']);
    expect(mm.position('wp')).toBe(1);
    expect(mm.position('w2')).toBe(4);
    expect(mm.position('nobody')).toBe(0);
  });

  it('keeps arrival order for identical timestamps', () => {
    const mm = setup(woman('a'), woman('b'), woman('c'));
    for (const id of ['b', 'c', 'a']) mm.enqueue(id, 5000);
    expect(mm.queuedUserIds()).toEqual(['b', 'c', 'a']);
  });

  it('gives the scarce partner to the premium user even if they queued last', () => {
    const mm = setup(woman('w1'), woman('wp', { isPremium: true }), man('m'));
    mm.enqueue('w1', 1000);
    mm.enqueue('wp', 9000);
    mm.enqueue('m', 9500);
    const pairs = mm.takePairs(NOW);
    expect(pairs).toHaveLength(1);
    expect(pairs[0]?.first.userId).toBe('wp');
    expect(pairs[0]?.second.userId).toBe('m');
    expect(mm.queuedUserIds()).toEqual(['w1']);
  });

  it('among free users the longest waiting is paired first', () => {
    const mm = setup(woman('w1'), woman('w2'), man('m'));
    mm.enqueue('w2', 1000);
    mm.enqueue('w1', 2000);
    mm.enqueue('m', 3000);
    const pairs = mm.takePairs(NOW);
    expect(pairs.map((p) => [p.first.userId, p.second.userId])).toEqual([['w2', 'm']]);
  });

  it('forms several pairs in one pass and skips incompatible neighbours', () => {
    const mm = setup(woman('w1'), woman('w2'), man('m1'), man('m2'), woman('w3'));
    ['w1', 'w2', 'm1', 'm2', 'w3'].forEach((id, i) => mm.enqueue(id, 1000 + i));
    const pairs = mm.takePairs(NOW).map((p) => [p.first.userId, p.second.userId]);
    expect(pairs).toEqual([
      ['w1', 'm1'],
      ['w2', 'm2'],
    ]);
    expect(mm.queuedUserIds()).toEqual(['w3']);
  });

  it('does not pair excluded people and reacts to a new exclusion immediately', () => {
    const mm = setup(woman('w'), man('m'));
    mm.enqueue('w', 1);
    mm.enqueue('m', 2);
    mm.addExclusion('w', 'm');
    expect(mm.takePairs(NOW)).toEqual([]);
    mm.removeExclusion('w', 'm');
    expect(mm.takePairs(NOW)).toHaveLength(1);
  });

  it('counts compatible people online, queued or not, excluding self', () => {
    const w = woman('w');
    const mm = setup(w, man('m1'), man('m2'), man('m3', { interestedIn: ['man'] }), woman('w2'));
    expect(mm.compatibleOnline(w, NOW)).toBe(2);
    mm.setOffline('m1');
    expect(mm.compatibleOnline(w, NOW)).toBe(1);
  });

  it('refreshing a snapshot keeps the place in the queue; going offline leaves it', () => {
    const mm = setup(woman('w1'), woman('w2'));
    mm.enqueue('w1', 1);
    mm.enqueue('w2', 2);
    mm.setOnline(woman('w1', { isPremium: false }, { ageMax: 50 }));
    expect(mm.queuedUserIds()).toEqual(['w1', 'w2']);
    mm.setOffline('w1');
    expect(mm.queuedUserIds()).toEqual(['w2']);
    expect(mm.enqueue('ghost', 3)).toBe(false);
  });
});

describe('scoring', () => {
  const stats = (answered: number, yesGiven: number, rated: number, yesReceived: number) => ({
    answered,
    yesGiven,
    rated,
    yesReceived,
  });

  it('starts everyone at the prior and moves toward their real yes-rates with history', () => {
    expect(yesRateGiven(stats(0, 0, 0, 0))).toBeCloseTo(0.4);
    expect(yesRateReceived(stats(0, 0, 0, 0))).toBeCloseTo(0.4);
    expect(yesRateGiven(stats(1, 1, 0, 0))).toBeLessThan(0.6); // one yes is not much evidence
    expect(yesRateGiven(stats(100, 90, 0, 0))).toBeGreaterThan(0.85);
    expect(yesRateReceived(stats(0, 0, 100, 5))).toBeLessThan(0.1);
  });

  it('rates shared intentions and plans for children above conflicting ones, with unknown in between', () => {
    const w = woman('w', { intention: 'long_term', children: 'wants' });
    const same = affinity(w, man('m', { intention: 'long_term', children: 'wants' }), NOW);
    const unknown = affinity(w, man('m'), NOW);
    const clash = affinity(w, man('m', { intention: 'short_term', children: 'doesnt_want' }), NOW);
    expect(same).toBeGreaterThan(unknown);
    expect(unknown).toBeGreaterThan(clash);
  });

  it('prefers a small age gap and a short distance', () => {
    const w = woman('w');
    expect(affinity(w, man('m'), NOW)).toBeGreaterThan(affinity(w, man('m', { birthdate: '1981-01-01' }), NOW));
    expect(affinity(w, man('m'), NOW)).toBeGreaterThan(affinity(w, man('m', { lat: 41.3, lng: -73.99 }), NOW));
  });

  it('is symmetric, stays within 0..1, and strikes only ever lower it', () => {
    const w = woman('w', { intention: 'marriage', stats: stats(20, 15, 20, 12) });
    const m = man('m', { intention: 'long_term', stats: stats(10, 2, 10, 9) });
    const score = mutualScore(w, m, NOW);
    expect(score).toBeCloseTo(mutualScore(m, w, NOW));
    expect(score).toBeGreaterThan(0);
    expect(score).toBeLessThan(1);
    expect(yesProbability(w, { ...m, strikes: 2 }, NOW)).toBeLessThan(yesProbability(w, m, NOW));
    expect(yesProbability(w, { ...m, strikes: 50 }, NOW)).toBe(0);
  });
});

describe('score-based pairing', () => {
  function queue(mm: InMemoryMatchmaker, people: Candidate[], at: (index: number) => number = (i) => NOW + i): void {
    people.forEach((p, i) => {
      mm.setOnline(p);
      mm.enqueue(p.userId, at(i));
    });
  }
  const ids = (mm: InMemoryMatchmaker, now = NOW + 10): string[][] =>
    mm.takePairs(now).map((p) => [p.first.userId, p.second.userId]);

  it('gives the person at the front the better fit, not the next in line', () => {
    const mm = new InMemoryMatchmaker();
    queue(mm, [
      woman('w', { intention: 'long_term', children: 'wants' }),
      man('clash', { intention: 'short_term', children: 'doesnt_want' }),
      man('fit', { intention: 'long_term', children: 'wants' }),
    ]);
    expect(ids(mm)).toEqual([['w', 'fit']]);
    expect(mm.isQueued('clash')).toBe(true);
  });

  it('prefers the partner people tend to say yes to', () => {
    const mm = new InMemoryMatchmaker();
    queue(mm, [
      woman('w'),
      man('rarely', { stats: { answered: 30, yesGiven: 15, rated: 30, yesReceived: 2 } }),
      man('often', { stats: { answered: 30, yesGiven: 15, rated: 30, yesReceived: 24 } }),
    ]);
    expect(ids(mm)).toEqual([['w', 'often']]);
  });

  it('lets a long wait outrank a slightly better fit, but not a much better one', () => {
    const waitedLong = (i: number): number => (i === 1 ? NOW - 120_000 : NOW + i);
    const slight = new InMemoryMatchmaker();
    // 'waiting' is three years older than 'w'; 'same-age' is the marginally better fit.
    queue(slight, [woman('w', { isPremium: true }), man('waiting', { birthdate: '1993-01-01' }), man('same-age')], waitedLong);
    expect(ids(slight)).toEqual([['w', 'waiting']]);
    const noWait = new InMemoryMatchmaker();
    queue(noWait, [woman('w', { isPremium: true }), man('waiting', { birthdate: '1993-01-01' }), man('same-age')]);
    expect(ids(noWait)).toEqual([['w', 'same-age']]);

    const w = woman('w', { isPremium: true, intention: 'long_term', children: 'wants' });

    const big = new InMemoryMatchmaker();
    queue(
      big,
      [w, man('waiting', { intention: 'short_term', children: 'doesnt_want' }), man('fit', { intention: 'long_term', children: 'wants' })],
      waitedLong,
    );
    expect(ids(big)).toEqual([['w', 'fit']]);
  });

  it('still serves premium first: they get the best partner even when they queued last', () => {
    const mm = new InMemoryMatchmaker();
    queue(mm, [
      woman('free', { intention: 'long_term' }),
      man('fit', { intention: 'long_term' }),
      man('clash', { intention: 'short_term' }),
      woman('premium', { isPremium: true, intention: 'long_term' }),
    ]);
    expect(ids(mm)).toEqual([
      ['premium', 'fit'],
      ['free', 'clash'],
    ]);
  });

  it('explores: at the configured rate it picks a random compatible partner instead of the best', () => {
    const people = (): Candidate[] => [
      woman('w', { intention: 'long_term' }),
      man('fit', { intention: 'long_term' }),
      man('clash', { intention: 'short_term' }),
    ];
    const rolls = [0.05, 0.9]; // explore, then pick the last option
    const exploring = new InMemoryMatchmaker({ exploreRate: 0.1, random: () => rolls.shift() ?? 0 });
    queue(exploring, people());
    expect(ids(exploring)).toEqual([['w', 'clash']]);

    const notThisTime = new InMemoryMatchmaker({ exploreRate: 0.1, random: () => 0.5 });
    queue(notThisTime, people());
    expect(ids(notThisTime)).toEqual([['w', 'fit']]);
  });

  it('never explores past the hard filters', () => {
    const mm = new InMemoryMatchmaker({ exploreRate: 1, random: () => 0.99 });
    queue(mm, [woman('w', {}, { ageMax: 30 }), man('ok'), man('too-old', { birthdate: '1970-01-01' })]);
    expect(ids(mm)).toEqual([['w', 'ok']]);
  });
});
