import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import type { Queryable } from './PgStore.js';

export const MIGRATIONS_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../migrations');

/** Applies every not-yet-applied `migrations/*.sql` file in name order, each in its own transaction. */
export async function runMigrations(db: Queryable, dir: string = MIGRATIONS_DIR): Promise<string[]> {
  await db.exec(
    'CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())',
  );
  const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
  const { rows } = await db.query('SELECT name FROM schema_migrations');
  const applied = new Set(rows.map((r) => String(r.name)));
  const ran: string[] = [];
  for (const file of files) {
    if (applied.has(file)) continue;
    const sql = await readFile(path.join(dir, file), 'utf8');
    await db.tx(async (q) => {
      await q.exec(sql);
      await q.query('INSERT INTO schema_migrations (name) VALUES ($1)', [file]);
    });
    ran.push(file);
  }
  return ran;
}

// CLI: `npm run migrate`
if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const url = process.env.DATABASE_URL;
  if (url === undefined || url === '') {
    console.error('DATABASE_URL is required to run migrations');
    process.exit(1);
  }
  const { createPgQueryable } = await import('./pgPool.js');
  const db = createPgQueryable({
    connectionString: url,
    ssl: process.env.DATABASE_SSL === '1' || process.env.DATABASE_SSL === 'true',
    max: 2,
  });
  try {
    const ran = await runMigrations(db);
    console.log(ran.length > 0 ? `Applied: ${ran.join(', ')}` : 'Nothing to apply');
  } catch (err) {
    console.error(err);
    process.exitCode = 1;
  } finally {
    await db.close();
  }
}
