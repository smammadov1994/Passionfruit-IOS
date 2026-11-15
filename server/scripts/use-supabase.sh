#!/bin/sh
# Points the server at a Supabase database and applies the migrations.
#
#   npm run db:use-supabase
#
# Takes the database password (from supabase-password.txt, else a hidden prompt), builds the connection string for
# this project's Session pooler, writes it to .env in place of the
# current DATABASE_URL, turns SSL on, and runs the migrations. The previous .env is kept as
# .env.local-backup, so `cp .env.local-backup .env` goes back to local Postgres.
set -eu
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "No .env here. Copy .env.example to .env first."; exit 1; }

# The project's Session pooler address (Supabase > Connect > Direct). Only the password is missing.
PG_USER="${SUPABASE_DB_USER:-postgres.comeeuzwevgahiuibjit}"
PG_HOST="${SUPABASE_DB_HOST:-aws-0-us-west-2.pooler.supabase.com}"

echo "Database: $PG_USER @ $PG_HOST"
# The password comes from the file supabase-password.txt if it has one (the file is deleted as soon
# as it is read); otherwise it is asked for here.
PASSWORD_FILE="supabase-password.txt"
PASSWORD=""
if [ -s "$PASSWORD_FILE" ]; then
  PASSWORD=$(head -n 1 "$PASSWORD_FILE" | tr -d '\r\n')
  rm -f "$PASSWORD_FILE"
  echo "Read the password from $PASSWORD_FILE and deleted that file."
else
  rm -f "$PASSWORD_FILE"
  echo "Type or paste only your Supabase DATABASE PASSWORD (not the whole address)."
  printf "Password (hidden), then press Return: "
  stty -echo 2>/dev/null || true
  read -r PASSWORD || true
  stty echo 2>/dev/null || true
  echo
fi

if [ -z "$PASSWORD" ]; then
  echo "No password entered. Nothing changed."
  exit 1
fi
case "$PASSWORD" in
  *"://"*|*"YOUR-PASSWORD"*) echo "That looks like an address or the placeholder, not the password. Nothing changed."; exit 1 ;;
esac

# Percent-encode the password so characters like @ : / # are safe inside the address.
ENCODED=$(printf '%s' "$PASSWORD" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>process.stdout.write(encodeURIComponent(d)))')
URL="postgresql://$PG_USER:$ENCODED@$PG_HOST:5432/postgres"

cp .env .env.local-backup
# Drop every existing DATABASE_URL / DATABASE_SSL line (commented or not), then append the new ones.
grep -v -E '^#? ?DATABASE_(URL|SSL|SSL_CA_PATH)=' .env.local-backup > .env
{
  echo ""
  echo "# Supabase (set by scripts/use-supabase.sh)"
  echo "DATABASE_URL=$URL"
  echo "DATABASE_SSL=1"
  # Supabase signs its database certificate with its own authority; verify against it.
  if [ -f certs/supabase-ca.crt ]; then echo "DATABASE_SSL_CA_PATH=./certs/supabase-ca.crt"; fi
} >> .env

echo "Applying migrations…"
if npm run --silent migrate; then
  echo "Done. Restart the server: npm run dev"
else
  cp .env.local-backup .env
  echo "Migration failed, so .env was put back to what it was."
  echo "If the error above mentions a certificate: in Supabase open Database settings > SSL"
  echo "configuration, download the certificate, save it as certs/supabase-ca.crt, set"
  echo "DATABASE_SSL_CA_PATH=./certs/supabase-ca.crt in .env, and run this again."
  echo "If it says password authentication failed: the password is wrong; reset it in Supabase."
  exit 1
fi
