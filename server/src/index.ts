import { buildApp } from './app.js';
import { ConfigError, loadConfig, type AppConfig } from './config.js';
import { MemoryStore } from './store/MemoryStore.js';
import { runMigrations } from './store/migrate.js';
import { PgStore } from './store/PgStore.js';
import { createPgQueryable } from './store/pgPool.js';
import type { Store } from './store/Store.js';

async function createStore(config: AppConfig): Promise<{ store: Store; kind: string }> {
  if (config.databaseUrl === undefined) return { store: new MemoryStore(), kind: 'memory' };
  const db = createPgQueryable({
    connectionString: config.databaseUrl,
    ssl: config.databaseSsl,
    max: config.databasePoolMax,
    onError: (err) => console.error(JSON.stringify({ level: 50, msg: 'postgres pool error', err: err.message })),
  });
  await runMigrations(db);
  return { store: new PgStore(db), kind: 'postgres' };
}

async function main(): Promise<void> {
  let config: AppConfig;
  try {
    config = loadConfig();
  } catch (err) {
    if (err instanceof ConfigError) {
      console.error(err.message);
      process.exit(1);
    }
    throw err;
  }

  const { store, kind } = await createStore(config);
  const { app } = await buildApp({ config, store });
  if (kind === 'memory') {
    app.log.warn('DATABASE_URL is not set: using the in-memory store. All data is lost on restart.');
  }

  let closing = false;
  const shutdown = (signal: string): void => {
    if (closing) return;
    closing = true;
    app.log.info({ signal }, 'shutting down');
    // If something hangs, do not hold the orchestrator's stop timeout hostage.
    const force = setTimeout(() => {
      app.log.error('graceful shutdown timed out; exiting');
      process.exit(1);
    }, 15_000);
    force.unref();
    app.close().then(
      () => process.exit(0),
      (err: unknown) => {
        app.log.error({ err }, 'error during shutdown');
        process.exit(1);
      },
    );
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('unhandledRejection', (reason) => {
    app.log.error({ reason }, 'unhandled promise rejection');
  });
  process.on('uncaughtException', (err) => {
    app.log.fatal({ err }, 'uncaught exception');
    shutdown('uncaughtException');
  });

  await app.listen({ host: config.host, port: config.port });
  app.log.info({ store: kind, moderation: config.moderation.provider, push: config.push.provider }, 'ready');
}

main().catch((err: unknown) => {
  console.error(err);
  process.exit(1);
});
