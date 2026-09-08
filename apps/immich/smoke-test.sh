#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-immich-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
db_volume="${IMMICH_DB_VOLUME:-${project}-database}"
model_cache_volume="${IMMICH_MODEL_CACHE_VOLUME:-${project}-model-cache}"
response="$(mktemp)"
backup_dir="$(mktemp -d)"
upload_location="$(mktemp -d)"

export IMMICH_PORT=0
export IMMICH_UPLOAD_LOCATION="$upload_location"
export IMMICH_DB_VOLUME="$db_volume"
export IMMICH_MODEL_CACHE_VOLUME="$model_cache_volume"
export IMMICH_DB_USERNAME=immich
export IMMICH_DB_DATABASE_NAME=immich
db_password="smoke$(date +%s)"
export IMMICH_DB_PASSWORD="$db_password"
export TZ=UTC
export COMPOSE_PROJECT_NAME="$project"
export IMMICH_BACKUP_DIR="$backup_dir"

compose=(
  docker compose
  --project-name "$project"
  --env-file "$app_dir/.env.example"
  --file "$app_dir/compose.yaml"
)

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=200
  "${compose[@]}" down --volumes --remove-orphans --timeout 30
  docker volume rm --force "$db_volume" "$model_cache_volume" >/dev/null 2>&1
  docker run --rm -v "${upload_location}:/target" alpine:3.22 \
    sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +' >/dev/null 2>&1
  rm -f "$response"
  rm -rf "$backup_dir" "$upload_location"
  exit "$status"
}
# Every failed check names itself: `grep --quiet` and `test` say nothing, and all
# the CI log would keep of them is an exit code.
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach --wait --wait-timeout 900

for service in immich-server immich-machine-learning redis database; do
  container_id="$("${compose[@]}" ps --quiet "$service")"
  test -n "$container_id"
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container_id")"
  test "$health" = healthy
done

server_id="$("${compose[@]}" ps --quiet immich-server)"
published="$("${compose[@]}" port immich-server 2283)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac

# An application-level API check, not just an open TCP port.
curl --fail --silent --show-error --location \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/api/server/ping"
grep --fixed-strings --quiet "pong" "$response"

# The server must report the version pinned in .env.example.
curl --fail --silent --show-error --location \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/api/server/version"
grep --fixed-strings --quiet '"major":3,"minor":1,"patch":0' "$response"

# Verify that backup and restore preserve both the database and the library files.
docker exec "$server_id" touch /data/fossary-restore-check
bash "$app_dir/backup.sh"
archives=("$backup_dir"/immich-*.tar)
test -f "${archives[0]}"
docker exec "$server_id" rm /data/fossary-restore-check

bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout 900

server_id="$("${compose[@]}" ps --quiet immich-server)"
docker exec "$server_id" test -f /data/fossary-restore-check
published="$("${compose[@]}" port immich-server 2283)"
curl --fail --silent --show-error --location \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/api/server/ping"
grep --fixed-strings --quiet "pong" "$response"

echo "Immich smoke test passed on $published"
