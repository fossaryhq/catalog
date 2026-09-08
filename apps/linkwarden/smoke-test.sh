#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-linkwarden-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"

export LINKWARDEN_PORT=0
export LINKWARDEN_URL=http://localhost:3000
export LINKWARDEN_USER_CONTENT_URL=http://localhost:3000
export NEXT_PUBLIC_DISABLE_REGISTRATION=false
export NEXTAUTH_SECRET="SmokeNextAuth${project//[^A-Za-z0-9]/}"
export POSTGRES_PASSWORD="SmokePostgres${project//[^A-Za-z0-9]/}"
export MEILI_MASTER_KEY="SmokeMeili${project//[^A-Za-z0-9]/}"
export LINKWARDEN_DATA_VOLUME="${project}-data"
export LINKWARDEN_DB_VOLUME="${project}-postgres"
export LINKWARDEN_MEILI_VOLUME="${project}-meilisearch"
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
"${compose[@]}" up --detach --wait --wait-timeout "${SMOKE_WAIT_TIMEOUT:-900}"
published="$("${compose[@]}" port linkwarden 3000)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac
curl --fail --silent --show-error \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output /dev/null "http://${published}/"

echo "Linkwarden smoke test passed on $published"
