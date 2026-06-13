#!/usr/bin/env bash
# Apply pending Supabase migrations to the linked remote project.
#
# Reads SUPABASE_DB_PASSWORD from the repo-root .env (gitignored) and connects
# via the session-mode pooler, so no `supabase login` / access token is needed.
# The DB password is never printed (masked in any CLI output).
#
# Usage:
#   scripts/db-push.sh --dry-run     # preview which migrations would apply
#   scripts/db-push.sh --yes         # apply pending migrations
#   scripts/db-push.sh               # apply, prompting for confirmation
#
# Override the CLI location with SUPABASE_BIN if it's not at ~/tools/supabase.
set -euo pipefail
cd "$(dirname "$0")/.."

set -a
# shellcheck disable=SC1091
. ./.env
set +a
: "${SUPABASE_DB_PASSWORD:?SUPABASE_DB_PASSWORD not set in .env}"

SUPABASE_BIN="${SUPABASE_BIN:-$HOME/tools/supabase/supabase}"
PROJECT_REF="ehuanqnkqehpivwuqpqw"
POOLER_HOST="aws-1-us-east-1.pooler.supabase.com"

ENC=$(python3 -c "import os,urllib.parse;print(urllib.parse.quote(os.environ['SUPABASE_DB_PASSWORD'],safe=''))")
URL="postgresql://postgres.${PROJECT_REF}:${ENC}@${POOLER_HOST}:5432/postgres"

"$SUPABASE_BIN" db push --db-url "$URL" "$@" 2>&1 \
  | sed -E "s#(postgres\.[a-z0-9]+:)[^@]*@#\1***@#g; s#${ENC}#***#g"
