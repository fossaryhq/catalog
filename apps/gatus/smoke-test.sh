#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-gatus-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
volume="${GATUS_DATA_VOLUME:-${project}-data}"
response="$(mktemp)"
backup_dir="$(mktemp -d)"

export GATUS_PORT=0
export GATUS_DATA_VOLUME="$volume"
export GATUS_USERNAME=smoke-user
smoke_password=smoke-password-not-for-production
export GATUS_PASSWORD_BCRYPT_BASE64="$(
  docker run --rm caddy:2.11.2-alpine \
    caddy hash-password --plaintext "$smoke_password" | base64 | tr -d '\n'
)"
export GATUS_BACKUP_DIR="$backup_dir"
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
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach

container_id="$("${compose[@]}" ps --quiet gatus)"
test -n "$container_id"

published="$("${compose[@]}" port gatus 8080)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac

curl --fail --silent --show-error \
  --retry 30 --retry-all-errors --retry-delay 2 \
  --connect-timeout 3 --max-time 10 \
  --output "$response" "http://${published}/health"
grep --fixed-strings --quiet '"status":"UP"' "$response"

for _ in $(seq 1 30); do
  if curl --fail --silent --show-error \
    --user "$GATUS_USERNAME:$smoke_password" \
    --connect-timeout 3 --max-time 10 \
    --output "$response" "http://${published}/api/v1/endpoints/statuses" \
    && grep --fixed-strings --quiet 'Gatus health' "$response" \
    && grep --extended-regexp --quiet '"success":[[:space:]]*true' "$response"; then
    break
  fi
  sleep 2
done
grep --fixed-strings --quiet 'Gatus health' "$response"
grep --extended-regexp --quiet '"success":[[:space:]]*true' "$response"

# Verify that backup and restore preserve the volume, not only process health.
docker run --rm -v "${volume}:/data" alpine:3.22 touch /data/fossary-restore-check
bash "$app_dir/backup.sh"
archives=("$backup_dir"/gatus-*.tar.gz)
test -f "${archives[0]}"
docker run --rm -v "${volume}:/data" alpine:3.22 rm /data/fossary-restore-check
bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach
docker run --rm -v "${volume}:/data:ro" alpine:3.22 test -f /data/fossary-restore-check
restored_published="$("${compose[@]}" port gatus 8080)"
curl --fail --silent --show-error \
  --retry 30 --retry-all-errors --retry-delay 2 \
  --connect-timeout 3 --max-time 10 \
  --output "$response" "http://${restored_published}/health"
grep --fixed-strings --quiet '"status":"UP"' "$response"

echo "Gatus smoke test passed on $published"
