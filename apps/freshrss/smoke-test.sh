#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-freshrss-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"

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

echo "FreshRSS smoke test passed on $published"
