#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-forgejo-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
response="$(mktemp)"

export FORGEJO_HTTP_PORT=0
export FORGEJO_SSH_PORT=0
export FORGEJO_DOMAIN=localhost
export FORGEJO_SSH_DOMAIN=localhost
export FORGEJO_ROOT_URL=http://localhost/
export POSTGRES_PASSWORD="smoke-${project}"
export FORGEJO_DATA_VOLUME="${project}-data"
export FORGEJO_DB_VOLUME="${project}-database"
export COMPOSE_PROJECT_NAME="$project"

compose=(docker compose --project-name "$project" --env-file "$app_dir/.env.example" --file "$app_dir/compose.yaml")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=300
  "${compose[@]}" down --volumes --remove-orphans --timeout 60
  rm -f "$response"
  exit "$status"
}
# Every failed check names itself: `grep --quiet` and `test` say nothing, and all
# the CI log would keep of them is an exit code.
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach --wait --wait-timeout 360
published="$("${compose[@]}" port forgejo 3000)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac
curl --fail --silent --show-error --retry 10 --retry-all-errors --output "$response" "http://${published}/api/healthz"
grep --quiet '"status": *"pass"' "$response"

echo "Forgejo smoke test passed on $published"
