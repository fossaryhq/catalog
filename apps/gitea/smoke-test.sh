#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-gitea-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
response="$(mktemp)"

export GITEA_HTTP_PORT=0
export GITEA_SSH_PORT=0
export GITEA_DOMAIN=localhost
export GITEA_SSH_DOMAIN=localhost
export GITEA_ROOT_URL=http://localhost/
export POSTGRES_PASSWORD="smoke-${project}"
export GITEA_DATA_VOLUME="${project}-data"
export GITEA_DB_VOLUME="${project}-database"
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
trap 'echo "Smoke test failed at line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach --wait --wait-timeout 360
published="$("${compose[@]}" port gitea 3000)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac
curl --fail --silent --show-error --retry 10 --retry-all-errors --output "$response" "http://${published}/api/healthz"
grep --quiet '"status": *"pass"' "$response"

echo "Gitea smoke test passed on $published"
