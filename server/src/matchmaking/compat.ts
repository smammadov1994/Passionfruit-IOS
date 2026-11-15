import {
  EDUCATION,
  type Children,
  type Drinking,
  type Education,
  type Gender,
  type Intention,
  type Preferences,
  type Religion,
  type Smoking,
  type UserRecord,
} from '../types.js';
import { ageFromBirthdate, haversineKm } from '../util.js';
import { NO_STATS, type DateStats } from './score.js';

/** Everything the matchmaker needs to know about a person; a snapshot of their profile. */
export interface Candidate {
  userId: string;
  birthdate: string;
  gender: Gender;
  interestedIn: Gender[];
  lat: number | null;
  lng: number | null;
  intention: Intention | null;
  children: Children | null;
  religion: Religion | null;
  education: Education | null;
  smoking: Smoking | null;
  drinking: Drinking | null;
  /** What a partner is shown on `date.matched`. */
  display: { firstName: string; city: string; photoUrl: string | null };
  /** Effective premium status (already checked against expiry). */
  isPremium: boolean;
  preferences: Preferences;
  /** User ids this person can never be paired with right now (blocks, matches, 24 h cooldown). */
  exclusions: Set<string>;
  /** Yes/no history and moderation strikes; ranking inputs only, never a filter (see `score.ts`). */
  stats: DateStats;
  strikes: number;
}

export function isPremiumActive(user: Pick<UserRecord, 'isPremium' | 'premiumExpiresAt'>, nowMs: number): boolean {
  return user.isPremium && (user.premiumExpiresAt === null || user.premiumExpiresAt.getTime() > nowMs);
}

/** Builds a candidate, or null when the profile is not complete enough to be matched. */
export function candidateFromUser(
  user: UserRecord,
  exclusions: Iterable<string>,
  nowMs: number,
  stats: DateStats = NO_STATS,
): Candidate | null {
  if (user.birthdate === null || user.gender === null || user.interestedIn.length === 0) return null;
  return {
    userId: user.id,
    birthdate: user.birthdate,
    gender: user.gender,
    interestedIn: user.interestedIn,
    lat: user.lat,
    lng: user.lng,
    intention: user.intention,
    children: user.children,
    religion: user.religion,
    education: user.education,
    smoking: user.smoking,
    drinking: user.drinking,
    display: { firstName: user.firstName, city: user.city, photoUrl: user.photoUrls[0] ?? null },
    isPremium: isPremiumActive(user, nowMs),
    preferences: user.preferences,
    exclusions: new Set(exclusions),
    stats,
    strikes: user.strikes,
  };
}

export function distanceBetween(
  a: { lat: number | null; lng: number | null },
  b: { lat: number | null; lng: number | null },
): number | null {
  if (a.lat === null || a.lng === null || b.lat === null || b.lng === null) return null;
  return haversineKm(a.lat, a.lng, b.lat, b.lng);
}

const listAllows = <T>(allowed: readonly T[] | undefined, value: T | null): boolean =>
  allowed === undefined || allowed.length === 0 || (value !== null && allowed.includes(value));

/**
 * Does `person` satisfy `owner`'s preferences?
 * Advanced filters only count when the owner of the filter is premium. A set advanced filter is a
 * dealbreaker: a person who has not filled that field in does not pass it.
 */
export function satisfies(person: Candidate, owner: Candidate, nowMs: number): boolean {
  const prefs = owner.preferences;
  const age = ageFromBirthdate(person.birthdate, nowMs);
  if (age < 18 || age < prefs.ageMin || age > prefs.ageMax) return false;
  if (!owner.interestedIn.includes(person.gender)) return false;

  const distance = distanceBetween(person, owner);
  if (distance !== null && distance > prefs.maxDistanceKm) return false;

  if (owner.isPremium) {
    if (!listAllows(prefs.intentions, person.intention)) return false;
    if (!listAllows(prefs.children, person.children)) return false;
    if (!listAllows(prefs.religions, person.religion)) return false;
    if (!listAllows(prefs.smokingOk, person.smoking)) return false;
    if (!listAllows(prefs.drinkingOk, person.drinking)) return false;
    if (prefs.minEducation !== undefined) {
      if (person.education === null) return false;
      if (EDUCATION.indexOf(person.education) < EDUCATION.indexOf(prefs.minEducation)) return false;
    }
  }
  return true;
}

/** The pairing predicate from SPEC "Matching rules". */
export function mutuallyCompatible(a: Candidate, b: Candidate, nowMs: number): boolean {
  if (a.userId === b.userId) return false;
  if (a.exclusions.has(b.userId) || b.exclusions.has(a.userId)) return false;
  return satisfies(a, b, nowMs) && satisfies(b, a, nowMs);
}
