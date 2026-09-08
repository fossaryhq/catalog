#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-stirling-pdf-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
response="$(mktemp)"
data_path="$(mktemp -d)"

export STIRLING_PDF_PORT=0
export STIRLING_PDF_URL=http://localhost:8080
export STIRLING_PDF_DATA_PATH="$data_path"
export STIRLING_PDF_INITIAL_USERNAME=smoke-admin
export STIRLING_PDF_INITIAL_PASSWORD="smoke-${project}-password"
export COMPOSE_PROJECT_NAME="$project"

compose=(docker compose --project-name "$project" --env-file "$app_dir/.env.example" --file "$app_dir/compose.yaml")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=300
  "${compose[@]}" down --volumes --remove-orphans --timeout 60
  rm -rf "$response" "$data_path"
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
published="$("${compose[@]}" port stirling-pdf 8080)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac
curl --fail --silent --show-error \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/api/v1/info/status"
grep --fixed-strings --quiet '"status":"UP"' "$response"

echo "Stirling PDF smoke test passed on $published"
