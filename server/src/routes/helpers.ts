import type { FastifyRequest } from 'fastify';
import { z } from 'zod';
import { badRequest } from '../errors.js';

export const UuidSchema = z.string().uuid();
export const IdParams = z.object({ id: UuidSchema });

/** Validates untrusted input; failures become a 400 with the first problem spelled out. */
export function parse<T extends z.ZodType>(schema: T, input: unknown): z.infer<T> {
  const result = schema.safeParse(input ?? {});
  if (!result.success) {
    const issue = result.error.issues[0];
    const where = issue && issue.path.length > 0 ? `${issue.path.join('.')}: ` : '';
    throw badRequest('invalid_request', `${where}${issue?.message ?? 'Invalid request'}`);
  }
  return result.data;
}

export const clientIp = (request: FastifyRequest): string => request.ip;

const JPEG_MAGIC = Buffer.from([0xff, 0xd8, 0xff]);

/** Decodes a base64 (or data-URL) JPEG and checks size and magic bytes. */
export function decodeJpeg(imageBase64: string, maxBytes: number): Buffer {
  const comma = imageBase64.startsWith('data:') ? imageBase64.indexOf(',') : -1;
  const body = comma >= 0 ? imageBase64.slice(comma + 1) : imageBase64;
  if (!/^[A-Za-z0-9+/=\s_-]*$/.test(body)) throw badRequest('invalid_image', 'Image is not valid base64.');
  const data = Buffer.from(body, 'base64');
  if (data.length < 4 || !data.subarray(0, 3).equals(JPEG_MAGIC)) {
    throw badRequest('invalid_image', 'Image must be a JPEG.');
  }
  if (data.length > maxBytes) throw badRequest('image_too_large', 'That image is too large.');
  return data;
}
