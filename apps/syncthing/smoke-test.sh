#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-syncthing-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
volume="${SYNCTHING_CONFIG_VOLUME:-${project}-config}"
response="$(mktemp)"
backup_dir="$(mktemp -d)"
data_location="$(mktemp -d)"

chmod 777 "$data_location"

# The sync ports are published externally, so the test picks free high ports.
sync_port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
discovery_port="$(python3 -c 'import socket;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"

export SYNCTHING_DEVICE_NAME=smoke
export SYNCTHING_GUI_PORT=0
export SYNCTHING_SYNC_PORT="$sync_port"
export SYNCTHING_DISCOVERY_PORT="$discovery_port"
export SYNCTHING_DATA_LOCATION="$data_location"
export SYNCTHING_CONFIG_VOLUME="$volume"
export SYNCTHING_UID=1000
export SYNCTHING_GID=1000
export TZ=UTC
export COMPOSE_PROJECT_NAME="$project"
export SYNCTHING_BACKUP_DIR="$backup_dir"

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
  docker run --rm -v "${data_location}:/target" alpine:3.22 \
    sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +' >/dev/null 2>&1
  rm -f "$response"
  rm -rf "$backup_dir" "$data_location"
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

container_id="$("${compose[@]}" ps --quiet syncthing)"
test -n "$container_id"
health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container_id")"
test "$health" = healthy

published="$("${compose[@]}" port syncthing 8384)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published GUI address: $published" >&2; exit 1 ;;
esac

# The web interface must not face outward; the sync port must.
sync_published="$("${compose[@]}" port --protocol tcp syncthing 22000)"
case "$sync_published" in
  0.0.0.0:*|"[::]":*) ;;
  *) echo "Sync port must be published on all interfaces, got: $sync_published" >&2; exit 1 ;;
esac

curl --fail --silent --show-error --location \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/rest/noauth/health"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "OK"' "$response"

# The server must report the version pinned in .env.example.
api_key="$(docker exec "$container_id" sh -c 'sed -n "s@.*<apikey>\(.*\)</apikey>.*@\1@p" /var/syncthing/config/config.xml')"
test -n "$api_key"
curl --fail --silent --show-error --location \
  --connect-timeout 3 --max-time 30 \
  --header "X-API-Key: $api_key" \
  --output "$response" "http://${published}/rest/system/version"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["version"] == "v2.1.3"' "$response"

# The sync directory is writable: without that the node is useless.
docker exec "$container_id" sh -c 'echo ok > /data/fossary-write-check'
test -f "$data_location/fossary-write-check"

# Verify that backup and restore preserve the keys and the device identifier.
device_id="$(curl --fail --silent --header "X-API-Key: $api_key" "http://${published}/rest/system/status" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["myID"])')"
test -n "$device_id"
docker exec "$container_id" touch /var/syncthing/fossary-restore-check
bash "$app_dir/backup.sh"
archives=("$backup_dir"/syncthing-*.tar.gz)
test -f "${archives[0]}"
docker exec "$container_id" rm /var/syncthing/fossary-restore-check

bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout 300

container_id="$("${compose[@]}" ps --quiet syncthing)"
docker exec "$container_id" test -f /var/syncthing/fossary-restore-check
published="$("${compose[@]}" port syncthing 8384)"
restored_id="$(curl --fail --silent --retry 20 --retry-all-errors --retry-delay 3 \
  --header "X-API-Key: $api_key" "http://${published}/rest/system/status" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["myID"])')"
test "$restored_id" = "$device_id"

echo "Syncthing smoke test passed on $published (device $device_id)"
