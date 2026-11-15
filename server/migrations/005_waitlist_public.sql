-- Public entry points for the launch-site waitlist, so the static site (GitHub Pages) can sign
-- people up straight through the Supabase Data API with the project's public key.
--
-- The `waitlist` table itself stays closed: RLS is on with no policies. The public key can only
-- call the two functions below, which run as the table owner and do their own checking:
--   waitlist_join(email, zip, website)  adds one person, New York City ZIP codes only
--   waitlist_stats()                    sign-up counts per borough, nothing else

-- One row per sign-up attempt, used only to slow down floods. Closed to the public key.
CREATE TABLE waitlist_attempts (
  ip text NOT NULL,
  at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX waitlist_attempts_ip_idx ON waitlist_attempts (ip, at);
ALTER TABLE waitlist_attempts ENABLE ROW LEVEL SECURITY;

-- Same ranges as site/nyc.mjs. Keep the two in step.
CREATE FUNCTION waitlist_borough(p_zip text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_zip !~ '^[0-9]{5}$' THEN NULL
    WHEN p_zip::int BETWEEN 10001 AND 10282 THEN 'Manhattan'
    WHEN p_zip::int BETWEEN 10301 AND 10314 THEN 'Staten Island'
    WHEN p_zip::int BETWEEN 10451 AND 10475 THEN 'The Bronx'
    WHEN p_zip::int BETWEEN 11004 AND 11005
      OR p_zip::int BETWEEN 11101 AND 11120
      OR p_zip::int BETWEEN 11351 AND 11499
      OR p_zip::int BETWEEN 11690 AND 11697 THEN 'Queens'
    WHEN p_zip::int BETWEEN 11201 AND 11256 THEN 'Brooklyn'
  END
$$;

CREATE FUNCTION waitlist_stats() RETURNS json
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT json_build_object(
    'total', (SELECT count(*) FROM waitlist),
    'boroughs', (
      SELECT json_object_agg(b.name, (SELECT count(*) FROM waitlist w WHERE w.borough = b.name))
      FROM unnest(ARRAY['Manhattan', 'Brooklyn', 'Queens', 'The Bronx', 'Staten Island']) AS b(name)
    )
  )
$$;

CREATE FUNCTION waitlist_join(p_email text, p_zip text, p_website text DEFAULT '') RETURNS json
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_zip     text := btrim(coalesce(p_zip, ''));
  v_borough text;
  v_id      bigint;
  v_already boolean := false;
  v_ip      text;
  v_place   record;
BEGIN
  -- The Data API passes request headers in this setting. Behind Supabase's gateway the first
  -- entry of x-forwarded-for is the caller.
  v_ip := coalesce(
    nullif(btrim(split_part(nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', ',', 1)), ''),
    'unknown');
  DELETE FROM waitlist_attempts WHERE at < now() - interval '1 hour';
  INSERT INTO waitlist_attempts (ip) VALUES (v_ip);
  IF (SELECT count(*) FROM waitlist_attempts WHERE ip = v_ip AND at > now() - interval '1 minute') > 8 THEN
    RETURN json_build_object('ok', false, 'error', 'slow_down', 'message', 'Too many tries. Give it a minute.');
  END IF;

  -- Hidden form field that only bots fill in. Answer as if it worked and store nothing.
  IF coalesce(p_website, '') <> '' THEN
    RETURN json_build_object('ok', true, 'already', false, 'borough', 'Manhattan', 'position', 1, 'boroughPosition', 1,
                             'stats', waitlist_stats());
  END IF;

  IF length(v_email) > 254 OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$' THEN
    RETURN json_build_object('ok', false, 'error', 'email', 'message', 'Enter an email address we can reach you at.');
  END IF;

  v_borough := waitlist_borough(v_zip);
  IF v_borough IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'zip',
      'message', 'That ZIP is outside the five boroughs. Passionfruit opens in New York City first.');
  END IF;

  INSERT INTO waitlist (email, zip, borough) VALUES (v_email, v_zip, v_borough)
  ON CONFLICT (email) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    v_already := true;
    SELECT id, borough INTO v_id, v_borough FROM waitlist WHERE email = v_email;
  END IF;

  SELECT count(*)::int AS position, (count(*) FILTER (WHERE borough = v_borough))::int AS borough_position
    INTO v_place FROM waitlist WHERE id <= v_id;

  RETURN json_build_object('ok', true, 'already', v_already, 'borough', v_borough,
                           'position', v_place.position, 'boroughPosition', v_place.borough_position,
                           'stats', waitlist_stats());
END
$$;

-- Functions are callable by everyone by default. Take that away, then hand the two entry points
-- to Supabase's public roles. Plain Postgres has no such roles, so this part is skipped there.
REVOKE ALL ON FUNCTION waitlist_join(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION waitlist_stats() FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
    GRANT EXECUTE ON FUNCTION waitlist_join(text, text, text) TO anon, authenticated;
    GRANT EXECUTE ON FUNCTION waitlist_stats() TO anon, authenticated;
  END IF;
END
$$;
