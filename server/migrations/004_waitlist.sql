-- Launch-site waitlist (New York City only). Written by site/serve.mjs, which connects as the
-- table owner. RLS is on with no policies, so the public (anon) key cannot read or write it.

CREATE TABLE waitlist (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email      text NOT NULL UNIQUE,
  zip        text NOT NULL CHECK (zip ~ '^[0-9]{5}$'),
  borough    text NOT NULL CHECK (borough IN ('Manhattan', 'Brooklyn', 'Queens', 'The Bronx', 'Staten Island')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX waitlist_borough_idx ON waitlist (borough, id);

ALTER TABLE waitlist ENABLE ROW LEVEL SECURITY;
