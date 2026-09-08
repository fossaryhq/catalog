#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-seafile-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
secret="${project//[^A-Za-z0-9]/}"
backup_dir="$(mktemp -d)"

export SEAFILE_PORT=0
# The setup script rejects "localhost" as a hostname, so the smoke run uses a
# domain-shaped name and reaches the container through the published port.
export SEAFILE_SERVER_HOSTNAME=seafile.smoke.example
export SEAFILE_SERVER_PROTOCOL=http
export SEAFILE_ADMIN_EMAIL=smoke@example.com
export SEAFILE_ADMIN_PASSWORD="SmokeAdmin${secret}"
export SEAFILE_DB_ROOT_PASSWORD="SmokeRoot${secret}"
export SEAFILE_DB_USER=smoke_seafile
export SEAFILE_DB_PASSWORD="SmokeSeafile${secret}"
export SEAFILE_JWT_PRIVATE_KEY="SmokeJwtPrivateKey${secret}0123456789abcdef"
export SEAFILE_CACHE_PASSWORD="SmokeCache${secret}"
export SEAFILE_DATA_VOLUME="${project}-data"
export SEAFILE_DB_VOLUME="${project}-database"
export COMPOSE_PROJECT_NAME="$project"
export SEAFILE_BACKUP_DIR="$backup_dir"
export FOSSARY_ENV_FILE=/dev/null

compose=(docker compose --project-name "$project" --env-file "$app_dir/.env.example" --file "$app_dir/compose.yaml")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=300
  "${compose[@]}" down --volumes --remove-orphans --timeout 120
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
# The first start creates three databases and runs the Seahub setup, which takes
# minutes rather than seconds.
"${compose[@]}" up --detach --wait --wait-timeout 900
published="$("${compose[@]}" port seafile 80)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac

# The login page proves Seahub, the database, and the cache all answer.
curl --fail --silent --show-error \
  --retry 20 --retry-all-errors --retry-delay 5 \
  --connect-timeout 3 --max-time 60 \
  "http://${published}/accounts/login/" | grep --quiet "Seafile"

# The file server is a separate Go process behind the same nginx; a 400 without
# a token is the expected answer and proves it is running.
status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 3 --max-time 30 "http://${published}/seafhttp/")"
case "$status" in
  400|401|403|404) ;;
  *) echo "Unexpected /seafhttp/ status: $status" >&2; exit 1 ;;
esac

# Restore must preserve both the file block volume and the MariaDB databases.
container_id="$("${compose[@]}" ps --quiet seafile)"
docker exec "$container_id" touch /shared/fossary-restore-check
"${compose[@]}" exec -T db mariadb --user=root --password="${SEAFILE_DB_ROOT_PASSWORD}" \
  --execute='CREATE TABLE ccnet_db.fossary_restore_check (id integer);'
bash "$app_dir/backup.sh"
archives=("$backup_dir"/seafile-*.tar)
test -f "${archives[0]}"
docker exec "$container_id" rm /shared/fossary-restore-check
"${compose[@]}" exec -T db mariadb --user=root --password="${SEAFILE_DB_ROOT_PASSWORD}" \
  --execute='DROP TABLE ccnet_db.fossary_restore_check;'
bash "$app_dir/restore.sh" "${archives[0]}"
container_id="$("${compose[@]}" ps --quiet seafile)"
docker exec "$container_id" test -f /shared/fossary-restore-check
"${compose[@]}" exec -T db mariadb --user=root --password="${SEAFILE_DB_ROOT_PASSWORD}" \
  --batch --skip-column-names --execute="SHOW TABLES FROM ccnet_db LIKE 'fossary_restore_check';" | \
  grep --fixed-strings --line-regexp --quiet fossary_restore_check

echo "Seafile smoke test passed on $published"
