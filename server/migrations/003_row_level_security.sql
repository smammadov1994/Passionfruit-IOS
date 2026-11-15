-- Row level security on every table, with no policies.
--
-- On Supabase, tables in the `public` schema are reachable through the auto-generated Data API
-- with the project's public (anon) key. Tempo's clients never use that API: they talk only to the
-- Tempo server, which connects as the table owner and is not subject to these rules. Enabling RLS
-- with no policies therefore changes nothing for the server and denies everything to anyone
-- holding only the public key.
--
-- On plain Postgres this is harmless: the owner bypasses RLS.

ALTER TABLE users              ENABLE ROW LEVEL SECURITY;
ALTER TABLE blocks             ENABLE ROW LEVEL SECURITY;
ALTER TABLE dates              ENABLE ROW LEVEL SECURITY;
ALTER TABLE matches            ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages           ENABLE ROW LEVEL SECURITY;
ALTER TABLE match_reads        ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports            ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log          ENABLE ROW LEVEL SECURITY;
ALTER TABLE iap_transactions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE deleted_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE schema_migrations  ENABLE ROW LEVEL SECURITY;
