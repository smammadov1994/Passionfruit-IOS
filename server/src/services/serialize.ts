import { distanceBetween, isPremiumActive } from '../matchmaking/compat.js';
import type {
  MatchSummary,
  MessageRecord,
  Preferences,
  UserRecord,
  WireMatch,
  WireMessage,
  WirePartner,
  WireUser,
} from '../types.js';
import { ageFromBirthdate, iso } from '../util.js';

/** Drops undefined/empty advanced filters so the wire object only carries what is set. */
export function toWirePreferences(p: Preferences): Preferences {
  const out: Preferences = {
    ageMin: p.ageMin,
    ageMax: p.ageMax,
    maxDistanceKm: p.maxDistanceKm,
    notifyOnlineSingles: p.notifyOnlineSingles,
  };
  if (p.intentions && p.intentions.length > 0) out.intentions = p.intentions;
  if (p.children && p.children.length > 0) out.children = p.children;
  if (p.religions && p.religions.length > 0) out.religions = p.religions;
  if (p.minEducation !== undefined) out.minEducation = p.minEducation;
  if (p.smokingOk && p.smokingOk.length > 0) out.smokingOk = p.smokingOk;
  if (p.drinkingOk && p.drinkingOk.length > 0) out.drinkingOk = p.drinkingOk;
  return out;
}

/**
 * The spec's `User`. Optional fields are omitted when unset. Before onboarding, `birthdate` is
 * the empty string and `gender` is omitted (see NOTES-backend.md).
 */
export function toWireUser(u: UserRecord, nowMs: number): WireUser {
  const premium = isPremiumActive(u, nowMs);
  const out: Record<string, unknown> = {
    id: u.id,
    firstName: u.firstName,
    birthdate: u.birthdate ?? '',
    interestedIn: u.interestedIn,
    bio: u.bio,
    city: u.city,
    photoUrls: u.photoUrls,
    isPremium: premium,
    onboardingComplete: u.onboardingComplete,
    strikes: u.strikes,
    preferences: toWirePreferences(u.preferences),
  };
  if (u.gender !== null) out.gender = u.gender;
  if (u.lat !== null && u.lng !== null) {
    out.lat = u.lat;
    out.lng = u.lng;
  }
  if (u.intention !== null) out.intention = u.intention;
  if (u.children !== null) out.children = u.children;
  if (u.religion !== null) out.religion = u.religion;
  if (u.education !== null) out.education = u.education;
  if (u.smoking !== null) out.smoking = u.smoking;
  if (u.drinking !== null) out.drinking = u.drinking;
  if (premium && u.premiumExpiresAt !== null) out.premiumExpiresAt = iso(u.premiumExpiresAt);
  if (u.suspended && u.suspendedUntil !== null) out.suspendedUntil = iso(u.suspendedUntil);
  return out as unknown as WireUser;
}

/** Whole kilometres, never 0, so both Int and Double decoders accept it. */
export function wireDistance(km: number | null): number | undefined {
  return km === null ? undefined : Math.max(1, Math.round(km));
}

export interface PartnerSource {
  id: string;
  firstName: string;
  birthdate: string | null;
  city: string;
  lat: number | null;
  lng: number | null;
  photoUrl: string | null;
  intention: UserRecord['intention'];
}

export function toPartner(
  partner: PartnerSource,
  viewer: { lat: number | null; lng: number | null },
  nowMs: number,
): WirePartner {
  const out: WirePartner = {
    id: partner.id,
    firstName: partner.firstName,
    age: partner.birthdate !== null ? Math.max(0, ageFromBirthdate(partner.birthdate, nowMs)) : 0,
    city: partner.city,
  };
  const distance = wireDistance(distanceBetween(partner, viewer));
  if (distance !== undefined) out.distanceKm = distance;
  if (partner.photoUrl !== null) out.photoUrl = partner.photoUrl;
  if (partner.intention !== null) out.intention = partner.intention;
  return out;
}

export const partnerSourceFromUser = (u: UserRecord): PartnerSource => ({
  id: u.id,
  firstName: u.firstName,
  birthdate: u.birthdate,
  city: u.city,
  lat: u.lat,
  lng: u.lng,
  photoUrl: u.photoUrls[0] ?? null,
  intention: u.intention,
});

export function toWireMessage(m: MessageRecord): WireMessage {
  const out: WireMessage = {
    id: m.id,
    matchId: m.matchId,
    senderId: m.senderId,
    text: m.text,
    sentAt: iso(m.sentAt),
  };
  if (m.clientId !== null) out.clientId = m.clientId;
  return out;
}

export function toWireMatch(s: MatchSummary, viewer: UserRecord, nowMs: number): WireMatch {
  const out: WireMatch = {
    id: s.match.id,
    partner: toPartner(partnerSourceFromUser(s.partner), viewer, nowMs),
    matchedAt: iso(s.match.matchedAt),
    unreadCount: s.unreadCount,
  };
  if (s.lastMessage !== null) out.lastMessage = toWireMessage(s.lastMessage);
  return out;
}
