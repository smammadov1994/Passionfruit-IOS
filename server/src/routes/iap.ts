import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../context.js';
import { HttpError } from '../errors.js';
import { IapError } from '../iap/appstore.js';
import { RATE_RULES } from '../services/rateLimit.js';
import { clientIp, parse } from './helpers.js';
import { iso } from '../util.js';

const VerifyBody = z.object({ jwsTransaction: z.string().min(1).max(64_000) });
const NotificationBody = z.object({ signedPayload: z.string().min(1).max(200_000) });

function toHttp(err: IapError): HttpError {
  switch (err.code) {
    case 'iap_not_configured':
      return new HttpError(503, err.code, 'Purchases are temporarily unavailable. Try again later.');
    case 'wrong_bundle':
    case 'wrong_product':
      return new HttpError(400, err.code, "That purchase doesn't belong to this app.");
    default:
      return new HttpError(400, err.code, "We couldn't verify that purchase. Try restoring it.");
  }
}

export function registerIapRoutes(app: FastifyInstance, ctx: AppContext): void {
  app.post('/v1/iap/verify', async (request) => {
    const user = await ctx.authenticate(request);
    ctx.rateLimiter.enforce(RATE_RULES.iap, user.id);
    const body = parse(VerifyBody, request.body);
    try {
      const state = await ctx.premium.verifyForUser(user.id, body.jwsTransaction);
      return {
        isPremium: state.isPremium,
        premiumExpiresAt: state.premiumExpiresAt !== null ? iso(state.premiumExpiresAt) : null,
      };
    } catch (err) {
      if (err instanceof IapError) {
        request.log.info({ code: err.code, reason: err.message }, 'iap verify rejected');
        throw toHttp(err);
      }
      throw err;
    }
  });

  // App Store Server Notifications V2. Unauthenticated by design: the signed payload is the credential.
  app.post('/v1/iap/notifications', { bodyLimit: 512 * 1024 }, async (request) => {
    ctx.rateLimiter.enforce(RATE_RULES.webhook, clientIp(request));
    const body = parse(NotificationBody, request.body);
    try {
      const result = await ctx.premium.handleNotification(body.signedPayload);
      request.log.info(result, 'iap notification processed');
      // Always 200 for a validly signed notification so Apple does not retry ones we chose to ignore.
      return { ok: true };
    } catch (err) {
      if (err instanceof IapError) {
        request.log.warn({ code: err.code, reason: err.message }, 'iap notification rejected');
        throw toHttp(err);
      }
      throw err;
    }
  });
}
