#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-paperless-ngx-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
status_file="$(mktemp)"

export PAPERLESS_PORT=0
export PAPERLESS_URL=http://localhost:8000
export PAPERLESS_SECRET_KEY="smoke-secret-${project}"
export PAPERLESS_DB_PASSWORD="smoke-db-${project}"
export PAPERLESS_DATA_VOLUME="${project}-data"
export PAPERLESS_MEDIA_VOLUME="${project}-media"
export PAPERLESS_EXPORT_VOLUME="${project}-export"
export PAPERLESS_CONSUME_VOLUME="${project}-consume"
export PAPERLESS_DB_VOLUME="${project}-database"
export PAPERLESS_BROKER_VOLUME="${project}-broker"
export COMPOSE_PROJECT_NAME="$project"

compose=(docker compose --project-name "$project" --env-file "$app_dir/.env.example" --file "$app_dir/compose.yaml")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=300
  "${compose[@]}" down --volumes --remove-orphans --timeout 60
  rm -f "$status_file"
  exit "$status"
}
# Every failed check names itself: `grep --quiet` and `test` say nothing, and all
# the CI log would keep of them is an exit code.
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach --wait --wait-timeout "${SMOKE_WAIT_TIMEOUT:-600}"
published="$("${compose[@]}" port webserver 8000)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac
curl --silent --show-error --output /dev/null --write-out '%{http_code}' "http://${published}/" > "$status_file"
grep --extended-regexp --quiet '^30[1278]$' "$status_file"

echo "Paperless-ngx smoke test passed on $published"
