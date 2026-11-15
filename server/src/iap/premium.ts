import type { FastifyBaseLogger } from 'fastify';
import { PREMIUM_PRODUCT_ID } from '../appName.js';
import type { Store } from '../store/Store.js';
import type { Clock } from '../util.js';
import { IapError, type AppStoreNotification, type AppStoreTransaction, type AppStoreVerifier } from './appstore.js';

export interface PremiumState {
  isPremium: boolean;
  premiumExpiresAt: Date | null;
}

const GRANT_TYPES = new Set([
  'SUBSCRIBED',
  'DID_RENEW',
  'OFFER_REDEEMED',
  'RENEWAL_EXTENDED',
  'DID_CHANGE_RENEWAL_PREF',
  'REFUND_REVERSED',
]);
const REVOKE_TYPES = new Set(['EXPIRED', 'GRACE_PERIOD_EXPIRED', 'REFUND', 'REVOKE']);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Turns verified App Store data into premium state on the user record. */
export class PremiumService {
  constructor(
    private readonly store: Store,
    private readonly verifier: AppStoreVerifier,
    private readonly bundleId: string,
    private readonly clock: Clock,
    private readonly log: FastifyBaseLogger,
    /** Called after a user's premium state changed so live state (queue priority) can refresh. */
    private readonly onChanged: (userId: string) => Promise<void>,
  ) {}

  private check(tx: AppStoreTransaction): void {
    if (tx.bundleId !== this.bundleId) throw new IapError('wrong_bundle', 'Transaction is for a different app');
    if (tx.productId !== PREMIUM_PRODUCT_ID) throw new IapError('wrong_product', 'Transaction is for a different product');
  }

  private stateFrom(tx: AppStoreTransaction): PremiumState {
    const expires = tx.expiresDate !== undefined ? new Date(tx.expiresDate) : null;
    const active = tx.revocationDate === undefined && expires !== null && expires.getTime() > this.clock.now();
    return { isPremium: active, premiumExpiresAt: expires };
  }

  private async apply(userId: string, state: PremiumState, source: string, tx: AppStoreTransaction): Promise<void> {
    const updated = await this.store.updateUser(userId, state);
    if (!updated) return;
    await this.store.addAudit({
      type: 'iap',
      userId,
      action: state.isPremium ? 'premium_on' : 'premium_off',
      details: { source, originalTransactionId: tx.originalTransactionId, environment: tx.environment ?? null },
    });
    await this.onChanged(userId);
  }

  /** POST /v1/iap/verify */
  async verifyForUser(userId: string, jwsTransaction: string): Promise<PremiumState> {
    const tx = await this.verifier.verifyTransaction(jwsTransaction);
    this.check(tx);
    const state = this.stateFrom(tx);
    const previousOwner = await this.store.bindTransaction(tx.originalTransactionId, userId);
    if (previousOwner !== null) {
      // The same Apple ID restored the subscription on another account: it moves, it is not duplicated.
      await this.apply(previousOwner, { isPremium: false, premiumExpiresAt: null }, 'transferred', tx);
    }
    await this.apply(userId, state, 'verify', tx);
    return state;
  }

  /** POST /v1/iap/notifications (App Store Server Notifications V2). */
  async handleNotification(signedPayload: string): Promise<{ handled: boolean; type: string }> {
    const note: AppStoreNotification = await this.verifier.verifyNotification(signedPayload);
    const type = note.notificationType;
    const tx = note.transaction;
    if (tx === null) return { handled: false, type };
    if (note.bundleId !== undefined && note.bundleId !== this.bundleId) {
      throw new IapError('wrong_bundle', 'Notification is for a different app');
    }
    this.check(tx);

    let userId = await this.store.getTransactionOwner(tx.originalTransactionId);
    if (userId === null && tx.appAccountToken !== undefined && UUID_RE.test(tx.appAccountToken)) {
      const user = await this.store.getUser(tx.appAccountToken.toLowerCase());
      if (user) {
        userId = user.id;
        await this.store.bindTransaction(tx.originalTransactionId, userId);
      }
    }
    if (userId === null) {
      this.log.warn({ type, originalTransactionId: tx.originalTransactionId }, 'iap notification for unknown transaction');
      return { handled: false, type };
    }

    if (GRANT_TYPES.has(type)) {
      await this.apply(userId, this.stateFrom(tx), `notification:${type}`, tx);
      return { handled: true, type };
    }
    if (REVOKE_TYPES.has(type)) {
      const expires = tx.expiresDate !== undefined ? new Date(tx.expiresDate) : null;
      await this.apply(userId, { isPremium: false, premiumExpiresAt: expires }, `notification:${type}`, tx);
      return { handled: true, type };
    }
    // DID_FAIL_TO_RENEW, DID_CHANGE_RENEWAL_STATUS, PRICE_INCREASE, TEST, ...: nothing to change.
    // Premium lapses on its own because it is always evaluated against premiumExpiresAt.
    return { handled: false, type };
  }
}
