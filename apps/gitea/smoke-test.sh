#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-gitea-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
response="$(mktemp)"
work_dir="$(mktemp -d)"
backup_dir="$(mktemp -d)"

export GITEA_HTTP_PORT=0
export GITEA_SSH_PORT=0
export GITEA_DOMAIN=localhost
export GITEA_SSH_DOMAIN=localhost
export GITEA_ROOT_URL=http://localhost/
export POSTGRES_PASSWORD="smoke-${project}"
export GITEA_DATA_VOLUME="${project}-data"
export GITEA_DB_VOLUME="${project}-database"
export GITEA_BACKUP_DIR="$backup_dir"
export COMPOSE_PROJECT_NAME="$project"

compose=(docker compose --project-name "$project" --env-file "$app_dir/.env.example" --file "$app_dir/compose.yaml")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=300
  "${compose[@]}" down --volumes --remove-orphans --timeout 60
  rm -f "$response"
  rm -rf "$work_dir" "$backup_dir"
  exit "$status"
}
trap 'echo "Smoke test failed at line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach --wait --wait-timeout 360
published="$("${compose[@]}" port gitea 3000)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac
curl --fail --silent --show-error --retry 10 --retry-all-errors --output "$response" "http://${published}/api/healthz"
grep --quiet '"status": *"pass"' "$response"

password="Smoke-${project}-password"
"${compose[@]}" exec -T --user git gitea gitea admin user create \
  --username smokeadmin --password "$password" --email smoke@example.invalid \
  --admin --must-change-password=false
curl --fail --silent --show-error --user "smokeadmin:$password" \
  --header 'Content-Type: application/json' \
  --data '{"name":"restore-check","private":true,"auto_init":true}' \
  --output "$response" "http://${published}/api/v1/user/repos"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["name"] == "restore-check"' "$response"

# A repository checks both the PostgreSQL rows and the Git objects on disk.
cp -- "$app_dir/compose.yaml" "$app_dir/backup.sh" "$app_dir/restore.sh" "$work_dir/"
{
  for variable in POSTGRES_PASSWORD GITEA_DATA_VOLUME GITEA_DB_VOLUME GITEA_BACKUP_DIR; do
    printf '%s=%s\n' "$variable" "${!variable}"
  done
} > "$work_dir/.env"
bash "$work_dir/backup.sh"
archives=("$backup_dir"/gitea-*.tar)
test -f "${archives[0]}"
test "$(stat -c %a "${archives[0]}")" = 600
"${compose[@]}" up --detach --wait --wait-timeout 360
published="$("${compose[@]}" port gitea 3000)"
curl --fail --silent --show-error --user "smokeadmin:$password" --request DELETE \
  "http://${published}/api/v1/repos/smokeadmin/restore-check"
code="$(curl --silent --output "$response" --write-out '%{http_code}' \
  --user "smokeadmin:$password" "http://${published}/api/v1/repos/smokeadmin/restore-check")"
test "$code" = 404
bash "$work_dir/restore.sh" "${archives[0]}"
published="$("${compose[@]}" port gitea 3000)"
curl --fail --silent --show-error --user "smokeadmin:$password" \
  --output "$response" "http://${published}/api/v1/repos/smokeadmin/restore-check/contents"
python3 -c 'import json,sys; assert len(json.load(open(sys.argv[1]))) > 0' "$response"

echo "Gitea repository creation, backup and restore passed on $published"
