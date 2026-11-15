// Where the waitlist form sends sign-ups.
//
// Leave SUPABASE_KEY empty to use the local server (node site/serve.mjs), which answers at
// api/waitlist. On a static host such as GitHub Pages there is no server, so fill in the
// project's public key ("publishable" or "anon" in Supabase, under Project Settings, API keys).
// That key is meant to be public: it can only call waitlist_join and waitlist_stats
// (server/migrations/005_waitlist_public.sql). Never put the secret or service_role key here.
export const SUPABASE_URL = 'https://comeeuzwevgahiuibjit.supabase.co';
export const SUPABASE_KEY = 'sb_publishable_cped6rsyg4oXa7MJJFafqA_4QJQF7ao';
