#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export COMPOSE_PROJECT_NAME="smoke-firefly-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$"
export FIREFLY_PORT=0 FIREFLY_URL=http://localhost:8088
export FIREFLY_APP_KEY="$(openssl rand -hex 16)" FIREFLY_CRON_TOKEN="$(openssl rand -hex 16)" FIREFLY_DB_PASSWORD="$(openssl rand -hex 24)"
scratch="$(mktemp -d)"
export FOSSARY_ENV_FILE="$scratch/.env" FIREFLY_BACKUP_DIR="$scratch/backups"
cp "$app_dir/.env.example" "$FOSSARY_ENV_FILE"
for key in FIREFLY_PORT FIREFLY_URL FIREFLY_APP_KEY FIREFLY_CRON_TOKEN FIREFLY_DB_PASSWORD FIREFLY_BACKUP_DIR; do
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
if FIREFLY_APP_KEY=replace-with-32-random-characters "${compose[@]}" run --rm --no-deps firefly; then
  echo "Placeholder key unexpectedly started the application" >&2
  exit 1
else
  [[ $? -eq 2 ]] || { echo "Expected the credential guard to exit 2" >&2; exit 1; }
fi
"${compose[@]}" up -d --wait --wait-timeout "${SMOKE_WAIT_TIMEOUT:-600}"
published="$("${compose[@]}" port firefly 8080)"
[[ "$published" =~ ^127\.0\.0\.1:[0-9]+$ ]] || { echo "Unexpected published address: $published" >&2; exit 1; }
python3 "$app_dir/smoke-api.py" "http://$published" seed "$scratch/state.json"
"${compose[@]}" exec -T cron sh -ec 'wget -qO- "http://firefly:8080/api/v1/cron/$STATIC_CRON_TOKEN"' > "$scratch/cron.json"
python3 - "$scratch/cron.json" <<'PY'
import json, sys
groups = json.load(open(sys.argv[1]))
jobs = [job for group in groups.values() for job in group]
assert jobs and all(job['job_succeeded'] and not job['job_errored'] for job in jobs), 'cron jobs must succeed'
PY
bash "$app_dir/backup.sh"
archive="$(find "$FIREFLY_BACKUP_DIR" -maxdepth 1 -name 'firefly-iii-*.tar' -print -quit)"
[[ "$(stat -c %a "$archive")" == 600 ]]
original_hash="$(sha256sum "$archive")"
"${compose[@]}" down --volumes --remove-orphans
"${compose[@]}" up -d --wait --wait-timeout 600
bash "$app_dir/restore.sh" "$archive"
[[ "$(sha256sum "$archive")" == "$original_hash" ]]
published="$("${compose[@]}" port firefly 8080)"
python3 "$app_dir/smoke-api.py" "http://$published" verify "$scratch/state.json"
echo "Firefly III application, cron and complete volume-loss recovery passed on $(uname -m)"
