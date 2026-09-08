#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-nextcloud-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
html_volume="${NEXTCLOUD_HTML_VOLUME:-${project}-html}"
db_volume="${NEXTCLOUD_DB_VOLUME:-${project}-database}"
response="$(mktemp)"
backup_dir="$(mktemp -d)"
data_root="$(mktemp -d)"
data_location="$data_root/data"
mkdir "$data_location"

# The data directory belongs to www-data inside the container.
docker run --rm -v "${data_location}:/d" alpine:3.22 chown -R 33:33 /d

export NEXTCLOUD_PORT=0
export NEXTCLOUD_DATA_LOCATION="$data_location"
export NEXTCLOUD_HTML_VOLUME="$html_volume"
export NEXTCLOUD_DB_VOLUME="$db_volume"
export NEXTCLOUD_DB_NAME=nextcloud
export NEXTCLOUD_DB_USER=nextcloud
db_password="smoke$(date +%s)"
export NEXTCLOUD_DB_PASSWORD="$db_password"
export NEXTCLOUD_ADMIN_USER=admin
admin_password="smoke-$(date +%s)-admin"
export NEXTCLOUD_ADMIN_PASSWORD="$admin_password"
export NEXTCLOUD_TRUSTED_DOMAINS="localhost 127.0.0.1"
export NEXTCLOUD_TRUSTED_PROXIES=
export NEXTCLOUD_OVERWRITE_PROTOCOL=
export NEXTCLOUD_OVERWRITE_CLI_URL=
export NEXTCLOUD_PHP_MEMORY_LIMIT=512M
export NEXTCLOUD_PHP_UPLOAD_LIMIT=1G
export TZ=UTC
export COMPOSE_PROJECT_NAME="$project"
export NEXTCLOUD_BACKUP_DIR="$backup_dir"

compose=(
  docker compose
  --project-name "$project"
  --env-file "$app_dir/.env.example"
  --file "$app_dir/compose.yaml"
)

occ() {
  "${compose[@]}" exec -T -u www-data app php occ "$@"
}

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=200
  "${compose[@]}" down --volumes --remove-orphans --timeout 60
  docker volume rm --force "$html_volume" "$db_volume" >/dev/null 2>&1
  docker run --rm -v "${data_root}:/target" alpine:3.22 \
    sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +' >/dev/null 2>&1
  rm -f "$response"
  rm -rf "$backup_dir" "$data_root"
  exit "$status"
}
# Every failed check names itself: `grep --quiet` and `test` say nothing, and all
# the CI log would keep of them is an exit code.
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach --wait --wait-timeout 900

for service in app database redis; do
  container_id="$("${compose[@]}" ps --quiet "$service")"
  test -n "$container_id"
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container_id")"
  test "$health" = healthy
done

published="$("${compose[@]}" port app 80)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac

curl --fail --silent --show-error --location \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/status.php"
python3 -c 'import json,sys
d = json.load(open(sys.argv[1]))
assert d["installed"] is True, d
assert d["maintenance"] is False, d
assert d["versionstring"] == "34.0.3", d' "$response"

# Background jobs run in their own container rather than in AJAX mode. The mode
# is recorded on the first cron.php run, which the cron container does every five
# minutes; here we run it once so the test does not have to wait.
"${compose[@]}" exec -T -u www-data app php -f /var/www/html/cron.php
test "$(occ config:app:get core backgroundjobs_mode | tr -d '\r\n')" = cron

# Redis file locking is required for clients working in parallel.
occ config:system:get memcache.locking | grep --fixed-strings --quiet 'Redis'

# Verify that backup and restore bring the database contents back.
"${compose[@]}" exec -T -u www-data -e OC_PASS="smoke-$(date +%s)-user" app \
  php occ user:add --password-from-env --display-name="Smoke" smoke >/dev/null
occ user:list | grep --fixed-strings --quiet 'smoke'

bash "$app_dir/backup.sh"
archives=("$backup_dir"/nextcloud-*.tar)
test -f "${archives[0]}"
occ user:delete smoke >/dev/null
if occ user:list | grep --fixed-strings --quiet 'smoke:'; then
  echo "User should have been deleted before restore" >&2
  exit 1
fi

bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout 900

occ user:list | grep --fixed-strings --quiet 'smoke'
published="$("${compose[@]}" port app 80)"
curl --fail --silent --show-error --location \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/status.php"
python3 -c 'import json,sys
d = json.load(open(sys.argv[1]))
assert d["installed"] is True and d["maintenance"] is False, d' "$response"

echo "Nextcloud smoke test passed on $published"
