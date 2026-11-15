#!/bin/sh
# Sends the two secrets the server needs to Fly.io, read from .env without printing them:
# the session signing key and the database address (which contains the database password).
set -eu
cd "$(dirname "$0")/.."
[ -f .env ] || { echo "No .env here."; exit 1; }
JWT=$(grep -E '^JWT_SECRET=' .env | tail -n 1 | cut -d= -f2-)
DB=$(grep -E '^DATABASE_URL=' .env | tail -n 1 | cut -d= -f2-)
case "$DB" in
  *supabase.com*) ;;
  *) echo ".env does not point at Supabase (run npm run db:use-supabase first). Nothing sent."; exit 1 ;;
esac
[ -n "$JWT" ] || { echo "JWT_SECRET is empty in .env. Nothing sent."; exit 1; }
fly secrets set --stage "JWT_SECRET=$JWT" "DATABASE_URL=$DB"
echo "Secrets staged. They take effect on the next: fly deploy"
