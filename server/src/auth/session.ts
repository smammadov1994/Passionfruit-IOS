import { jwtVerify, SignJWT } from 'jose';
import { APP_NAME } from '../appName.js';

const ISSUER = APP_NAME.toLowerCase();

/** Our own session tokens: HS256 JWTs carrying only the user id. */
export class SessionTokens {
  private readonly key: Uint8Array;

  constructor(
    secret: string,
    private readonly ttlDays: number,
  ) {
    this.key = new TextEncoder().encode(secret);
  }

  async issue(userId: string): Promise<string> {
    return new SignJWT({})
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setSubject(userId)
      .setIssuer(ISSUER)
      .setIssuedAt()
      .setExpirationTime(`${this.ttlDays}d`)
      .sign(this.key);
  }

  /** Returns the user id, or null if the token is missing, malformed, forged or expired. */
  async verify(token: string): Promise<string | null> {
    try {
      const { payload } = await jwtVerify(token, this.key, { algorithms: ['HS256'], issuer: ISSUER });
      return typeof payload.sub === 'string' && payload.sub.length > 0 ? payload.sub : null;
    } catch {
      return null;
    }
  }
}
