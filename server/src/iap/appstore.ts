import { X509Certificate } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { compactVerify, decodeProtectedHeader } from 'jose';
import { z } from 'zod';
import type { Clock } from '../util.js';

export class IapError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

/** DER encodings of the Apple extension OIDs that mark App Store signing certificates. */
const OID_LEAF_RECEIPT_SIGNING = Buffer.from('060a2a864886f76364060b01', 'hex'); // 1.2.840.113635.100.6.11.1
const OID_INTERMEDIATE_WWDR = Buffer.from('060a2a864886f763640602 01'.replace(/ /g, ''), 'hex'); // 1.2.840.113635.100.6.2.1

const TransactionSchema = z.object({
  bundleId: z.string(),
  productId: z.string(),
  transactionId: z.coerce.string(),
  originalTransactionId: z.coerce.string(),
  expiresDate: z.number().optional(),
  revocationDate: z.number().optional(),
  environment: z.string().optional(),
  appAccountToken: z.string().optional(),
});
export type AppStoreTransaction = z.infer<typeof TransactionSchema>;

const NotificationSchema = z.object({
  notificationType: z.string(),
  subtype: z.string().optional(),
  notificationUUID: z.string().optional(),
  data: z
    .object({
      bundleId: z.string().optional(),
      environment: z.string().optional(),
      signedTransactionInfo: z.string().optional(),
    })
    .optional(),
});

export interface AppStoreNotification {
  notificationType: string;
  subtype: string | undefined;
  notificationUUID: string | undefined;
  bundleId: string | undefined;
  transaction: AppStoreTransaction | null;
}

export interface AppStoreVerifierOptions {
  /** Apple Root CA - G3 (PEM or DER). Without it only dev-mode unsigned payloads can be accepted. */
  rootCert: X509Certificate | null;
  /** DEV ONLY: accept unsigned payloads (plain JSON, or a JWS without an x5c chain). */
  allowUnsigned: boolean;
  /** Require Apple's marker OIDs on the leaf and intermediate. Disable only for test chains without them. */
  requireAppleOids?: boolean;
  clock: Clock;
}

/** Loads the trusted root and, when a fingerprint is supplied, refuses anything else. */
export function loadRootCertificate(file: string, expectedSha256Hex?: string): X509Certificate {
  const cert = new X509Certificate(readFileSync(file));
  if (expectedSha256Hex !== undefined) {
    const actual = cert.fingerprint256.replace(/:/g, '').toLowerCase();
    if (actual !== expectedSha256Hex.toLowerCase()) {
      throw new Error(`Root certificate at ${file} has SHA-256 ${actual}, expected ${expectedSha256Hex}`);
    }
  }
  if (!cert.ca) throw new Error(`Certificate at ${file} is not a CA certificate`);
  return cert;
}

function decodeJsonSegment(segment: string): unknown {
  return JSON.parse(Buffer.from(segment, 'base64url').toString('utf8'));
}

/**
 * Verifies App Store signed data (JWS transactions and Server Notifications V2):
 * x5c chain up to the pinned Apple Root CA - G3, certificate validity, Apple marker OIDs,
 * then the ES256 signature with the leaf key.
 */
export class AppStoreVerifier {
  constructor(private readonly options: AppStoreVerifierOptions) {}

  async verifyTransaction(jws: string): Promise<AppStoreTransaction> {
    const payload = await this.verifyAndDecode(jws);
    const parsed = TransactionSchema.safeParse(payload);
    if (!parsed.success) throw new IapError('invalid_transaction', 'Transaction payload is missing required fields');
    return parsed.data;
  }

  async verifyNotification(signedPayload: string): Promise<AppStoreNotification> {
    const payload = await this.verifyAndDecode(signedPayload);
    const parsed = NotificationSchema.safeParse(payload);
    if (!parsed.success) throw new IapError('invalid_notification', 'Notification payload is malformed');
    const signedTx = parsed.data.data?.signedTransactionInfo;
    return {
      notificationType: parsed.data.notificationType,
      subtype: parsed.data.subtype,
      notificationUUID: parsed.data.notificationUUID,
      bundleId: parsed.data.data?.bundleId,
      transaction: signedTx !== undefined ? await this.verifyTransaction(signedTx) : null,
    };
  }

  private async verifyAndDecode(jws: string): Promise<unknown> {
    const parts = jws.split('.');
    let header: ReturnType<typeof decodeProtectedHeader> | null = null;
    if (parts.length === 3) {
      try {
        header = decodeProtectedHeader(jws);
      } catch {
        header = null;
      }
    }
    const chain = header?.x5c;
    if (header === null || chain === undefined || chain.length === 0) {
      return this.decodeUnsigned(jws, parts);
    }
    if (header.alg !== 'ES256') throw new IapError('invalid_signature', 'Unexpected signing algorithm');
    const leaf = this.verifyChain(chain);
    try {
      const { payload } = await compactVerify(jws, leaf.publicKey, { algorithms: ['ES256'] });
      return JSON.parse(Buffer.from(payload).toString('utf8'));
    } catch {
      throw new IapError('invalid_signature', 'Signature verification failed');
    }
  }

  private decodeUnsigned(jws: string, parts: string[]): unknown {
    if (!this.options.allowUnsigned) {
      throw new IapError('invalid_signature', 'Signed data has no certificate chain');
    }
    try {
      if (parts.length === 3 && parts[1] !== undefined) return decodeJsonSegment(parts[1]);
      return JSON.parse(jws);
    } catch {
      throw new IapError('invalid_transaction', 'Unsigned test payload is not valid JSON');
    }
  }

  /** Returns the leaf certificate after validating the whole chain against the pinned root. */
  private verifyChain(x5c: string[]): X509Certificate {
    const root = this.options.rootCert;
    if (root === null) throw new IapError('iap_not_configured', 'App Store root certificate is not configured');
    if (x5c.length < 2 || x5c.length > 5) throw new IapError('invalid_signature', 'Unexpected certificate chain length');

    let certs: X509Certificate[];
    try {
      certs = x5c.map((b64) => new X509Certificate(Buffer.from(b64, 'base64')));
    } catch {
      throw new IapError('invalid_signature', 'Certificate chain could not be parsed');
    }
    // Anchor: the chain must end at, or be directly issued by, the pinned root.
    const last = certs[certs.length - 1] as X509Certificate;
    if (last.fingerprint256 !== root.fingerprint256) certs = [...certs, root];
    else certs[certs.length - 1] = root;

    const now = this.options.clock.now();
    for (let i = 0; i < certs.length; i++) {
      const cert = certs[i] as X509Certificate;
      if (now < Date.parse(cert.validFrom) || now > Date.parse(cert.validTo)) {
        throw new IapError('invalid_signature', 'A certificate in the chain is outside its validity period');
      }
      if (i === certs.length - 1) break;
      const issuer = certs[i + 1] as X509Certificate;
      if (!issuer.ca || !cert.checkIssued(issuer) || !cert.verify(issuer.publicKey)) {
        throw new IapError('invalid_signature', 'Certificate chain does not verify');
      }
    }
    const leaf = certs[0] as X509Certificate;
    if (this.options.requireAppleOids !== false) {
      const intermediate = certs[1] as X509Certificate;
      if (!leaf.raw.includes(OID_LEAF_RECEIPT_SIGNING) || !intermediate.raw.includes(OID_INTERMEDIATE_WWDR)) {
        throw new IapError('invalid_signature', 'Certificates are not App Store signing certificates');
      }
    }
    if (leaf.ca) throw new IapError('invalid_signature', 'Leaf certificate must not be a CA');
    return leaf;
  }
}
