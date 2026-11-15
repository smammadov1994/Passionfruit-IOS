import { z } from 'zod';
import type {
  DateEndReason,
  IceServer,
  ModerationCategory,
  WireMatch,
  WireMessage,
  WirePartner,
} from '../types.js';

const Uuid = z.string().uuid();
/** A speed-date id, or `call:<matchId>` for a post-match call. */
const SignalTarget = z.string().min(1).max(64);

/** Relayed verbatim to the partner; unknown keys are kept. */
export const SignalPayloadSchema = z
  .object({
    kind: z.enum(['offer', 'answer', 'ice']),
    sdp: z.string().max(100_000).nullish(),
    candidate: z.string().max(4_000).nullish(),
    sdpMid: z.string().max(256).nullish(),
    sdpMLineIndex: z.number().int().min(0).max(1024).nullish(),
  })
  .passthrough();
export type SignalPayload = z.infer<typeof SignalPayloadSchema>;

export const ClientMessageSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('queue.join') }),
  z.object({ type: z.literal('queue.leave') }),
  z.object({ type: z.literal('date.ready'), dateId: Uuid }),
  z.object({ type: z.literal('rtc.signal'), dateId: SignalTarget, payload: SignalPayloadSchema }),
  z.object({ type: z.literal('turn.pass'), dateId: Uuid }),
  z.object({ type: z.literal('date.leave'), dateId: Uuid }),
  z.object({ type: z.literal('date.decide'), dateId: Uuid, decision: z.enum(['yes', 'no']) }),
  z.object({ type: z.literal('date.continue'), dateId: Uuid, choice: z.enum(['continue', 'end']) }),
  z.object({ type: z.literal('call.invite'), matchId: Uuid }),
  z.object({ type: z.literal('call.accept'), matchId: Uuid }),
  z.object({ type: z.literal('call.decline'), matchId: Uuid }),
  z.object({ type: z.literal('call.end'), matchId: Uuid }),
  z.object({ type: z.literal('ping') }),
]);
export type ClientMessage = z.infer<typeof ClientMessageSchema>;

export type ServerMessage =
  | { type: 'queue.status'; compatibleOnline: number; position: number }
  | { type: 'queue.limit'; limit: number; resetsAt: string }
  | { type: 'date.matched'; dateId: string; partner: WirePartner; role: 'caller' | 'callee'; iceServers: IceServer[] }
  | { type: 'date.started'; dateId: string; startsAt: string; endsAt: string }
  | { type: 'rtc.signal'; dateId: string; payload: SignalPayload }
  | {
      type: 'icebreaker.turn';
      dateId: string;
      question: string;
      questionIndex: number;
      speakerId: string;
      turnEndsAt: string;
      turnDurationSec: number;
    }
  /** After the first question: audio and video pause and both vote privately until `deadline`. */
  | { type: 'date.checkpoint'; dateId: string; deadline: string }
  /** Both voted to carry on. The date clock was paused; `endsAt` is the new end. */
  | { type: 'date.resumed'; dateId: string; endsAt: string }
  | { type: 'date.ended'; dateId: string; reason: DateEndReason; decisionDeadline?: string }
  | { type: 'date.result'; dateId: string; outcome: 'match' | 'no_match'; match?: WireMatch }
  | {
      type: 'moderation.action';
      dateId: string;
      action: 'warn' | 'end';
      category: ModerationCategory;
      message: string;
    }
  | { type: 'chat.message'; message: WireMessage }
  | { type: 'match.removed'; matchId: string }
  | { type: 'call.invite' | 'call.accept' | 'call.decline' | 'call.end'; matchId: string; fromUserId: string }
  | { type: 'account.suspended'; until?: string; reason: string }
  | { type: 'error'; code: string; message: string }
  | { type: 'pong' };

/** WebSocket close codes used by the server (4000-4999 is the application range). */
export const CLOSE = {
  replaced: 4000,
  idle: 4001,
  accountDeleted: 4002,
  flood: 4003,
  shutdown: 1001,
} as const;

export const CALL_PREFIX = 'call:';
