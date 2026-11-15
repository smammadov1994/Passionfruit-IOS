/** Error carrying an HTTP status and a stable machine-readable code. */
export class HttpError extends Error {
  readonly statusCode: number;
  readonly code: string;

  constructor(statusCode: number, code: string, message: string) {
    super(message);
    this.name = 'HttpError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

export const badRequest = (code: string, message: string): HttpError => new HttpError(400, code, message);
export const unauthorized = (message = 'Authentication required'): HttpError =>
  new HttpError(401, 'unauthorized', message);
export const forbidden = (code = 'forbidden', message = 'Not allowed'): HttpError =>
  new HttpError(403, code, message);
export const notFound = (message = 'Not found'): HttpError => new HttpError(404, 'not_found', message);
export const tooMany = (message = 'Too many requests'): HttpError => new HttpError(429, 'rate_limited', message);
