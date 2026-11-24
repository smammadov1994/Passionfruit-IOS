-- Where each waitlist sign-up came from, so an ad's clicks can be told apart from word of mouth.
--
-- The launch page works the source out itself (site/home.js): a `from` or `utm_source` in the
-- link, else "meta" when Facebook or Instagram added its click id, else the site that linked
-- here, else "direct". It is a hint from the visitor's browser, not a fact: never trust it for
-- anything but counting.

ALTER TABLE waitlist ADD COLUMN source text;

-- A second entry point beside waitlist_join(email, zip, website), so pages still open in
-- someone's browser from before this change keep working. It does everything the first does,
-- then notes the source on a row that has none yet (a second try never rewrites the first).
CREATE FUNCTION waitlist_join(p_email text, p_zip text, p_website text, p_source text) RETURNS json
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_result json := waitlist_join(p_email, p_zip, p_website);
  v_source text := nullif(left(regexp_replace(lower(coalesce(p_source, '')), '[^a-z0-9._-]', '', 'g'), 40), '');
BEGIN
  IF v_source IS NOT NULL AND (v_result ->> 'ok')::boolean AND coalesce(p_website, '') = '' THEN
    UPDATE waitlist SET source = v_source
    WHERE email = lower(btrim(coalesce(p_email, ''))) AND source IS NULL;
  END IF;
  RETURN v_result;
END
$$;

REVOKE ALL ON FUNCTION waitlist_join(text, text, text, text) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
    GRANT EXECUTE ON FUNCTION waitlist_join(text, text, text, text) TO anon, authenticated;
  END IF;
END
$$;
