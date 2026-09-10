#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-freshrss-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
# backup.sh and restore.sh read their own .env and run `docker compose` beside
# it, so they are exercised from a copy of the recipe rather than from the
# catalog directory, which has no .env.
work_dir="$(mktemp -d)"
backup_dir="$(mktemp -d)"

export FRESHRSS_PORT=0
export FRESHRSS_BASE_URL=http://localhost:8080
export FRESHRSS_ADMIN_USER=freshrssadmin
export FRESHRSS_ADMIN_PASSWORD="SmokeLogin${project//[^A-Za-z0-9]/}"
export FRESHRSS_ADMIN_API_PASSWORD="SmokeApi${project//[^A-Za-z0-9]/}"
export FRESHRSS_DB_PASSWORD="SmokeDb${project//[^A-Za-z0-9]/}"
export FRESHRSS_DATA_VOLUME="${project}-data"
export FRESHRSS_EXTENSIONS_VOLUME="${project}-extensions"
export FRESHRSS_DB_VOLUME="${project}-database"
export COMPOSE_PROJECT_NAME="$project"

compose=(docker compose --project-name "$project" --env-file "$app_dir/.env.example" --file "$app_dir/compose.yaml")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=300
  "${compose[@]}" down --volumes --remove-orphans --timeout 60
  rm -rf "$work_dir" "$backup_dir"
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
published="$("${compose[@]}" port freshrss 80)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac
curl --fail --silent --show-error \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output /dev/null "http://${published}/i/"
"${compose[@]}" exec -T freshrss cli/health.php

# Verify that backup and restore preserve the database and the data volume, not
# only container health. A second user is a row in PostgreSQL and a directory
# under the data volume at once, so one check covers both halves of the archive.
"${compose[@]}" exec -T freshrss cli/create-user.php \
  --user smokerestore --password "SmokeRestore${project//[^A-Za-z0-9]/}"
"${compose[@]}" exec -T freshrss cli/list-users.php | grep --fixed-strings --line-regexp --quiet smokerestore

cp -- "$app_dir/compose.yaml" "$app_dir/backup.sh" "$app_dir/restore.sh" "$work_dir/"
{
  printf 'FRESHRSS_PORT=%s\n' "$FRESHRSS_PORT"
  printf 'FRESHRSS_BASE_URL=%s\n' "$FRESHRSS_BASE_URL"
  printf 'FRESHRSS_ADMIN_USER=%s\n' "$FRESHRSS_ADMIN_USER"
  printf 'FRESHRSS_ADMIN_PASSWORD=%s\n' "$FRESHRSS_ADMIN_PASSWORD"
  printf 'FRESHRSS_ADMIN_API_PASSWORD=%s\n' "$FRESHRSS_ADMIN_API_PASSWORD"
  printf 'FRESHRSS_DB_PASSWORD=%s\n' "$FRESHRSS_DB_PASSWORD"
  printf 'FRESHRSS_DATA_VOLUME=%s\n' "$FRESHRSS_DATA_VOLUME"
  printf 'FRESHRSS_EXTENSIONS_VOLUME=%s\n' "$FRESHRSS_EXTENSIONS_VOLUME"
  printf 'FRESHRSS_DB_VOLUME=%s\n' "$FRESHRSS_DB_VOLUME"
  printf 'FRESHRSS_BACKUP_DIR=%s\n' "$backup_dir"
} > "$work_dir/.env"

bash "$work_dir/backup.sh"
archives=("$backup_dir"/freshrss-*.tar)
test -f "${archives[0]}"
test "$(stat -c %a "${archives[0]}")" = 600

"${compose[@]}" exec -T freshrss cli/delete-user.php --user smokerestore
# An `if` condition is the one place a failing grep is the expected result, and
# neither `set -e` nor the ERR trap fires there.
if "${compose[@]}" exec -T freshrss cli/list-users.php | grep --fixed-strings --line-regexp --quiet smokerestore; then
  echo "delete-user.php did not remove the user the restore is meant to bring back" >&2
  exit 1
fi

bash "$work_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout 600
"${compose[@]}" exec -T freshrss cli/health.php
"${compose[@]}" exec -T freshrss cli/list-users.php | grep --fixed-strings --line-regexp --quiet smokerestore

echo "FreshRSS smoke test passed on $published"
