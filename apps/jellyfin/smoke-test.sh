#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-jellyfin-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
config_volume="${JELLYFIN_CONFIG_VOLUME:-${project}-config}"
cache_volume="${JELLYFIN_CACHE_VOLUME:-${project}-cache}"
response="$(mktemp)"
backup_dir="$(mktemp -d)"
media_location="$(mktemp -d)"

mkdir -p "$media_location/Movies"

export JELLYFIN_PORT=0
export JELLYFIN_PUBLISHED_URL=http://127.0.0.1:8096
export JELLYFIN_MEDIA_LOCATION="$media_location"
export JELLYFIN_CONFIG_VOLUME="$config_volume"
export JELLYFIN_CACHE_VOLUME="$cache_volume"
export TZ=UTC
export COMPOSE_PROJECT_NAME="$project"
export JELLYFIN_BACKUP_DIR="$backup_dir"

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
  docker volume rm --force "$config_volume" "$cache_volume" >/dev/null 2>&1
  rm -f "$response"
  rm -rf "$backup_dir" "$media_location"
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

container_id="$("${compose[@]}" ps --quiet jellyfin)"
test -n "$container_id"
health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container_id")"
test "$health" = healthy

published="$("${compose[@]}" port jellyfin 8096)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac

curl --fail --silent --show-error --location \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/health"
grep --fixed-strings --quiet "Healthy" "$response"

# The server must report the version pinned in .env.example.
curl --fail --silent --show-error --location \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/System/Info/Public"
grep --fixed-strings --quiet '"Version":"10.11.11"' "$response"

# The media library is mounted read-only.
if docker exec "$container_id" sh -c 'touch /media/fossary-write-check' 2>/dev/null; then
  echo "Media mount must be read-only" >&2
  exit 1
fi

# Verify that backup and restore preserve the contents of the config volume.
docker exec "$container_id" touch /config/fossary-restore-check
bash "$app_dir/backup.sh"
archives=("$backup_dir"/jellyfin-*.tar.gz)
test -f "${archives[0]}"
docker exec "$container_id" rm /config/fossary-restore-check

bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout 600

container_id="$("${compose[@]}" ps --quiet jellyfin)"
docker exec "$container_id" test -f /config/fossary-restore-check
published="$("${compose[@]}" port jellyfin 8096)"
curl --fail --silent --show-error --location \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/health"
grep --fixed-strings --quiet "Healthy" "$response"

echo "Jellyfin smoke test passed on $published"
