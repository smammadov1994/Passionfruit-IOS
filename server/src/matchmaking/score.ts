import type { Children, Drinking, Intention, Smoking } from '../types.js';
import { ageFromBirthdate } from '../util.js';
import { distanceBetween, type Candidate } from './compat.js';

/**
 * Ranking for pairs that already passed the hard filters in `compat.ts`.
 *
 * `mutualScore(a, b)` estimates the chance that both people say yes after the date. Phase 1 uses
 * hand-set weights; every date's private answers are stored (`dates.decision_a/_b`) so the weights
 * can later be fitted to real outcomes without touching callers.
 *
 * Inputs are stated profile fields and behaviour only. Photos are never scored.
 */

/** A person's history of private yes/no answers, from finished dates. */
export interface DateStats {
  /** Dates where this person's own answer was recorded. */
  answered: number;
  /** Of those, how often they said yes. */
  yesGiven: number;
  /** Dates where the partner's answer was recorded. */
  rated: number;
  /** Of those, how often the partner said yes to this person. */
  yesReceived: number;
}

export const NO_STATS: DateStats = { answered: 0, yesGiven: 0, rated: 0, yesReceived: 0 };

/** Yes-rate assumed for someone with no history, and how many dates it takes to outweigh it. */
const PRIOR_YES_RATE = 0.4;
const PRIOR_WEIGHT = 5;

const WEIGHT_SELECTIVITY = 0.3;
const WEIGHT_DESIRABILITY = 0.3;
const WEIGHT_AFFINITY = 0.4;

/** Each moderation strike on the person being judged lowers the score; it never raises it. */
const STRIKE_PENALTY = 0.15;
const NEUTRAL = 0.5;

const clamp01 = (x: number): number => Math.min(1, Math.max(0, x));

function smoothedRate(yes: number, total: number): number {
  return (yes + PRIOR_YES_RATE * PRIOR_WEIGHT) / (total + PRIOR_WEIGHT);
}

/** How readily this person says yes, pulled toward the prior until they have history. */
export function yesRateGiven(stats: DateStats): number {
  return smoothedRate(stats.yesGiven, stats.answered);
}

/** How often partners say yes to this person, pulled toward the prior until they have history. */
export function yesRateReceived(stats: DateStats): number {
  return smoothedRate(stats.yesReceived, stats.rated);
}

function intentionFit(a: Intention | null, b: Intention | null): number {
  if (a === null || b === null) return NEUTRAL;
  if (a === b) return 1;
  if (a === 'figuring_out' || b === 'figuring_out') return 0.5;
  const serious = (x: Intention): boolean => x === 'long_term' || x === 'marriage';
  if (serious(a) && serious(b)) return 0.8;
  return 0.1; // short-term with long-term or marriage
}

function childrenFit(a: Children | null, b: Children | null): number {
  if (a === null || b === null) return NEUTRAL;
  if (a === b) return 1;
  if (a === 'open' || b === 'open') return 0.7;
  const wantsMore = (x: Children): boolean => x === 'wants' || x === 'has_wants_more';
  const noMore = (x: Children): boolean => x === 'doesnt_want' || x === 'has_done';
  if (wantsMore(a) && wantsMore(b)) return 0.9;
  if (noMore(a) && noMore(b)) return 0.7;
  return 0.1; // one wants (more) children, the other does not
}

const HABIT_LEVELS: Record<Smoking | Drinking, number> = { never: 0, sometimes: 1, socially: 1, regularly: 2 };

function habitFit(a: Smoking | Drinking | null, b: Smoking | Drinking | null): number {
  if (a === null || b === null) return NEUTRAL;
  const gap = Math.abs(HABIT_LEVELS[a] - HABIT_LEVELS[b]);
  return gap === 0 ? 1 : gap === 1 ? 0.6 : 0.2;
}

function ageFit(a: Candidate, b: Candidate, nowMs: number): number {
  const gap = Math.abs(ageFromBirthdate(a.birthdate, nowMs) - ageFromBirthdate(b.birthdate, nowMs));
  return 1 - 0.7 * Math.min(gap, 15) / 15; // 1 at the same age, 0.3 from 15 years apart
}

function distanceFit(a: Candidate, b: Candidate): number {
  const km = distanceBetween(a, b);
  if (km === null) return 0.7;
  return 1 - 0.6 * Math.min(km, 100) / 100; // 1 next door, 0.4 from 100 km
}

/** Symmetric 0..1 fit from stated profile fields. A field either side left empty counts as neutral. */
export function affinity(a: Candidate, b: Candidate, nowMs: number): number {
  const religion = a.religion === null || b.religion === null ? NEUTRAL : a.religion === b.religion ? 1 : 0.4;
  return (
    0.3 * intentionFit(a.intention, b.intention) +
    0.2 * childrenFit(a.children, b.children) +
    0.15 * ageFit(a, b, nowMs) +
    0.15 * distanceFit(a, b) +
    0.1 * religion +
    0.05 * habitFit(a.smoking, b.smoking) +
    0.05 * habitFit(a.drinking, b.drinking)
  );
}

/** Estimated chance that `judge` says yes to `subject`. */
export function yesProbability(judge: Candidate, subject: Candidate, nowMs: number): number {
  const base =
    WEIGHT_SELECTIVITY * yesRateGiven(judge.stats) +
    WEIGHT_DESIRABILITY * yesRateReceived(subject.stats) +
    WEIGHT_AFFINITY * affinity(judge, subject, nowMs);
  return clamp01(base * (1 - STRIKE_PENALTY * Math.max(0, subject.strikes)));
}

/** Estimated chance of a match: both say yes. Symmetric in its arguments. */
export function mutualScore(a: Candidate, b: Candidate, nowMs: number): number {
  return yesProbability(a, b, nowMs) * yesProbability(b, a, nowMs);
}
