#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="smoke-karakeep-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$"
export COMPOSE_PROJECT_NAME="$project"
export KARAKEEP_PORT=0 KARAKEEP_DISABLE_SIGNUPS=false
export KARAKEEP_AUTH_SECRET="$(openssl rand -hex 32)" KARAKEEP_MEILI_KEY="$(openssl rand -hex 32)"
scratch="$(mktemp -d)"
export FOSSARY_ENV_FILE="$scratch/.env" KARAKEEP_BACKUP_DIR="$scratch/backups"
write_env() {
  cp "$app_dir/.env.example" "$FOSSARY_ENV_FILE"
  for key in KARAKEEP_PORT KARAKEEP_URL KARAKEEP_AUTH_SECRET KARAKEEP_MEILI_KEY KARAKEEP_DISABLE_SIGNUPS KARAKEEP_BACKUP_DIR; do
    printf '%s=%q\n' "$key" "${!key}" >> "$FOSSARY_ENV_FILE"
  done
}
export KARAKEEP_URL=http://localhost:3000
write_env
compose=(docker compose --project-name "$project" --env-file "$FOSSARY_ENV_FILE" --file "$app_dir/compose.yaml")
cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=200
  "${compose[@]}" down --volumes --remove-orphans --timeout 30
  rm -rf "$scratch"
  exit "$status"
}
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM
"${compose[@]}" config --quiet
"${compose[@]}" pull --quiet
"${compose[@]}" up -d --wait --wait-timeout "${SMOKE_WAIT_TIMEOUT:-600}"
address="$("${compose[@]}" port karakeep 3000)"
export KARAKEEP_URL="http://$address"
# Recreate with the exact origin used by the HTTP client and keep the allocated port.
export KARAKEEP_PORT="${address##*:}"
write_env
"${compose[@]}" up -d --wait --wait-timeout 600 karakeep
node "$app_dir/smoke-api.mjs" "$KARAKEEP_URL" seed "$scratch/state.json"
"${compose[@]}" exec -T karakeep sh -c 'printf recovery-asset > /data/fossary-recovery.txt'
bash "$app_dir/backup.sh"
archive="$(find "$KARAKEEP_BACKUP_DIR" -maxdepth 1 -name 'karakeep-*.tar' -print -quit)"
[[ "$(stat -c %a "$archive")" == 600 ]]
original_hash="$(sha256sum "$archive")"
"${compose[@]}" down --volumes --remove-orphans
"${compose[@]}" up -d --wait --wait-timeout 600
bash "$app_dir/restore.sh" "$archive"
[[ "$(sha256sum "$archive")" == "$original_hash" ]]
node "$app_dir/smoke-api.mjs" "$KARAKEEP_URL" verify "$scratch/state.json"
[[ "$("${compose[@]}" exec -T karakeep cat /data/fossary-recovery.txt)" == recovery-asset ]]
export KARAKEEP_DISABLE_SIGNUPS=true
write_env
"${compose[@]}" up -d --wait --wait-timeout 600 karakeep
node "$app_dir/smoke-api.mjs" "$KARAKEEP_URL" closed "$scratch/state.json"
echo "Karakeep application, closed registration and volume-loss recovery passed on $(uname -m)"
