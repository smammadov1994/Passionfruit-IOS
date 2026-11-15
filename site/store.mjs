// Waitlist storage. Supabase (Postgres) when DATABASE_URL is set, else a local JSON-lines file.
// Both expose: join(email, zip, borough) -> { already, borough, position, boroughPosition }
//              stats() -> { total, boroughs: { name: count } }
import { appendFile, mkdir, readFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BOROUGHS } from './nyc.mjs';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const SERVER = path.resolve(ROOT, '../server');
const emptyTally = () => Object.fromEntries(BOROUGHS.map((b) => [b, 0]));

function pgStore(url) {
  // `pg` is already installed for the app server; reuse it rather than adding a dependency here.
  const pg = createRequire(path.join(SERVER, 'package.json'))('pg');
  const ssl = process.env.DATABASE_SSL === '1' || process.env.DATABASE_SSL === 'true';
  const caPath = process.env.DATABASE_SSL_CA_PATH;
  const pool = new pg.Pool({
    connectionString: url,
    max: 3,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 10_000,
    // TLS is always verified. Supabase signs with its own authority, so pass its certificate.
    ssl: ssl ? { rejectUnauthorized: true, ...(caPath ? { ca: readFileSync(path.resolve(SERVER, caPath), 'utf8') } : {}) } : undefined,
  });
  pool.on('error', (err) => console.error('waitlist db:', err.message));

  const place = async (row) => {
    const { rows } = await pool.query(
      `SELECT count(*)::int AS position, count(*) FILTER (WHERE borough = $2)::int AS borough_position
         FROM waitlist WHERE id <= $1`,
      [row.id, row.borough],
    );
    return { borough: row.borough, position: rows[0].position, boroughPosition: rows[0].borough_position };
  };

  return {
    kind: 'supabase',
    async join(email, zip, borough) {
      const ins = await pool.query(
        'INSERT INTO waitlist (email, zip, borough) VALUES ($1, $2, $3) ON CONFLICT (email) DO NOTHING RETURNING id, borough',
        [email, zip, borough],
      );
      if (ins.rows[0]) return { already: false, ...(await place(ins.rows[0])) };
      const old = await pool.query('SELECT id, borough FROM waitlist WHERE email = $1', [email]);
      return { already: true, ...(await place(old.rows[0])) };
    },
    async stats() {
      const { rows } = await pool.query('SELECT borough, count(*)::int AS n FROM waitlist GROUP BY borough');
      const boroughs = emptyTally();
      let total = 0;
      for (const r of rows) { boroughs[r.borough] = r.n; total += r.n; }
      return { total, boroughs };
    },
  };
}

async function fileStore() {
  const DATA = path.join(ROOT, 'data');
  const FILE = path.join(DATA, 'waitlist.jsonl');
  let entries = [];
  try {
    entries = (await readFile(FILE, 'utf8')).split('\n').filter(Boolean).map((l) => JSON.parse(l));
  } catch { /* first run: no file yet */ }
  const place = (entry) => ({
    borough: entry.borough,
    position: entries.indexOf(entry) + 1,
    boroughPosition: entries.filter((e) => e.borough === entry.borough).indexOf(entry) + 1,
  });
  return {
    kind: 'file',
    async join(email, zip, borough) {
      const existing = entries.find((e) => e.email === email);
      if (existing) return { already: true, ...place(existing) };
      const entry = { email, zip, borough, at: new Date().toISOString() };
      await mkdir(DATA, { recursive: true });
      await appendFile(FILE, JSON.stringify(entry) + '\n');
      entries.push(entry);
      return { already: false, ...place(entry) };
    },
    async stats() {
      const boroughs = emptyTally();
      for (const e of entries) boroughs[e.borough] = (boroughs[e.borough] ?? 0) + 1;
      return { total: entries.length, boroughs };
    },
  };
}

export async function openStore() {
  const url = process.env.DATABASE_URL;
  return url ? pgStore(url) : fileStore();
}
