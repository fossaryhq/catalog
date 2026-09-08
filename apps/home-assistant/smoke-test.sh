#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-home-assistant-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
config_volume="${HOMEASSISTANT_CONFIG_VOLUME:-${project}-config}"
response="$(mktemp)"
backup_dir="$(mktemp -d)"

admin_user="smoke"
admin_password="Sm0ke-HomeAssistant-Password-2026"
automation_id="fossarysmoke"
automation_entity="automation.fossary_smoke"

# Port 0 asks for an ephemeral port: 8123 on the runner may be taken.
export HOMEASSISTANT_PORT=0
export HOMEASSISTANT_CONFIG_VOLUME="$config_volume"
export TZ=UTC
export COMPOSE_PROJECT_NAME="$project"
export HOMEASSISTANT_BACKUP_DIR="$backup_dir"

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
  "${compose[@]}" down --volumes --remove-orphans --timeout 60
  docker volume rm --force "$config_volume" >/dev/null 2>&1
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
# The first start unpacks the configuration into /config, so this waits longer than usual.
"${compose[@]}" up --detach --wait --wait-timeout 600

container_id="$("${compose[@]}" ps --quiet home-assistant)"
test -n "$container_id"
health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container_id")"
test "$health" = healthy

refresh_endpoint() {
  # Port 0 means a fresh ephemeral port on every container start, so the address
  # is read again after each stop.
  web="$("${compose[@]}" port home-assistant 8123)"
  case "$web" in
    127.0.0.1:[0-9]*) ;;
    *) echo "Unexpected published address: $web" >&2; exit 1 ;;
  esac
  client_id="http://${web}/"
}

refresh_endpoint

# Until the first-run wizard is complete its API needs no authentication.
curl --fail --silent --show-error --location \
  --retry 30 --retry-all-errors --retry-delay 4 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${web}/api/onboarding"
grep --fixed-strings --quiet '"step":"user"' "$response"

curl --fail --silent --show-error \
  --connect-timeout 3 --max-time 60 \
  --header 'Content-Type: application/json' \
  --data "{\"client_id\":\"${client_id}\",\"name\":\"Smoke Owner\",\"username\":\"${admin_user}\",\"password\":\"${admin_password}\",\"language\":\"en\"}" \
  --output "$response" "http://${web}/api/onboarding/users"
auth_code="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["auth_code"])' "$response")"
test -n "$auth_code"

exchange_token() {
  # $1 is the authorization code, from the first-run wizard or from the login flow.
  curl --fail --silent --show-error \
    --connect-timeout 3 --max-time 30 \
    --data-urlencode "grant_type=authorization_code" \
    --data-urlencode "code=$1" \
    --data-urlencode "client_id=${client_id}" \
    --output "$response" "http://${web}/auth/token"
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["access_token"])' "$response"
}

login_token() {
  # A full username and password sign-in: proves the user database survived.
  curl --fail --silent --show-error \
    --connect-timeout 3 --max-time 30 \
    --header 'Content-Type: application/json' \
    --data "{\"client_id\":\"${client_id}\",\"handler\":[\"homeassistant\",null],\"redirect_uri\":\"${client_id}?auth_callback=1\"}" \
    --output "$response" "http://${web}/auth/login_flow"
  local flow_id code
  flow_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["flow_id"])' "$response")"
  curl --fail --silent --show-error \
    --connect-timeout 3 --max-time 30 \
    --header 'Content-Type: application/json' \
    --data "{\"client_id\":\"${client_id}\",\"username\":\"${admin_user}\",\"password\":\"${admin_password}\"}" \
    --output "$response" "http://${web}/auth/login_flow/${flow_id}"
  code="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"])' "$response")"
  exchange_token "$code"
}

token="$(exchange_token "$auth_code")"
test -n "$token"

api_get() {
  curl --fail --silent --show-error --location \
    --retry 20 --retry-all-errors --retry-delay 3 \
    --connect-timeout 3 --max-time 30 \
    --header "Authorization: Bearer ${token}" \
    --output "$response" "http://${web}$1"
}

# The core must reach RUNNING, not recovery or safe mode. The state is polled
# rather than trusted on the first try: the healthcheck and `/api/config` answer
# before the integrations have loaded, so the first response carries
# `state: NOT_RUNNING`. A curl retry does not help — the HTTP code is already 200.
state=""
deadline=$((SECONDS + 240))
while :; do
  api_get /api/config
  state="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$response")"
  if [[ $state == RUNNING ]]; then
    break
  fi
  if ((SECONDS >= deadline)); then
    echo "Home Assistant did not reach RUNNING within 240s, last state: $state" >&2
    exit 1
  fi
  echo "Waiting for RUNNING, current state: $state"
  sleep 5
done

python3 - "$response" <<'PY'
import json, sys
config = json.load(open(sys.argv[1]))
assert config["state"] == "RUNNING", config["state"]
assert config["recovery_mode"] is False, "recovery mode"
assert config["safe_mode"] is False, "safe mode"
assert config["config_dir"] == "/config", config["config_dir"]
print(f"Home Assistant {config['version']} state={config['state']}")
PY

# The automation is both an application-level check and the artifact restore is
# verified against: the editor writes it to /config/automations.yaml.
curl --fail --silent --show-error \
  --connect-timeout 3 --max-time 30 \
  --header "Authorization: Bearer ${token}" \
  --header 'Content-Type: application/json' \
  --data '{"alias":"Fossary smoke","description":"","triggers":[{"trigger":"time","at":"03:15:00"}],"conditions":[],"actions":[{"action":"persistent_notification.create","data":{"message":"smoke"}}],"mode":"single"}' \
  --output "$response" "http://${web}/api/config/automation/config/${automation_id}"
grep --fixed-strings --quiet '"result":"ok"' "$response"

curl --fail --silent --show-error \
  --connect-timeout 3 --max-time 60 \
  --header "Authorization: Bearer ${token}" \
  --header 'Content-Type: application/json' \
  --data '{}' \
  --output "$response" "http://${web}/api/services/automation/reload"

api_get "/api/states/${automation_entity}"
grep --fixed-strings --quiet '"state":"on"' "$response"
docker exec "$container_id" grep --fixed-strings --quiet 'Fossary smoke' /config/automations.yaml

# Backup and restore must preserve both the automation and the user database.
bash "$app_dir/backup.sh"
archives=("$backup_dir"/home-assistant-*.tar.gz)
test -f "${archives[0]}"

# backup.sh starts the container but does not wait for it to be ready.
"${compose[@]}" up --detach --wait --wait-timeout 600
refresh_endpoint

# The server must come back up after being stopped for the archive.
api_get /api/config
grep --fixed-strings --quiet '"state":"RUNNING"' "$response"

curl --fail --silent --show-error --request DELETE \
  --connect-timeout 3 --max-time 30 \
  --header "Authorization: Bearer ${token}" \
  --output "$response" "http://${web}/api/config/automation/config/${automation_id}"
docker exec "$container_id" sh -c '! grep -q "Fossary smoke" /config/automations.yaml'

bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout 600

container_id="$("${compose[@]}" ps --quiet home-assistant)"
refresh_endpoint
docker exec "$container_id" grep --fixed-strings --quiet 'Fossary smoke' /config/automations.yaml
docker exec "$container_id" test -f /config/home-assistant_v2.db

# After a restore both the sign-in and the core state are checked.
token="$(login_token)"
test -n "$token"
api_get /api/config
grep --fixed-strings --quiet '"state":"RUNNING"' "$response"
api_get "/api/states/${automation_entity}"
grep --fixed-strings --quiet "${automation_entity}" "$response"

echo "Home Assistant smoke test passed on $web"
