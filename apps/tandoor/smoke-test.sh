#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export COMPOSE_PROJECT_NAME="smoke-tandoor-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$"
export TANDOOR_PORT=0
export TANDOOR_SECRET_KEY="$(openssl rand -hex 32)" TANDOOR_DB_PASSWORD="$(openssl rand -hex 24)"
scratch="$(mktemp -d)"
export FOSSARY_ENV_FILE="$scratch/.env" TANDOOR_BACKUP_DIR="$scratch/backups"
cp "$app_dir/.env.example" "$FOSSARY_ENV_FILE"
for key in TANDOOR_PORT TANDOOR_SECRET_KEY TANDOOR_DB_PASSWORD TANDOOR_BACKUP_DIR; do
  printf '%s=%q\n' "$key" "${!key}" >> "$FOSSARY_ENV_FILE"
done
compose=(docker compose --project-name "$COMPOSE_PROJECT_NAME" --env-file "$FOSSARY_ENV_FILE" --file "$app_dir/compose.yaml")
cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=120
  "${compose[@]}" down --volumes --remove-orphans --timeout 30
  rm -rf "$scratch"
  exit "$status"
}
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM
"${compose[@]}" config --quiet
"${compose[@]}" pull --quiet
if TANDOOR_SECRET_KEY=replace-with-openssl-rand-hex-32 "${compose[@]}" run --rm --no-deps tandoor; then
  echo "Placeholder key unexpectedly started the application" >&2
  exit 1
else
  [[ $? -eq 2 ]] || { echo "Expected the credential guard to exit 2" >&2; exit 1; }
fi
"${compose[@]}" up -d --wait --wait-timeout "${SMOKE_WAIT_TIMEOUT:-600}"
published="$("${compose[@]}" port tandoor 80)"
[[ "$published" =~ ^127\.0\.0\.1:[0-9]+$ ]] || { echo "Unexpected published address: $published" >&2; exit 1; }
python3 "$app_dir/smoke-api.py" "http://$published" seed "$scratch/state.json"
bash "$app_dir/backup.sh"
archive="$(find "$TANDOOR_BACKUP_DIR" -maxdepth 1 -name 'tandoor-*.tar' -print -quit)"
[[ "$(stat -c %a "$archive")" == 600 ]]
original_hash="$(sha256sum "$archive")"
"${compose[@]}" down --volumes --remove-orphans
"${compose[@]}" up -d --wait --wait-timeout 600
bash "$app_dir/restore.sh" "$archive"
[[ "$(sha256sum "$archive")" == "$original_hash" ]]
published="$("${compose[@]}" port tandoor 80)"
python3 "$app_dir/smoke-api.py" "http://$published" verify "$scratch/state.json"
echo "Tandoor application and complete volume-loss recovery passed on $(uname -m)"
