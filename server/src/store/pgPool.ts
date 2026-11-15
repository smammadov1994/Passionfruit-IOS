import { readFileSync } from 'node:fs';
import pg from 'pg';
import type { Queryable, Row } from './PgStore.js';

function wrapClient(client: pg.PoolClient): Queryable {
  const q: Queryable = {
    async query(text, params) {
      const res = await client.query<Row>(text, params ? [...params] : undefined);
      return { rows: res.rows };
    },
    async exec(sql) {
      await client.query(sql);
    },
    tx: (fn) => fn(q), // already inside a transaction
    async close() {},
  };
  return q;
}

/**
 * TLS is always verified. Hosts whose certificate is signed by their own authority (Supabase is
 * one) need that authority's certificate: download it and set `DATABASE_SSL_CA_PATH` to the file.
 */
function sslOptions(): { rejectUnauthorized: true; ca?: string } {
  const caPath = process.env.DATABASE_SSL_CA_PATH;
  if (caPath === undefined || caPath === '') return { rejectUnauthorized: true };
  return { rejectUnauthorized: true, ca: readFileSync(caPath, 'utf8') };
}

/** `Queryable` over a node-postgres pool. */
export function createPgQueryable(options: {
  connectionString: string;
  ssl: boolean;
  max: number;
  onError?: (err: Error) => void;
}): Queryable {
  const pool = new pg.Pool({
    connectionString: options.connectionString,
    max: options.max,
    ssl: options.ssl ? sslOptions() : undefined,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 10_000,
  });
  // An idle client erroring must not crash the process.
  pool.on('error', (err) => options.onError?.(err));

  return {
    async query(text, params) {
      const res = await pool.query<Row>(text, params ? [...params] : undefined);
      return { rows: res.rows };
    },
    async exec(sql) {
      await pool.query(sql);
    },
    async tx(fn) {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const result = await fn(wrapClient(client));
        await client.query('COMMIT');
        return result;
      } catch (err) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw err;
      } finally {
        client.release();
      }
    },
    async close() {
      await pool.end();
    },
  };
}
