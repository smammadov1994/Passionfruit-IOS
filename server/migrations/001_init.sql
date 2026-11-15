-- Tempo initial schema.

CREATE TABLE users (
  id                  uuid PRIMARY KEY,
  apple_sub           text NOT NULL UNIQUE,
  first_name          text NOT NULL DEFAULT '',
  birthdate           text CHECK (birthdate IS NULL OR birthdate ~ '^\d{4}-\d{2}-\d{2}$'),
  gender              text,
  interested_in       jsonb NOT NULL DEFAULT '[]'::jsonb,
  bio                 text NOT NULL DEFAULT '',
  city                text NOT NULL DEFAULT '',
  lat                 double precision,
  lng                 double precision,
  photo_urls          jsonb NOT NULL DEFAULT '[]'::jsonb,
  intention           text,
  children            text,
  religion            text,
  education           text,
  smoking             text,
  drinking            text,
  is_premium          boolean NOT NULL DEFAULT false,
  premium_expires_at  timestamptz,
  onboarding_complete boolean NOT NULL DEFAULT false,
  strikes             integer NOT NULL DEFAULT 0,
  suspended           boolean NOT NULL DEFAULT false,
  suspended_until     timestamptz,
  preferences         jsonb NOT NULL,
  apns_token          text,
  push_enabled        boolean NOT NULL DEFAULT false,
  tz_offset_minutes   integer NOT NULL DEFAULT 0,
  last_online_push_at timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX users_push_idx ON users (last_online_push_at) WHERE push_enabled AND apns_token IS NOT NULL;

CREATE TABLE blocks (
  blocker_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (blocker_id, blocked_id)
);
CREATE INDEX blocks_blocked_idx ON blocks (blocked_id);

-- One row per pairing. Participants are nulled (not deleted) when an account is removed so the
-- other person's daily count is unaffected.
CREATE TABLE dates (
  id         uuid PRIMARY KEY,
  user_a     uuid REFERENCES users (id) ON DELETE SET NULL,
  user_b     uuid REFERENCES users (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL,
  started_at timestamptz,
  ended_at   timestamptz,
  end_reason text,
  outcome    text CHECK (outcome IS NULL OR outcome IN ('match', 'no_match'))
);
CREATE INDEX dates_user_a_idx ON dates (user_a, created_at);
CREATE INDEX dates_user_b_idx ON dates (user_b, created_at);

-- user_a < user_b always, so a pair can only be matched once.
CREATE TABLE matches (
  id         uuid PRIMARY KEY,
  user_a     uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  user_b     uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  date_id    uuid,
  matched_at timestamptz NOT NULL,
  UNIQUE (user_a, user_b),
  CHECK (user_a < user_b)
);
CREATE INDEX matches_user_b_idx ON matches (user_b);

CREATE TABLE messages (
  id        uuid PRIMARY KEY,
  seq       bigserial NOT NULL,
  match_id  uuid NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
  sender_id uuid NOT NULL,
  text      text NOT NULL,
  sent_at   timestamptz NOT NULL,
  client_id text
);
CREATE INDEX messages_match_idx ON messages (match_id, seq);
CREATE UNIQUE INDEX messages_client_idx ON messages (match_id, sender_id, client_id) WHERE client_id IS NOT NULL;

CREATE TABLE match_reads (
  match_id     uuid NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
  user_id      uuid NOT NULL,
  last_read_at timestamptz NOT NULL,
  PRIMARY KEY (match_id, user_id)
);

-- Safety records. reported_user_id is intentionally not a foreign key: reports about an account
-- outlive that account.
CREATE TABLE reports (
  id               uuid PRIMARY KEY,
  reporter_id      uuid REFERENCES users (id) ON DELETE SET NULL,
  reported_user_id uuid NOT NULL,
  date_id          uuid,
  match_id         uuid,
  reason           text NOT NULL,
  details          text,
  created_at       timestamptz NOT NULL
);
CREATE INDEX reports_reported_idx ON reports (reported_user_id, created_at);

-- Append-only audit trail of moderation verdicts, strikes, suspensions, reports and blocks.
-- Never contains frames or transcript text.
CREATE TABLE audit_log (
  id             uuid PRIMARY KEY,
  seq            bigserial NOT NULL,
  type           text NOT NULL,
  user_id        uuid,
  target_user_id uuid,
  date_id        text,
  match_id       uuid,
  category       text,
  action         text,
  details        jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_user_idx ON audit_log (user_id, seq);
CREATE INDEX audit_type_idx ON audit_log (type, seq);

CREATE TABLE iap_transactions (
  original_transaction_id text PRIMARY KEY,
  user_id                 uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  updated_at              timestamptz NOT NULL DEFAULT now()
);

-- Strike carry-over so deleting and recreating an account does not clear a ban.
-- Keyed by a salted hash of the identity subject; holds no profile data.
CREATE TABLE deleted_identities (
  identity_hash   text PRIMARY KEY,
  strikes         integer NOT NULL,
  suspended       boolean NOT NULL,
  suspended_until timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
