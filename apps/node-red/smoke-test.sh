#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-node-red-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
volume="${NODE_RED_DATA_VOLUME:-${project}-data}"
response="$(mktemp)"
backup_dir="$(mktemp -d)"

export NODE_RED_PORT=0 NODE_RED_DATA_VOLUME="$volume" NODE_RED_BACKUP_DIR="$backup_dir"
export NODE_RED_ADMIN_USERNAME=smoke-admin
export NODE_RED_ADMIN_PASSWORD_HASH='$2b$08$au5IWB89G8ucLBFZPb3imed9DG8slcAvw7hkpgbdo.Zf/arcqtgwS'
export NODE_RED_CREDENTIAL_SECRET=smoke-credential-secret-not-for-production
export TZ=Etc/UTC COMPOSE_PROJECT_NAME="$project"
compose=(docker compose --project-name "$project" --env-file "$app_dir/.env.example" --file "$app_dir/compose.yaml")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=250
  "${compose[@]}" down --volumes --remove-orphans --timeout 45
  docker volume rm --force "$volume" >/dev/null 2>&1 || true
  rm -f "$response"; rm -rf "$backup_dir"
  exit "$status"
}
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach --wait --wait-timeout 300

container="$("${compose[@]}" ps --quiet node-red)"
test -n "$container"
test "$(docker inspect --format '{{.State.Health.Status}}' "$container")" = healthy
published="$("${compose[@]}" port node-red 1880)"
case "$published" in 127.0.0.1:[0-9]*) ;; *) echo "Unexpected published address: $published" >&2; exit 1 ;; esac

# A saved HTTP flow proves that the editor API, runtime, deployment and flow
# persistence work—not merely that the editor's HTML is reachable.
curl --fail --silent --show-error --retry 30 --retry-all-errors --retry-delay 2 \
  --output "$response" "http://${published}/"
grep --fixed-strings --quiet 'Node-RED' "$response"
token="$(curl --fail --silent --show-error --data 'client_id=node-red-admin&grant_type=password&scope=*&username=smoke-admin&password=smoke-password' "http://${published}/auth/token" | jq --raw-output '.access_token')"
test "$token" != null
flow='{"label":"Fossary smoke","nodes":[{"id":"fossary-http","type":"http in","name":"Fossary smoke endpoint","url":"/fossary-smoke","method":"get","wires":[["fossary-function"]]},{"id":"fossary-function","type":"function","name":"Respond","func":"msg.payload = '\''Node-RED smoke flow'\''; return msg;","outputs":1,"wires":[["fossary-response"]]},{"id":"fossary-response","type":"http response","name":"Return text","wires":[]}]}'
curl --fail --silent --show-error -H "Authorization: Bearer $token" -H 'Content-Type: application/json' --data "$flow" \
  --output "$response" "http://${published}/flow"
grep --fixed-strings --quiet 'id' "$response"

for _ in $(seq 1 20); do
  if curl --fail --silent --show-error --output "$response" "http://${published}/fossary-smoke" \
    && grep --fixed-strings --quiet 'Node-RED smoke flow' "$response"; then break; fi
  sleep 2
done
grep --fixed-strings --quiet 'Node-RED smoke flow' "$response"

docker run --rm -v "${volume}:/data" alpine:3.22 touch /data/fossary-restore-check
bash "$app_dir/backup.sh"
archives=("$backup_dir"/node-red-*.tar.gz)
test -f "${archives[0]}"
docker run --rm -v "${volume}:/data" alpine:3.22 sh -c 'rm -f /data/fossary-restore-check /data/flows.json'
bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout 300
docker run --rm -v "${volume}:/data:ro" alpine:3.22 test -f /data/fossary-restore-check
published="$("${compose[@]}" port node-red 1880)"
curl --fail --silent --show-error --retry 20 --retry-all-errors --retry-delay 2 \
  --output "$response" "http://${published}/fossary-smoke"
grep --fixed-strings --quiet 'Node-RED smoke flow' "$response"
echo "Node-RED smoke test passed on $published"
