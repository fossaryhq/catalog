#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-n8n-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
data_volume="${N8N_DATA_VOLUME:-${project}-data}"
db_volume="${N8N_DB_VOLUME:-${project}-database}"
response="$(mktemp)"
backup_dir="$(mktemp -d)"

export N8N_PORT=0
export N8N_DATA_VOLUME="$data_volume"
export N8N_DB_VOLUME="$db_volume"
export N8N_DB_NAME=n8n
export N8N_DB_USER=n8n
db_password="smoke-$(date +%s)-db"
export N8N_DB_PASSWORD="$db_password"
# The key is generated per run: the volume is fresh every time, and a constant in
# the repository would look like a real secret and trip secret scanning.
encryption_key="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export N8N_ENCRYPTION_KEY="$encryption_key"
export N8N_PUBLIC_HOST=localhost
export N8N_PROTOCOL=http
export N8N_WEBHOOK_URL=
export N8N_SECURE_COOKIE=true
export N8N_PROXY_HOPS=0
export N8N_DIAGNOSTICS=false
export N8N_VERSION_NOTIFICATIONS=false
export N8N_EXECUTIONS_MAX_AGE_HOURS=336
export TZ=UTC
export COMPOSE_PROJECT_NAME="$project"
export N8N_BACKUP_DIR="$backup_dir"

compose=(
  docker compose
  --project-name "$project"
  --env-file "$app_dir/.env.example"
  --file "$app_dir/compose.yaml"
)

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=200
  "${compose[@]}" down --volumes --remove-orphans --timeout 60
  docker volume rm --force "$data_volume" "$db_volume" >/dev/null 2>&1
  rm -f "$response"
  rm -rf "$backup_dir"
  exit "$status"
}
# Every failed check names itself: `grep --quiet` and `test` say nothing, and all
# the CI log would keep of them is an exit code.
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach --wait --wait-timeout 600

for service in n8n database; do
  container="$("${compose[@]}" ps --quiet "$service")"
  test -n "$container"
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container")"
  test "$health" = healthy
done

published="$("${compose[@]}" port n8n 5678)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac

# The database is not published: the service has no ports section. This inspects
# the output rather than the exit code, because `docker compose port` (2.38)
# prints `:0` and exits zero for an unpublished port on a running service, so a
# check on the exit code always passed.
db_published="$("${compose[@]}" port database 5432 2>/dev/null || true)"
case "${db_published:-:0}" in
  "" | :0) ;;
  *) echo "PostgreSQL must not be published to the host: $db_published" >&2; exit 1 ;;
esac

# Check the response body and say why it failed: a bare `grep --quiet` fails the
# smoke test silently, leaving the CI log nothing but an exit code.
expect_in_response() {
  # $1 is the substring to look for, $2 names what is being checked.
  if ! grep --fixed-strings --quiet "$1" "$response"; then
    echo "$2: the response does not contain '$1'" >&2
    echo "Start of the response:" >&2
    head --bytes=400 "$response" >&2
    echo >&2
    exit 1
  fi
}

# `up --wait` relies on `/healthz`, which already answers 200 while the database
# migrations run. n8n reports readiness on a separate endpoint that returns 503
# until the migrations finish, and in that window `/rest/settings` can flash a
# 200 with a partial body and drop back to 404 — a curl retry does not save you.
deadline=$((SECONDS + 300))
while :; do
  ready="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 3 --max-time 15 "http://${published}/healthz/readiness" || true)"
  if [[ $ready == 200 ]]; then
    break
  fi
  if ((SECONDS >= deadline)); then
    echo "n8n did not become ready within 300s, last /healthz/readiness code: $ready" >&2
    exit 1
  fi
  echo "Waiting for n8n readiness, /healthz/readiness=$ready"
  sleep 5
done

curl --fail --silent --show-error --location \
  --retry 30 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/healthz"
expect_in_response '"status":"ok"' "/healthz"

# An application-level request: the frontend fetches instance settings here.
curl --fail --silent --show-error --location \
  --retry 30 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/rest/settings"
expect_in_response 'userManagement' "/rest/settings"

# The schema must live in PostgreSQL, not in the fallback SQLite inside the container.
tables="$("${compose[@]}" exec -T database \
  psql --dbname=n8n --username=n8n --tuples-only --no-align \
  --command "select count(*) from information_schema.tables where table_schema = 'public'")"
if [[ ${tables//[[:space:]]/} -le 0 ]]; then
  echo "No tables in the public schema: the n8n migrations did not run (got '$tables')" >&2
  exit 1
fi
if "${compose[@]}" exec -T n8n test -f /home/node/.n8n/database.sqlite; then
  echo "n8n fell back to SQLite instead of PostgreSQL" >&2
  exit 1
fi

# Backup and restore must preserve both the data directory and the database contents.
"${compose[@]}" exec -T n8n touch /home/node/.n8n/fossary-restore-check
"${compose[@]}" exec -T database \
  psql --dbname=n8n --username=n8n --command "create table fossary_restore_check (id int)" >/dev/null

bash "$app_dir/backup.sh"
archives=("$backup_dir"/n8n-*.tar)
if [[ ! -f ${archives[0]} ]]; then
  echo "backup.sh produced no archive in $backup_dir" >&2
  exit 1
fi

"${compose[@]}" exec -T n8n rm /home/node/.n8n/fossary-restore-check
"${compose[@]}" exec -T database \
  psql --dbname=n8n --username=n8n --command "drop table fossary_restore_check" >/dev/null

bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout 600

"${compose[@]}" exec -T n8n test -f /home/node/.n8n/fossary-restore-check
restored="$("${compose[@]}" exec -T database \
  psql --dbname=n8n --username=n8n --tuples-only --no-align \
  --command "select count(*) from information_schema.tables where table_schema = 'public' and table_name = 'fossary_restore_check'")"
if [[ ${restored//[[:space:]]/} != 1 ]]; then
  echo "The fossary_restore_check table is missing after the restore (got '$restored')" >&2
  exit 1
fi

published="$("${compose[@]}" port n8n 5678)"
curl --fail --silent --show-error --location \
  --retry 30 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/healthz"
grep --fixed-strings --quiet '"status":"ok"' "$response"

echo "n8n smoke test passed on $published"
