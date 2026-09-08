#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-actual-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
backup_dir="$(mktemp -d)"

export ACTUAL_PORT=0
export ACTUAL_DATA_VOLUME="${project}-data"
export COMPOSE_PROJECT_NAME="$project"
export ACTUAL_BACKUP_DIR="$backup_dir"
export FOSSARY_ENV_FILE=/dev/null

compose=(docker compose --project-name "$project" --env-file "$app_dir/.env.example" --file "$app_dir/compose.yaml")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=300
  "${compose[@]}" down --volumes --remove-orphans --timeout 60
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
"${compose[@]}" up --detach --wait --wait-timeout 600
published="$("${compose[@]}" port actual 5006)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac

# The same probe the container health check runs, from the outside.
curl --fail --silent --show-error \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  "http://${published}/health" | grep --quiet '"status":"UP"'

# A fresh server reports that no password has been set yet; that answer proves
# the API and its SQLite store came up, not just the static frontend.
curl --fail --silent --show-error \
  --connect-timeout 3 --max-time 30 \
  "http://${published}/account/needs-bootstrap" | grep --quiet '"bootstrapped":false'

# Restore must bring back data from the persistent SQLite volume.
container_id="$("${compose[@]}" ps --quiet actual)"
docker exec "$container_id" touch /data/fossary-restore-check
bash "$app_dir/backup.sh"
archives=("$backup_dir"/actual-budget-*.tar)
test -f "${archives[0]}"
docker exec "$container_id" rm /data/fossary-restore-check
bash "$app_dir/restore.sh" "${archives[0]}"
container_id="$("${compose[@]}" ps --quiet actual)"
docker exec "$container_id" test -f /data/fossary-restore-check

echo "Actual Budget smoke test passed on $published"
