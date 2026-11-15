import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import { badRequest, forbidden, notFound } from '../errors.js';
import { CALL_PREFIX } from '../realtime/protocol.js';
import { RATE_RULES } from '../services/rateLimit.js';
import { ReportReasonSchema } from '../types.js';
import { decodeJpeg, parse, UuidSchema } from './helpers.js';

const MAX_FRAME_BYTES = 1024 * 1024;

/** A speed-date id or `call:<matchId>`. */
const SessionId = z
  .string()
  .max(64)
  .refine(
    (v) => UuidSchema.safeParse(v.startsWith(CALL_PREFIX) ? v.slice(CALL_PREFIX.length) : v).success,
    'must be a date id',
  );

const ReportBody = z.object({
  userId: UuidSchema,
  dateId: SessionId.nullish(),
  matchId: UuidSchema.nullish(),
  reason: ReportReasonSchema,
  details: z.string().trim().max(1000).nullish(),
});
const BlockBody = z.object({ userId: UuidSchema });
const FrameBody = z.object({ dateId: SessionId, imageBase64: z.string().min(1) });
const TranscriptBody = z.object({ dateId: SessionId, text: z.string().max(4000) });

export function registerSafetyRoutes(app: FastifyInstance, ctx: AppContext): void {
  app.post('/v1/reports', async (request, reply) => {
    const user = await ctx.authenticate(request);
    ctx.rateLimiter.enforce(RATE_RULES.report, user.id);
    const body = parse(ReportBody, request.body);
    if (body.userId === user.id) throw badRequest('invalid_request', "You can't report yourself.");

    // A report may only cite a date or match that the reporter and the reported person share.
    let dateId: string | null = null;
    let matchId: string | null = body.matchId ?? null;
    if (body.dateId != null) {
      if (body.dateId.startsWith(CALL_PREFIX)) matchId = matchId ?? body.dateId.slice(CALL_PREFIX.length);
      else dateId = body.dateId;
    }
    if (dateId !== null) {
      const date = await ctx.store.getDate(dateId);
      const mine = date !== null && (date.userA === user.id || date.userB === user.id);
      const theirs = date !== null && (date.userA === body.userId || date.userB === body.userId);
      // `theirs` can legitimately be false only when the reported account has since been deleted.
      const partnerGone = date !== null && (date.userA === null || date.userB === null);
      if (!mine || (!theirs && !partnerGone)) throw forbidden('forbidden', "That date isn't yours to report.");
    }
    if (matchId !== null) {
      const match = await ctx.store.getMatch(matchId);
      // A match that no longer exists (unmatched first, then reported) is accepted as context.
      if (match) {
        const members = [match.userA, match.userB];
        if (!members.includes(user.id) || !members.includes(body.userId)) {
          throw forbidden('forbidden', "That match isn't yours to report.");
        }
      }
    }

    const report = await ctx.store.addReport({
      reporterId: user.id,
      reportedUserId: body.userId,
      dateId,
      matchId,
      reason: body.reason,
      details: body.details != null && body.details.length > 0 ? body.details : null,
      createdAt: new Date(ctx.clock.now()),
    });
    await ctx.store.addAudit({
      type: 'report',
      userId: body.userId,
      targetUserId: user.id,
      dateId,
      matchId,
      category: body.reason,
      action: 'reported',
      details: { reportId: report.id },
    });
    return reply.code(204).send();
  });

  app.post('/v1/blocks', async (request, reply) => {
    const user = await ctx.authenticate(request);
    ctx.rateLimiter.enforce(RATE_RULES.block, user.id);
    const body = parse(BlockBody, request.body);
    if (body.userId === user.id) throw badRequest('invalid_request', "You can't block yourself.");
    if (!(await ctx.store.getUser(body.userId))) throw notFound('That person is no longer here.');
    await ctx.accounts.block(user.id, body.userId);
    return reply.code(204).send();
  });

  app.post('/v1/moderation/frame', { bodyLimit: 2 * 1024 * 1024 }, async (request) => {
    const user = await ctx.authenticate(request);
    ctx.rateLimiter.enforce(RATE_RULES.frame, user.id);
    const body = parse(FrameBody, request.body);
    const jpeg = decodeJpeg(body.imageBase64, MAX_FRAME_BYTES);
    // The frame lives only in this request's memory: classified, then dropped.
    return { action: await ctx.moderation.handleFrame(user.id, body.dateId, jpeg) };
  });

  app.post('/v1/moderation/transcript', async (request) => {
    const user = await ctx.authenticate(request);
    ctx.rateLimiter.enforce(RATE_RULES.transcript, user.id);
    const body = parse(TranscriptBody, request.body);
    return { action: await ctx.moderation.handleTranscript(user.id, body.dateId, body.text) };
  });
}
