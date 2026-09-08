#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-uptime-kuma-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
volume="${UPTIME_KUMA_DATA_VOLUME:-${project}-data}"
response="$(mktemp)"
backup_dir="$(mktemp -d)"

export UPTIME_KUMA_PORT=0
export UPTIME_KUMA_DATA_VOLUME="$volume"
export TZ=UTC
export COMPOSE_PROJECT_NAME="$project"
export UPTIME_KUMA_BACKUP_DIR="$backup_dir"

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
  "${compose[@]}" logs --no-color --timestamps --tail=300
  "${compose[@]}" down --volumes --remove-orphans --timeout 30
  docker volume rm --force "$volume" >/dev/null 2>&1 || true
  rm -f "$response"
  rm -rf "$backup_dir"
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

container_id="$("${compose[@]}" ps --quiet uptime-kuma)"
test -n "$container_id"
health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container_id")"
test "$health" = healthy

published="$("${compose[@]}" port uptime-kuma 3001)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac

curl --fail --silent --show-error --location \
  --retry 10 --retry-all-errors --retry-delay 2 \
  --connect-timeout 3 --max-time 20 \
  --output "$response" "http://${published}/"
grep --fixed-strings --quiet "Uptime Kuma" "$response"

# Verify that backup and restore preserve volume data, not only container health.
docker exec "$container_id" touch /app/data/fossary-restore-check
bash "$app_dir/backup.sh"
archives=("$backup_dir"/uptime-kuma-*.tar.gz)
test -f "${archives[0]}"
docker exec "$container_id" rm /app/data/fossary-restore-check
bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout 360
docker exec "$container_id" test -f /app/data/fossary-restore-check

echo "Uptime Kuma smoke test passed on $published"
