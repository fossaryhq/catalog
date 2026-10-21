#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-mealie-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
volume="${MEALIE_DATA_VOLUME:-${project}-data}"
version="$(sed -n 's/^MEALIE_VERSION=//p' "$app_dir/.env.example" | head -n 1)"
backup_dir="$(mktemp -d)"
response="$(mktemp)"
export COMPOSE_PROJECT_NAME="$project" MEALIE_VERSION="$version" MEALIE_PORT=0 MEALIE_DATA_VOLUME="$volume"
export MEALIE_BASE_URL=http://localhost:9925 MEALIE_BACKUP_DIR="$backup_dir"
compose=(docker compose --project-name "$project" --env-file "$app_dir/.env.example" --file "$app_dir/compose.yaml")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=150
  "${compose[@]}" down --volumes --remove-orphans --timeout 30
  docker volume rm --force "$volume" >/dev/null 2>&1
  rm -f "$response"
  rm -rf "$backup_dir"
  exit "$status"
}
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach --wait --wait-timeout 300
container_id="$("${compose[@]}" ps --quiet mealie)"
test -n "$container_id"
test "$(docker inspect --format '{{.State.Health.Status}}' "$container_id")" = healthy
published="$("${compose[@]}" port mealie 9000)"
case "$published" in 127.0.0.1:[0-9]*) ;; *) echo "Unexpected web bind: $published" >&2; exit 1 ;; esac

curl --fail --silent --show-error --retry 20 --retry-all-errors --retry-delay 2 \
  --connect-timeout 3 --max-time 30 --output "$response" "http://${published}/api/app/about"
grep -Fq "\"version\":\"${version}" "$response"
curl --fail --silent --show-error --output "$response" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'username=changeme@example.com' --data-urlencode 'password=MyPassword' \
  "http://${published}/api/auth/token"
grep -Fq '"access_token"' "$response"
token="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])' < "$response")"
curl --fail --silent --show-error --output "$response" \
  --header "Authorization: Bearer $token" "http://${published}/api/recipes"
grep -Fq '"items"' "$response"

# The public API requires a signed-in account; preserve its application data too.
docker exec "$container_id" sh -c 'printf "restore-check\n" > /app/data/fossary-restore-check'
bash "$app_dir/backup.sh"
archives=("$backup_dir"/mealie-*.tar.gz)
test -f "${archives[0]}"
docker exec "$container_id" rm /app/data/fossary-restore-check
bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout 300
container_id="$("${compose[@]}" ps --quiet mealie)"
docker exec "$container_id" grep -Fxq restore-check /app/data/fossary-restore-check
published="$("${compose[@]}" port mealie 9000)"
curl --fail --silent --show-error --retry 10 --retry-all-errors --retry-delay 2 \
  --connect-timeout 3 --max-time 30 --output "$response" "http://${published}/api/app/about"
grep -Fq "\"version\":\"${version}" "$response"
curl --fail --silent --show-error --output "$response" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'username=changeme@example.com' --data-urlencode 'password=MyPassword' \
  "http://${published}/api/auth/token"
grep -Fq '"access_token"' "$response"
token="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])' < "$response")"
curl --fail --silent --show-error --output "$response" \
  --header "Authorization: Bearer $token" "http://${published}/api/recipes"
grep -Fq '"items"' "$response"
echo "Mealie smoke test passed on $published"
