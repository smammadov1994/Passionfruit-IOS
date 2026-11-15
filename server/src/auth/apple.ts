import { decodeProtectedHeader, importJWK, jwtVerify, type JWK } from 'jose';
import { z } from 'zod';
import type { Clock } from '../util.js';

export const APPLE_ISSUER = 'https://appleid.apple.com';
export const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';

const JwksSchema = z.object({
  keys: z.array(z.object({ kty: z.string(), kid: z.string(), n: z.string(), e: z.string() }).passthrough()),
});

export type JwksFetcher = () => Promise<unknown>;

export const defaultJwksFetcher: JwksFetcher = async () => {
  const res = await fetch(APPLE_JWKS_URL, { signal: AbortSignal.timeout(5000) });
  if (!res.ok) throw new Error(`Apple JWKS fetch failed with HTTP ${res.status}`);
  return res.json();
};

export class AppleAuthError extends Error {}

type VerifyKey = Awaited<ReturnType<typeof importJWK>>;

/**
 * Verifies "Sign in with Apple" identity tokens: RS256 signature against Apple's JWKS,
 * `iss`, `aud` (our bundle id) and `exp`. Keys are cached and refreshed on an unknown `kid`
 * (at most once a minute) or after an hour.
 */
export class AppleIdentityVerifier {
  private keys = new Map<string, VerifyKey>();
  private fetchedAt = 0;
  private inflight: Promise<void> | null = null;

  static readonly CACHE_TTL_MS = 60 * 60 * 1000;
  static readonly MIN_REFETCH_MS = 60 * 1000;

  constructor(
    private readonly bundleId: string,
    private readonly fetcher: JwksFetcher,
    private readonly clock: Clock,
  ) {}

  async verify(identityToken: string): Promise<{ sub: string }> {
    let kid: string | undefined;
    try {
      const header = decodeProtectedHeader(identityToken);
      if (header.alg !== 'RS256') throw new AppleAuthError('Unexpected token algorithm');
      kid = header.kid;
    } catch (err) {
      if (err instanceof AppleAuthError) throw err;
      throw new AppleAuthError('Malformed identity token');
    }
    if (kid === undefined) throw new AppleAuthError('Identity token has no key id');

    const key = await this.keyFor(kid);
    try {
      const { payload } = await jwtVerify(identityToken, key, {
        algorithms: ['RS256'],
        issuer: APPLE_ISSUER,
        audience: this.bundleId,
        currentDate: new Date(this.clock.now()),
      });
      if (typeof payload.sub !== 'string' || payload.sub.length === 0) {
        throw new AppleAuthError('Identity token has no subject');
      }
      if (typeof payload.exp !== 'number') throw new AppleAuthError('Identity token has no expiry');
      return { sub: payload.sub };
    } catch (err) {
      if (err instanceof AppleAuthError) throw err;
      throw new AppleAuthError('Identity token failed verification');
    }
  }

  private async keyFor(kid: string): Promise<VerifyKey> {
    const now = this.clock.now();
    const stale = now - this.fetchedAt > AppleIdentityVerifier.CACHE_TTL_MS;
    let key = this.keys.get(kid);
    if (key === undefined || stale) {
      const mayRefetch = this.fetchedAt === 0 || stale || now - this.fetchedAt > AppleIdentityVerifier.MIN_REFETCH_MS;
      if (mayRefetch) {
        try {
          await this.refresh();
        } catch (err) {
          // Keep serving from a stale cache if Apple is briefly unreachable.
          if (key === undefined) throw new AppleAuthError(`Could not load Apple signing keys: ${String(err)}`);
        }
      }
      key = this.keys.get(kid);
    }
    if (key === undefined) throw new AppleAuthError('Identity token was signed with an unknown key');
    return key;
  }

  private refresh(): Promise<void> {
    this.inflight ??= (async () => {
      try {
        const parsed = JwksSchema.parse(await this.fetcher());
        const next = new Map<string, VerifyKey>();
        for (const jwk of parsed.keys) {
          if (jwk.kty !== 'RSA') continue;
          next.set(jwk.kid, await importJWK(jwk as JWK, 'RS256'));
        }
        if (next.size === 0) throw new Error('Apple JWKS contained no RSA keys');
        this.keys = next;
        this.fetchedAt = this.clock.now();
      } finally {
        this.inflight = null;
      }
    })();
    return this.inflight;
  }
}
