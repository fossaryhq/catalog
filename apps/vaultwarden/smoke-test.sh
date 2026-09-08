#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-vaultwarden-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
volume="${VAULTWARDEN_DATA_VOLUME:-${project}-data}"
response="$(mktemp)"
backup_dir="$(mktemp -d)"

export VAULTWARDEN_PORT=0
export VAULTWARDEN_DOMAIN=http://localhost
export VAULTWARDEN_SIGNUPS_ALLOWED=false
export VAULTWARDEN_INVITATIONS_ALLOWED=false
export VAULTWARDEN_DATA_VOLUME="$volume"
export VAULTWARDEN_BACKUP_DIR="$backup_dir"
export TZ=UTC
export COMPOSE_PROJECT_NAME="$project"

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

container_id="$("${compose[@]}" ps --quiet vaultwarden)"
test -n "$container_id"
health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container_id")"
test "$health" = healthy

published="$("${compose[@]}" port vaultwarden 80)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac

curl --fail --silent --show-error \
  --retry 10 --retry-all-errors --retry-delay 2 \
  --connect-timeout 3 --max-time 20 \
  --output "$response" "http://${published}/api/version"
grep --fixed-strings --line-regexp --quiet '"1.37.2"' "$response"

# Verify that backup and restore preserve volume data, not only container health.
docker exec "$container_id" touch /data/fossary-restore-check
bash "$app_dir/backup.sh"
archives=("$backup_dir"/vaultwarden-*.tar.gz)
test -f "${archives[0]}"
docker exec "$container_id" rm /data/fossary-restore-check
bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout 360
docker exec "$container_id" test -f /data/fossary-restore-check

echo "Vaultwarden smoke test passed on $published"
