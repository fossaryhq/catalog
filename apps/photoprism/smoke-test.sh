#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-photoprism-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
originals="$(mktemp -d)"
storage="$(mktemp -d)"
response="$(mktemp)"

export PHOTOPRISM_PORT=0
export PHOTOPRISM_SITE_URL=http://localhost:2342/
export PHOTOPRISM_ADMIN_PASSWORD="smoke-admin-${project}"
export PHOTOPRISM_DATABASE_PASSWORD="smoke-db-${project}"
export PHOTOPRISM_DATABASE_ROOT_PASSWORD="smoke-root-${project}"
export PHOTOPRISM_DATABASE_VOLUME="${project}-database"
export PHOTOPRISM_ORIGINALS_PATH="$originals"
export PHOTOPRISM_STORAGE_PATH="$storage"
# The container does not run as root, so the bind directories must belong to it.
PHOTOPRISM_UID="$(id -u)"
PHOTOPRISM_GID="$(id -g)"
export PHOTOPRISM_UID PHOTOPRISM_GID
export TZ=UTC
export COMPOSE_PROJECT_NAME="$project"

compose=(docker compose --project-name "$project" --env-file "$app_dir/.env.example" --file "$app_dir/compose.yaml")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=300
  "${compose[@]}" down --volumes --remove-orphans --timeout 60
  docker volume rm --force "${project}-database" >/dev/null 2>&1
  rm -rf "$originals" "$storage"
  rm -f "$response"
  exit "$status"
}
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach --wait --wait-timeout 900

published="$("${compose[@]}" port photoprism 2342)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac

curl --fail --silent --show-error --location \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/api/v1/status"
grep --extended-regexp --quiet '"status"[[:space:]]*:[[:space:]]*"operational"' "$response"

echo "PhotoPrism smoke test passed on $published"
