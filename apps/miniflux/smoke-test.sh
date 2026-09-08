#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-miniflux-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
backup_dir="$(mktemp -d)"

export MINIFLUX_PORT=0
export MINIFLUX_BASE_URL=http://localhost:8080
export MINIFLUX_ADMIN_USER=smokeadmin
export MINIFLUX_ADMIN_PASSWORD="SmokeAdmin${project//[^A-Za-z0-9]/}"
export MINIFLUX_DB_PASSWORD="SmokePostgres${project//[^A-Za-z0-9]/}"
export MINIFLUX_DB_VOLUME="${project}-database"
export COMPOSE_PROJECT_NAME="$project"
export MINIFLUX_BACKUP_DIR="$backup_dir"
export FOSSARY_ENV_FILE=/dev/null

compose=(docker compose --project-name "$project" --env-file "$app_dir/.env.example" --file "$app_dir/compose.yaml")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=300
  "${compose[@]}" down --volumes --remove-orphans --timeout 60
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
published="$("${compose[@]}" port miniflux 8080)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac

# The readiness probe answers only after the database connection works, so it
# covers the migrations the container runs at startup.
curl --fail --silent --show-error \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  "http://${published}/healthcheck" | grep --quiet "OK"

# The login form is the first page an unauthenticated visitor gets; a redirect
# loop or a broken BASE_URL shows up here rather than in the probe.
curl --fail --silent --show-error \
  --connect-timeout 3 --max-time 30 \
  "http://${published}/" | grep --quiet "Miniflux"

# Restore must bring back PostgreSQL contents, not merely restart the service.
"${compose[@]}" exec -T database psql --username=miniflux --dbname=miniflux \
  --command='CREATE TABLE fossary_restore_check (id integer);' >/dev/null
bash "$app_dir/backup.sh"
archives=("$backup_dir"/miniflux-*.tar)
test -f "${archives[0]}"
"${compose[@]}" exec -T database psql --username=miniflux --dbname=miniflux \
  --command='DROP TABLE fossary_restore_check;' >/dev/null
bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" exec -T database psql --username=miniflux --dbname=miniflux --tuples-only \
  --command="SELECT to_regclass('public.fossary_restore_check');" | grep --quiet fossary_restore_check

echo "Miniflux smoke test passed on $published"
