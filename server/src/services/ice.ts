import { createHmac } from 'node:crypto';
import type { AppConfig } from '../config.js';
import type { IceServer } from '../types.js';
import type { Clock } from '../util.js';

/**
 * ICE server lists. STUN is public. TURN credentials are short-lived and per user, using the
 * coturn "REST API" scheme (`use-auth-secret`): username = "<expiry>:<userId>",
 * credential = base64(HMAC-SHA1(TURN_SECRET, username)).
 */
export class IceService {
  constructor(
    private readonly config: Pick<AppConfig, 'stunUrls' | 'turnUrls' | 'turnSecret' | 'turnTtlSec'>,
    private readonly clock: Clock,
  ) {}

  /** `userId` undefined = anonymous caller: STUN only, no TURN credentials are handed out. */
  serversFor(userId: string | undefined): IceServer[] {
    const servers: IceServer[] = [];
    if (this.config.stunUrls.length > 0) servers.push({ urls: this.config.stunUrls });
    if (userId !== undefined && this.config.turnUrls.length > 0 && this.config.turnSecret !== undefined) {
      const expiry = Math.floor(this.clock.now() / 1000) + this.config.turnTtlSec;
      const username = `${expiry}:${userId}`;
      const credential = createHmac('sha1', this.config.turnSecret).update(username).digest('base64');
      servers.push({ urls: this.config.turnUrls, username, credential });
    }
    return servers;
  }
}
