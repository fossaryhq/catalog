#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-stirling-pdf-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
response="$(mktemp)"
data_path="$(mktemp -d)"
work_dir="$(mktemp -d)"
backup_dir="$(mktemp -d)"

export STIRLING_PDF_PORT=0
export STIRLING_PDF_URL=http://localhost:8080
export STIRLING_PDF_DATA_PATH="$data_path"
export STIRLING_PDF_INITIAL_USERNAME=smoke-admin
export STIRLING_PDF_INITIAL_PASSWORD="smoke-${project}-password"
export STIRLING_PDF_BACKUP_DIR="$backup_dir"
export COMPOSE_PROJECT_NAME="$project"

compose=(docker compose --project-name "$project" --env-file "$app_dir/.env.example" --file "$app_dir/compose.yaml")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=300
  "${compose[@]}" down --volumes --remove-orphans --timeout 60
  docker run --rm -v "${data_path}:/data" alpine:3.22 sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +'
  rm -rf "$response" "$data_path" "$work_dir" "$backup_dir"
  exit "$status"
}
# Every failed check names itself: `grep --quiet` and `test` say nothing, and all
# the CI log would keep of them is an exit code.
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach --wait --wait-timeout "${SMOKE_WAIT_TIMEOUT:-600}"
published="$("${compose[@]}" port stirling-pdf 8080)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac
curl --fail --silent --show-error \
  --retry 20 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 30 \
  --output "$response" "http://${published}/api/v1/info/status"
grep --fixed-strings --quiet '"status":"UP"' "$response"

check_login() {
  curl --fail --silent --show-error --header 'Content-Type: application/json' \
    --data "{\"username\":\"$STIRLING_PDF_INITIAL_USERNAME\",\"password\":\"$STIRLING_PDF_INITIAL_PASSWORD\"}" \
    --output "$response" "http://${published}/api/v1/auth/login"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["user"]["username"] == "smoke-admin"; assert d["session"]["access_token"]' "$response"
}
check_login

cp -- "$app_dir/compose.yaml" "$app_dir/backup.sh" "$app_dir/restore.sh" "$work_dir/"
{
  printf 'STIRLING_PDF_DATA_PATH=%s\n' "$data_path"
  printf 'STIRLING_PDF_BACKUP_DIR=%s\n' "$backup_dir"
} > "$work_dir/.env"
"${compose[@]}" exec -T stirling-pdf sh -c 'for path in /configs /customFiles /pipeline /usr/share/tessdata; do printf "fossary restore check\n" > "$path/fossary-restore-check"; done'
bash "$work_dir/backup.sh"
archives=("$backup_dir"/stirling-pdf-*.tar.gz)
test -f "${archives[0]}"
test "$(stat -c %a "${archives[0]}")" = 600
"${compose[@]}" up --detach --wait --wait-timeout "${SMOKE_WAIT_TIMEOUT:-600}"
"${compose[@]}" exec -T stirling-pdf sh -c 'for path in /configs /customFiles /pipeline /usr/share/tessdata; do rm "$path/fossary-restore-check"; done'
bash "$work_dir/restore.sh" "${archives[0]}"
published="$("${compose[@]}" port stirling-pdf 8080)"
for directory in configs customFiles pipeline tessdata; do
  grep --fixed-strings --line-regexp --quiet 'fossary restore check' "$data_path/$directory/fossary-restore-check"
done
curl --fail --silent --show-error --output "$response" "http://${published}/api/v1/info/status"
grep --fixed-strings --quiet '"status":"UP"' "$response"
check_login

echo "Stirling PDF health, four data directories, backup and restore passed on $published"
