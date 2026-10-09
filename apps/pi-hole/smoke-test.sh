#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-pi-hole-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
volume="${PIHOLE_VOLUME:-${project}-data}"
response="$(mktemp)"
cookie_jar="$(mktemp)"
backup_dir="$(mktemp -d)"
blocked_host="smoke.fossary.invalid"
expected_version="${PIHOLE_VERSION:-$(sed -n 's/^PIHOLE_VERSION=//p' "$app_dir/.env.example")}"

export COMPOSE_PROJECT_NAME="$project"
export PIHOLE_VOLUME="$volume"
export PIHOLE_DNS_BIND=127.0.0.1
export PIHOLE_DNS_PORT=0
export PIHOLE_WEB_PORT=0
export PIHOLE_WEB_PASSWORD="Sm0ke-PiHole-${project}-2026"
export PIHOLE_VERSION="$expected_version"
export PIHOLE_BACKUP_DIR="$backup_dir"
export TZ=Etc/UTC

compose=(docker compose --project-name "$project" --env-file "$app_dir/.env.example" --file "$app_dir/compose.yaml")

wait_for_blocked_dns() {
  # FTL reloads deny-list changes asynchronously; CLI success does not mean
  # the DNS worker has applied the new entry yet.
  for attempt in {1..30}; do
    if docker exec "$container_id" dig +time=1 +tries=1 +short @127.0.0.1 "$blocked_host" A > "$response" \
      && grep -Fxq '0.0.0.0' "$response"; then
      return 0
    fi
    sleep 1
  done
  echo "DNS did not block $blocked_host within 30 attempts; last response:" >&2
  cat "$response" >&2
  return 1
}

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=150
  "${compose[@]}" down --volumes --remove-orphans --timeout 30
  docker volume rm --force "$volume" >/dev/null 2>&1
  rm -f "$response" "$cookie_jar"
  rm -rf "$backup_dir"
  exit "$status"
}
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach --wait --wait-timeout 300

container_id="$("${compose[@]}" ps --quiet pi-hole)"
test -n "$container_id"
health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container_id")"
test "$health" = healthy

web="$("${compose[@]}" port pi-hole 80)"
dns="$("${compose[@]}" port --protocol udp pi-hole 53)"
case "$web" in 127.0.0.1:[0-9]*) ;; *) echo "Unexpected web bind: $web" >&2; exit 1 ;; esac
case "$dns" in 127.0.0.1:[0-9]*) ;; *) echo "Unexpected DNS bind: $dns" >&2; exit 1 ;; esac

# Authenticate against the real v6 API, then fetch the running versions.
curl --fail --silent --show-error --retry 20 --retry-all-errors --retry-delay 2 \
  --connect-timeout 3 --max-time 30 \
  --cookie-jar "$cookie_jar" \
  --header 'Content-Type: application/json' \
  --data "{\"password\":\"${PIHOLE_WEB_PASSWORD}\"}" \
  --output "$response" "http://${web}/api/auth"
grep -Eq '"valid"[[:space:]]*:[[:space:]]*true' "$response"
sid="$(sed -n 's/.*"sid":"\([^"]*\)".*/\1/p' "$response")"
test -n "$sid"
curl --fail --silent --show-error --header "X-FTL-SID: $sid" \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${web}/api/info/version"
grep -Fq "\"docker\":{\"local\":\"${expected_version}\"" "$response"

# Prove DNS blocking using a local-only, reserved .invalid domain.
docker exec "$container_id" pihole deny "$blocked_host"
wait_for_blocked_dns

# Verify a whole-volume backup and restore, including both SQLite databases.
docker exec "$container_id" touch /etc/pihole/fossary-restore-check
bash "$app_dir/backup.sh"
archives=("$backup_dir"/pi-hole-*.tar.gz)
test -f "${archives[0]}"
docker exec "$container_id" rm /etc/pihole/fossary-restore-check
bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout 300

container_id="$("${compose[@]}" ps --quiet pi-hole)"
docker exec "$container_id" test -f /etc/pihole/fossary-restore-check
docker exec "$container_id" test -f /etc/pihole/pihole.toml
docker exec "$container_id" test -f /etc/pihole/gravity.db
wait_for_blocked_dns

web="$("${compose[@]}" port pi-hole 80)"
curl --fail --silent --show-error \
  --connect-timeout 3 --max-time 30 \
  --cookie-jar "$cookie_jar" \
  --header 'Content-Type: application/json' \
  --data "{\"password\":\"${PIHOLE_WEB_PASSWORD}\"}" \
  --output "$response" "http://${web}/api/auth"
grep -Eq '"valid"[[:space:]]*:[[:space:]]*true' "$response"

echo "Pi-hole smoke test passed on $web"
