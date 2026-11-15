import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

/** Where profile photos live. Keys are server-generated (`<uuid>.jpg`), never user input. */
export interface BlobStore {
  /** Stores the object and returns its public URL. */
  put(key: string, data: Buffer, contentType: string): Promise<string>;
  /** Deletes the object a previously returned URL points at. Missing objects are not an error. */
  deleteByUrl(url: string): Promise<void>;
}

const SAFE_KEY = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;

/** Dev/default implementation: files on local disk, served by the API at `/uploads/<key>`. */
export class LocalBlobStore implements BlobStore {
  static readonly ROUTE_PREFIX = '/uploads/';

  constructor(
    private readonly dir: string,
    private readonly publicBaseUrl: () => string,
  ) {}

  private pathFor(key: string): string {
    if (!SAFE_KEY.test(key)) throw new Error('unsafe blob key');
    return path.join(this.dir, key);
  }

  async put(key: string, data: Buffer, _contentType: string): Promise<string> {
    await mkdir(this.dir, { recursive: true });
    await writeFile(this.pathFor(key), data, { mode: 0o640 });
    return `${this.publicBaseUrl()}${LocalBlobStore.ROUTE_PREFIX}${key}`;
  }

  async deleteByUrl(url: string): Promise<void> {
    const idx = url.lastIndexOf(LocalBlobStore.ROUTE_PREFIX);
    if (idx < 0) return;
    const key = url.slice(idx + LocalBlobStore.ROUTE_PREFIX.length);
    if (!SAFE_KEY.test(key)) return;
    await rm(this.pathFor(key), { force: true });
  }

  /** Used by the `/uploads/:key` route. Returns null for unknown or unsafe keys. */
  async read(key: string): Promise<Buffer | null> {
    if (!SAFE_KEY.test(key)) return null;
    try {
      return await readFile(this.pathFor(key));
    } catch {
      return null;
    }
  }
}

export interface S3Options {
  bucket: string;
  publicBaseUrl: string;
  region?: string;
  endpoint?: string;
  accessKeyId?: string;
  secretAccessKey?: string;
}

/** The two S3 calls this app needs. Supply an implementation backed by your SDK of choice. */
export interface S3Transport {
  putObject(input: { bucket: string; key: string; body: Buffer; contentType: string }): Promise<void>;
  deleteObject(input: { bucket: string; key: string }): Promise<void>;
}

/**
 * S3-compatible blob store (AWS S3, Cloudflare R2, MinIO...).
 *
 * The key naming, URL construction and delete-by-URL logic are complete. The network calls go
 * through `S3Transport`, which is deliberately NOT bundled so the server has no cloud SDK
 * dependency; README "Photo storage on S3" shows the ~15 line @aws-sdk/client-s3 transport.
 * Without a transport this class throws at first use, so a misconfigured deploy fails loudly.
 */
export class S3BlobStore implements BlobStore {
  private readonly base: string;

  constructor(
    private readonly options: S3Options,
    private readonly transport?: S3Transport,
  ) {
    this.base = options.publicBaseUrl.replace(/\/+$/, '');
  }

  private requireTransport(): S3Transport {
    if (!this.transport) {
      throw new Error('BLOB_STORE=s3 needs an S3Transport; see README "Photo storage on S3"');
    }
    return this.transport;
  }

  async put(key: string, data: Buffer, contentType: string): Promise<string> {
    if (!SAFE_KEY.test(key)) throw new Error('unsafe blob key');
    const objectKey = `photos/${key}`;
    await this.requireTransport().putObject({ bucket: this.options.bucket, key: objectKey, body: data, contentType });
    return `${this.base}/${objectKey}`;
  }

  async deleteByUrl(url: string): Promise<void> {
    if (!url.startsWith(`${this.base}/photos/`)) return;
    const objectKey = url.slice(this.base.length + 1);
    await this.requireTransport().deleteObject({ bucket: this.options.bucket, key: objectKey });
  }
}
