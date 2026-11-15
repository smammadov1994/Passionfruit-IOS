import { z } from 'zod';

// ---------------------------------------------------------------------------
// Enums (SPEC section 3, "Objects")
// ---------------------------------------------------------------------------
export const GENDERS = ['woman', 'man', 'nonbinary'] as const;
export const INTENTIONS = ['long_term', 'short_term', 'marriage', 'figuring_out'] as const;
export const CHILDREN = ['has_wants_more', 'has_done', 'wants', 'doesnt_want', 'open'] as const;
export const RELIGIONS = [
  'agnostic',
  'atheist',
  'buddhist',
  'christian',
  'hindu',
  'jewish',
  'muslim',
  'spiritual',
  'other',
] as const;
/** Ordered lowest to highest; `minEducation` compares by index. */
export const EDUCATION = ['high_school', 'some_college', 'bachelors', 'masters', 'doctorate'] as const;
export const SMOKING = ['never', 'sometimes', 'regularly'] as const;
export const DRINKING = ['never', 'socially', 'regularly'] as const;
export const REPORT_REASONS = [
  'nudity',
  'sexual_language',
  'harassment',
  'underage',
  'fake_profile',
  'spam',
  'other',
] as const;

export const GenderSchema = z.enum(GENDERS);
export const IntentionSchema = z.enum(INTENTIONS);
export const ChildrenSchema = z.enum(CHILDREN);
export const ReligionSchema = z.enum(RELIGIONS);
export const EducationSchema = z.enum(EDUCATION);
export const SmokingSchema = z.enum(SMOKING);
export const DrinkingSchema = z.enum(DRINKING);
export const ReportReasonSchema = z.enum(REPORT_REASONS);

export type Gender = z.infer<typeof GenderSchema>;
export type Intention = z.infer<typeof IntentionSchema>;
export type Children = z.infer<typeof ChildrenSchema>;
export type Religion = z.infer<typeof ReligionSchema>;
export type Education = z.infer<typeof EducationSchema>;
export type Smoking = z.infer<typeof SmokingSchema>;
export type Drinking = z.infer<typeof DrinkingSchema>;
export type ReportReason = z.infer<typeof ReportReasonSchema>;

// ---------------------------------------------------------------------------
// Preferences
// ---------------------------------------------------------------------------
export interface Preferences {
  ageMin: number;
  ageMax: number;
  maxDistanceKm: number;
  intentions?: Intention[];
  children?: Children[];
  religions?: Religion[];
  minEducation?: Education;
  smokingOk?: Smoking[];
  drinkingOk?: Drinking[];
  notifyOnlineSingles: boolean;
}

export const DEFAULT_PREFERENCES: Readonly<Preferences> = Object.freeze({
  ageMin: 18,
  ageMax: 99,
  maxDistanceKm: 100,
  notifyOnlineSingles: false,
});

const uniqueList = <T extends z.ZodType>(item: T, max: number) =>
  z
    .array(item)
    .max(max)
    .transform((list) => [...new Set(list)]);

/** `null` clears an advanced filter; an absent key leaves it as stored. */
export const PreferencesInputSchema = z
  .object({
    ageMin: z.number().int().min(18).max(99),
    ageMax: z.number().int().min(18).max(99),
    maxDistanceKm: z.number().min(1).max(20_000),
    intentions: uniqueList(IntentionSchema, INTENTIONS.length).nullish(),
    children: uniqueList(ChildrenSchema, CHILDREN.length).nullish(),
    religions: uniqueList(ReligionSchema, RELIGIONS.length).nullish(),
    minEducation: EducationSchema.nullish(),
    smokingOk: uniqueList(SmokingSchema, SMOKING.length).nullish(),
    drinkingOk: uniqueList(DrinkingSchema, DRINKING.length).nullish(),
    notifyOnlineSingles: z.boolean(),
  })
  .refine((p) => p.ageMin <= p.ageMax, { message: 'ageMin must be <= ageMax', path: ['ageMin'] });
export type PreferencesInput = z.infer<typeof PreferencesInputSchema>;

// ---------------------------------------------------------------------------
// Stored records (internal shapes; never sent over the wire as-is)
// ---------------------------------------------------------------------------
export interface UserRecord {
  id: string;
  /** Stable identity subject: Apple `sub`, or `dev:<deviceId>` for dev auth. */
  appleSub: string;
  firstName: string;
  birthdate: string | null;
  gender: Gender | null;
  interestedIn: Gender[];
  bio: string;
  city: string;
  lat: number | null;
  lng: number | null;
  photoUrls: string[];
  intention: Intention | null;
  children: Children | null;
  religion: Religion | null;
  education: Education | null;
  smoking: Smoking | null;
  drinking: Drinking | null;
  isPremium: boolean;
  premiumExpiresAt: Date | null;
  onboardingComplete: boolean;
  strikes: number;
  suspended: boolean;
  suspendedUntil: Date | null;
  preferences: Preferences;
  apnsToken: string | null;
  pushEnabled: boolean;
  /** Minutes EAST of UTC (iOS `TimeZone.current.secondsFromGMT() / 60`). */
  tzOffsetMinutes: number;
  lastOnlinePushAt: Date | null;
  createdAt: Date;
}

export type UserPatch = Partial<Omit<UserRecord, 'id' | 'appleSub' | 'createdAt'>>;

export interface DateRecord {
  id: string;
  /** Null once that participant has deleted their account. */
  userA: string | null;
  userB: string | null;
  createdAt: Date;
  startedAt: Date | null;
  endedAt: Date | null;
  endReason: string | null;
  outcome: 'match' | 'no_match' | null;
  /** Each participant's private answer; null when the date ended before the yes/no screen. */
  decisionA: 'yes' | 'no' | null;
  decisionB: 'yes' | 'no' | null;
}

export interface MatchRecord {
  id: string;
  userA: string;
  userB: string;
  dateId: string | null;
  matchedAt: Date;
}

export interface MessageRecord {
  id: string;
  matchId: string;
  senderId: string;
  text: string;
  sentAt: Date;
  clientId: string | null;
}

export interface MatchSummary {
  match: MatchRecord;
  partner: UserRecord;
  lastMessage: MessageRecord | null;
  unreadCount: number;
}

export interface ReportRecord {
  id: string;
  /** Null once the reporter has deleted their account. */
  reporterId: string | null;
  reportedUserId: string;
  dateId: string | null;
  matchId: string | null;
  reason: ReportReason;
  details: string | null;
  createdAt: Date;
}

export type AuditType =
  | 'moderation.frame'
  | 'moderation.transcript'
  | 'moderation.photo'
  | 'moderation.error'
  | 'strike'
  | 'suspension'
  | 'report'
  | 'block'
  | 'account.deleted'
  | 'iap';

export interface AuditEvent {
  id: string;
  type: AuditType;
  /** The user the event is about (offender / actor). */
  userId: string | null;
  /** The other party when there is one (reported user, blocked user, date partner). */
  targetUserId: string | null;
  dateId: string | null;
  matchId: string | null;
  category: string | null;
  action: string | null;
  details: Record<string, unknown>;
  createdAt: Date;
}
export type AuditInput = Partial<Omit<AuditEvent, 'id' | 'createdAt' | 'type'>> & { type: AuditType };

// ---------------------------------------------------------------------------
// Wire objects
// ---------------------------------------------------------------------------
export interface WireUser {
  id: string;
  firstName: string;
  birthdate: string;
  gender: Gender;
  interestedIn: Gender[];
  bio: string;
  city: string;
  lat?: number;
  lng?: number;
  photoUrls: string[];
  intention?: Intention;
  children?: Children;
  religion?: Religion;
  education?: Education;
  smoking?: Smoking;
  drinking?: Drinking;
  isPremium: boolean;
  premiumExpiresAt?: string;
  onboardingComplete: boolean;
  strikes: number;
  suspendedUntil?: string;
  preferences: Preferences;
}

export interface WirePartner {
  id: string;
  firstName: string;
  age: number;
  city: string;
  distanceKm?: number;
  photoUrl?: string;
  intention?: Intention;
}

export interface WireMessage {
  id: string;
  matchId: string;
  senderId: string;
  text: string;
  sentAt: string;
  clientId?: string;
}

export interface WireMatch {
  id: string;
  partner: WirePartner;
  matchedAt: string;
  lastMessage?: WireMessage;
  unreadCount: number;
}

export interface IceServer {
  urls: string[];
  username?: string;
  credential?: string;
}

export type ModerationAction = 'none' | 'warn' | 'end';
export type ModerationCategory = 'nudity' | 'sexual_language';
export type DateEndReason = 'timer' | 'partner_left' | 'you_left' | 'moderation' | 'disconnect' | 'checkpoint';
