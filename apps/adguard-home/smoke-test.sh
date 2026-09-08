#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-adguard-home-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
conf_volume="${ADGUARD_CONF_VOLUME:-${project}-conf}"
work_volume="${ADGUARD_WORK_VOLUME:-${project}-work}"
response="$(mktemp)"
backup_dir="$(mktemp -d)"

# A domain in the reserved .invalid TLD: it does not exist in global DNS, so
# blocking is verified without ever reaching an upstream server.
blocked_host="smoke.fossary.invalid"
admin_user="smoke"
admin_password="Sm0ke-AdGuard-Password-2026"

# Port 0 asks for an ephemeral port: 53 on the runner is usually held by systemd-resolved.
export ADGUARD_DNS_BIND=127.0.0.1
export ADGUARD_DNS_PORT=0
export ADGUARD_WEB_PORT=0
export ADGUARD_CONF_VOLUME="$conf_volume"
export ADGUARD_WORK_VOLUME="$work_volume"
export TZ=UTC
export COMPOSE_PROJECT_NAME="$project"
export ADGUARD_BACKUP_DIR="$backup_dir"

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
  docker volume rm --force "$conf_volume" "$work_volume" >/dev/null 2>&1
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
"${compose[@]}" up --detach --wait --wait-timeout 300

container_id="$("${compose[@]}" ps --quiet adguard-home)"
test -n "$container_id"
health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container_id")"
test "$health" = healthy

web="$("${compose[@]}" port adguard-home 3000)"
case "$web" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published web address: $web" >&2; exit 1 ;;
esac

# With the defaults, DNS must not leave localhost either.
dns="$("${compose[@]}" port --protocol udp adguard-home 53)"
case "$dns" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published DNS address: $dns" >&2; exit 1 ;;
esac

# Until the wizard finishes, the install API is reachable without authentication.
curl --fail --silent --show-error --location \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${web}/control/install/get_addresses"
grep --fixed-strings --quiet '"interfaces"' "$response"

# First-run wizard: inside the container the panel stays on 3000 and DNS on 53.
curl --fail --silent --show-error \
  --connect-timeout 3 --max-time 60 \
  --header 'Content-Type: application/json' \
  --data "{\"web\":{\"ip\":\"0.0.0.0\",\"port\":3000},\"dns\":{\"ip\":\"0.0.0.0\",\"port\":53},\"username\":\"${admin_user}\",\"password\":\"${admin_password}\"}" \
  --output "$response" "http://${web}/control/install/configure"

curl --fail --silent --show-error --location \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --user "${admin_user}:${admin_password}" \
  --output "$response" "http://${web}/control/status"
grep --fixed-strings --quiet '"running":true' "$response"

# A custom filtering rule verifies filtering without any external block list.
curl --fail --silent --show-error \
  --connect-timeout 3 --max-time 30 \
  --user "${admin_user}:${admin_password}" \
  --header 'Content-Type: application/json' \
  --data "{\"rules\":[\"||${blocked_host}^\"]}" \
  --output "$response" "http://${web}/control/filtering/set_rules"

curl --fail --silent --show-error --location \
  --retry 10 --retry-all-errors --retry-delay 2 \
  --connect-timeout 3 --max-time 30 \
  --user "${admin_user}:${admin_password}" \
  --output "$response" "http://${web}/control/filtering/check_host?name=${blocked_host}"
grep --fixed-strings --quiet '"reason":"FilteredBlackList"' "$response"

# A real DNS query to the server: the filter answers it, no upstream needed.
docker exec "$container_id" nslookup "$blocked_host" 127.0.0.1 > "$response"
grep --fixed-strings --quiet '0.0.0.0' "$response"

# Backup and restore must preserve both data directories.
docker exec "$container_id" touch /opt/adguardhome/work/fossary-restore-check
bash "$app_dir/backup.sh"
archives=("$backup_dir"/adguard-home-*.tar.gz)
test -f "${archives[0]}"
docker exec "$container_id" rm /opt/adguardhome/work/fossary-restore-check

bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout 300

container_id="$("${compose[@]}" ps --quiet adguard-home)"
docker exec "$container_id" test -f /opt/adguardhome/work/fossary-restore-check
docker exec "$container_id" test -f /opt/adguardhome/conf/AdGuardHome.yaml

web="$("${compose[@]}" port adguard-home 3000)"
curl --fail --silent --show-error --location \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --user "${admin_user}:${admin_password}" \
  --output "$response" "http://${web}/control/status"
grep --fixed-strings --quiet '"running":true' "$response"

echo "AdGuard Home smoke test passed on $web"
