import type { AppConfig } from '../config.js';
import { ExplicitTextClassifier } from './textClassifier.js';

export interface FrameVerdict {
  /** Probability-like score in [0, 1] that the frame shows nudity / an exposed body. */
  nudityScore: number;
}

export interface TextVerdictResult {
  sexualLanguage: boolean;
  /** Opaque references for the audit log (list indices or vendor labels); never the words said. */
  matches: string[];
}

/**
 * Content classification. Enforcement (warn / end / strike) lives in ModerationService; a
 * provider only says what it sees. Frames are passed in memory and must never be persisted.
 */
export interface ModerationProvider {
  readonly name: string;
  classifyFrame(jpeg: Buffer): Promise<FrameVerdict>;
  classifyText(text: string): Promise<TextVerdictResult>;
}

/**
 * Deterministic provider for dev and tests. A frame is "nudity" when its bytes contain the ASCII
 * marker `TEMPO_TEST_NUDITY` (append it after the JPEG data); everything else is clean.
 * Text uses the real built-in classifier.
 */
export class MockModerationProvider implements ModerationProvider {
  static readonly NUDITY_MARKER = 'TEMPO_TEST_NUDITY';
  readonly name = 'mock';

  constructor(private readonly text: ExplicitTextClassifier) {}

  async classifyFrame(jpeg: Buffer): Promise<FrameVerdict> {
    return { nudityScore: jpeg.includes(MockModerationProvider.NUDITY_MARKER) ? 1 : 0 };
  }

  async classifyText(text: string): Promise<TextVerdictResult> {
    const verdict = this.text.classify(text);
    return { sexualLanguage: verdict.explicit, matches: verdict.matches };
  }
}

export interface HttpModerationOptions {
  apiUrl: string;
  apiKey: string;
  timeoutMs: number;
  fetchImpl?: typeof fetch;
}

interface VendorRequest {
  url: string;
  init: { method: 'POST'; headers: Record<string, string>; body: string | Uint8Array };
}

// ============================================================================================
// VENDOR-SPECIFIC MAPPING: the only code to edit when wiring a real image-moderation vendor.
// Replace the bodies of these two functions with your vendor's request and response shapes
// (Hive, Sightengine, AWS Rekognition behind a gateway, ...). Everything else in this file,
// including auth header plumbing, timeouts, error handling and text moderation, is complete.
//
// As shipped they speak a neutral JSON contract:
//   POST {MODERATION_API_URL}   Authorization: Bearer {MODERATION_API_KEY}
//   { "image": "<base64 jpeg>" }   ->   { "nudity": <number 0..1> }
// ============================================================================================
export function buildVendorFrameRequest(jpeg: Buffer, options: HttpModerationOptions): VendorRequest {
  return {
    url: options.apiUrl,
    init: {
      method: 'POST',
      headers: { authorization: `Bearer ${options.apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({ image: jpeg.toString('base64') }),
    },
  };
}

export function parseVendorFrameResponse(body: unknown): FrameVerdict {
  if (typeof body === 'object' && body !== null && 'nudity' in body) {
    const score = Number((body as { nudity: unknown }).nudity);
    if (Number.isFinite(score)) return { nudityScore: Math.min(1, Math.max(0, score)) };
  }
  throw new Error('Unrecognised moderation vendor response');
}
// ============================================================================================
// END VENDOR-SPECIFIC MAPPING
// ============================================================================================

/** Real provider: frames go to an HTTP vision-moderation API, text to the built-in classifier. */
export class HttpModerationProvider implements ModerationProvider {
  readonly name = 'http';
  private readonly fetchImpl: typeof fetch;

  constructor(
    private readonly options: HttpModerationOptions,
    private readonly text: ExplicitTextClassifier,
  ) {
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  async classifyFrame(jpeg: Buffer): Promise<FrameVerdict> {
    const { url, init } = buildVendorFrameRequest(jpeg, this.options);
    const res = await this.fetchImpl(url, { ...init, signal: AbortSignal.timeout(this.options.timeoutMs) });
    if (!res.ok) throw new Error(`Moderation vendor responded with HTTP ${res.status}`);
    return parseVendorFrameResponse(await res.json());
  }

  async classifyText(text: string): Promise<TextVerdictResult> {
    const verdict = this.text.classify(text);
    return { sexualLanguage: verdict.explicit, matches: verdict.matches };
  }
}

export function createModerationProvider(config: AppConfig['moderation']): ModerationProvider {
  const text = ExplicitTextClassifier.fromFile();
  if (config.provider === 'http' && config.apiUrl !== undefined && config.apiKey !== undefined) {
    return new HttpModerationProvider(
      { apiUrl: config.apiUrl, apiKey: config.apiKey, timeoutMs: config.timeoutMs },
      text,
    );
  }
  return new MockModerationProvider(text);
}
