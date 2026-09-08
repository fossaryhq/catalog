#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-navidrome-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
volume="${NAVIDROME_DATA_VOLUME:-${project}-data}"
response="$(mktemp)"
backup_dir="$(mktemp -d)"
music_location="$(mktemp -d)"

mkdir -p "$music_location/Demo"

export NAVIDROME_PORT=0
export NAVIDROME_MUSIC_LOCATION="$music_location"
export NAVIDROME_DATA_VOLUME="$volume"
export NAVIDROME_SCAN_INTERVAL=24h
export NAVIDROME_LOG_LEVEL=info
export NAVIDROME_SESSION_TIMEOUT=24h
export NAVIDROME_BASE_URL=
export NAVIDROME_INSIGHTS=false
export TZ=UTC
export COMPOSE_PROJECT_NAME="$project"
export NAVIDROME_BACKUP_DIR="$backup_dir"

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
  docker volume rm --force "$volume" >/dev/null 2>&1
  rm -f "$response"
  rm -rf "$backup_dir" "$music_location"
  exit "$status"
}
# Every failed check names itself: `grep --quiet` and `test` say nothing, and all
# the CI log would keep of them is an exit code.
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach --wait --wait-timeout 300

container_id="$("${compose[@]}" ps --quiet navidrome)"
test -n "$container_id"
health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container_id")"
test "$health" = healthy

published="$("${compose[@]}" port navidrome 4533)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac

curl --fail --silent --show-error --location \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/ping"
grep --fixed-strings --quiet "." "$response"

# Unauthenticated, the Subsonic API answers only with an error — but it states the server version.
curl --fail --silent --show-error --location \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/rest/ping?v=1.16.1&c=fossary-smoke&f=json"
grep --fixed-strings --quiet '"type":"navidrome"' "$response"
grep --fixed-strings --quiet '"serverVersion":"0.63.2' "$response"

# The media library is mounted read-only.
if docker exec "$container_id" sh -c 'touch /music/fossary-write-check' 2>/dev/null; then
  echo "Music mount must be read-only" >&2
  exit 1
fi

# Verify that backup and restore preserve the contents of the data directory.
docker exec "$container_id" touch /data/fossary-restore-check
bash "$app_dir/backup.sh"
archives=("$backup_dir"/navidrome-*.tar.gz)
test -f "${archives[0]}"
docker exec "$container_id" rm /data/fossary-restore-check

bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout 300

container_id="$("${compose[@]}" ps --quiet navidrome)"
docker exec "$container_id" test -f /data/fossary-restore-check
published="$("${compose[@]}" port navidrome 4533)"
curl --fail --silent --show-error --location \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/ping"
grep --fixed-strings --quiet "." "$response"

echo "Navidrome smoke test passed on $published"
