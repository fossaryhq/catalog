#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export COMPOSE_PROJECT_NAME="smoke-wallabag-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$"
export WALLABAG_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
export WALLABAG_URL="http://127.0.0.1:$WALLABAG_PORT"
export WALLABAG_SECRET="$(openssl rand -hex 32)" WALLABAG_ADMIN_PASSWORD="$(openssl rand -hex 24)"
scratch="$(mktemp -d)"
export FOSSARY_ENV_FILE="$scratch/.env" WALLABAG_BACKUP_DIR="$scratch/backups"
cp "$app_dir/.env.example" "$FOSSARY_ENV_FILE"
for key in WALLABAG_PORT WALLABAG_URL WALLABAG_SECRET WALLABAG_ADMIN_PASSWORD WALLABAG_BACKUP_DIR; do
  printf '%s=%q\n' "$key" "${!key}" >> "$FOSSARY_ENV_FILE"
done
compose=(docker compose --project-name "$COMPOSE_PROJECT_NAME" --env-file "$FOSSARY_ENV_FILE" --file "$app_dir/compose.yaml")
cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=150
  "${compose[@]}" down --volumes --remove-orphans --timeout 30
  rm -rf "$scratch"
  exit "$status"
}
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM
"${compose[@]}" config --quiet
"${compose[@]}" pull --quiet
# The template password must fail before a web server can accept requests.
if WALLABAG_ADMIN_PASSWORD=replace-with-a-unique-password "${compose[@]}" up -d --wait --wait-timeout 60; then
  echo "Placeholder credentials unexpectedly started the application" >&2
  exit 1
fi
initialize_id="$("${compose[@]}" ps --all --quiet initialize)"
[[ "$(docker inspect --format '{{.State.ExitCode}}' "$initialize_id")" == 2 ]]
[[ -z "$("${compose[@]}" ps --status running --quiet wallabag)" ]]
"${compose[@]}" up -d --wait --wait-timeout "${SMOKE_WAIT_TIMEOUT:-600}"
python3 "$app_dir/smoke-api.py" "$WALLABAG_URL" seed "$scratch/state.json"
# Data in the image volume must survive along with SQLite.
"${compose[@]}" exec -T wallabag sh -c 'printf saved-image-recovery > /var/www/wallabag/web/assets/images/fossary-recovery.txt'
bash "$app_dir/backup.sh"
archive="$(find "$WALLABAG_BACKUP_DIR" -maxdepth 1 -name 'wallabag-*.tar' -print -quit)"
[[ "$(stat -c %a "$archive")" == 600 ]]
original_hash="$(sha256sum "$archive")"
"${compose[@]}" down --volumes --remove-orphans
"${compose[@]}" up -d --wait --wait-timeout 600
bash "$app_dir/restore.sh" "$archive"
[[ "$(sha256sum "$archive")" == "$original_hash" ]]
python3 "$app_dir/smoke-api.py" "$WALLABAG_URL" verify "$scratch/state.json"
[[ "$("${compose[@]}" exec -T wallabag cat /var/www/wallabag/web/assets/images/fossary-recovery.txt)" == saved-image-recovery ]]
echo "Wallabag application, secure initialization and volume-loss recovery passed on $(uname -m)"
