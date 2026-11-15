import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { AppleAuthError } from '../auth/apple.js';
import type { AppContext } from '../context.js';
import { HttpError, notFound } from '../errors.js';
import { RATE_RULES } from '../services/rateLimit.js';
import { toWireUser } from '../services/serialize.js';
import { clientIp, parse } from './helpers.js';

const AppleBody = z.object({
  identityToken: z.string().min(20).max(8192),
  firstName: z.string().trim().max(40).optional(),
});
const DevBody = z.object({ deviceId: z.string().trim().min(1).max(128) });

export function registerAuthRoutes(app: FastifyInstance, ctx: AppContext): void {
  app.post('/v1/auth/apple', async (request) => {
    ctx.rateLimiter.enforce(RATE_RULES.auth, clientIp(request));
    const body = parse(AppleBody, request.body);
    let sub: string;
    try {
      ({ sub } = await ctx.apple.verify(body.identityToken));
    } catch (err) {
      if (err instanceof AppleAuthError) {
        request.log.info({ reason: err.message }, 'apple sign-in rejected');
        throw new HttpError(401, 'invalid_identity_token', 'Sign in with Apple could not be verified. Try again.');
      }
      throw err;
    }
    const user = await ctx.accounts.signIn(`apple:${sub}`, body.firstName === '' ? undefined : body.firstName);
    return { token: await ctx.sessions.issue(user.id), user: toWireUser(user, ctx.clock.now()) };
  });

  app.post('/v1/auth/dev', async (request) => {
    // Indistinguishable from a missing route unless explicitly enabled.
    if (!ctx.config.allowDevAuth) throw notFound();
    ctx.rateLimiter.enforce(RATE_RULES.auth, clientIp(request));
    const body = parse(DevBody, request.body);
    const user = await ctx.accounts.signIn(`dev:${body.deviceId}`, undefined);
    return { token: await ctx.sessions.issue(user.id), user: toWireUser(user, ctx.clock.now()) };
  });
}
