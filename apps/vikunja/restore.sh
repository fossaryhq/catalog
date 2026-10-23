#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/vikunja-backup.tar" >&2
  exit 2
fi
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$app_dir"
env_file="${FOSSARY_ENV_FILE:-$app_dir/.env}"
[[ -f "$env_file" ]] || { echo "Missing $env_file" >&2; exit 2; }
set -a
# shellcheck disable=SC1091
. "$env_file"
set +a
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-vikunja}" --env-file "$env_file" --file "$app_dir/compose.yaml")
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

# Validate the complete payload before stopping or replacing the current installation.
tar -C "$staging" -xf "$archive" database.sql data.tar.gz configuration.env compose.yaml
for file in database.sql data.tar.gz configuration.env compose.yaml; do
  [[ -s "$staging/$file" && ! -L "$staging/$file" ]] || { echo "Invalid backup member: $file" >&2; exit 1; }
done
gzip -t "$staging/data.tar.gz"
tar -tzf "$staging/data.tar.gz" > "$staging/data-files"
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$staging/data-files"; then
  echo "Unsafe data archive paths" >&2
  exit 1
fi
container_id="$("${compose[@]}" ps --all --quiet vikunja)"
[[ -n "$container_id" ]] || { echo "Start the Vikunja recipe before restore" >&2; exit 1; }
volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' "$container_id")"
[[ -n "$volume" ]] || { echo "No named /data volume found" >&2; exit 1; }
bash "$app_dir/backup.sh"
"${compose[@]}" stop vikunja
"${compose[@]}" up -d --wait --wait-timeout 300 database
"${compose[@]}" exec -T database sh -c 'exec psql --quiet --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --set=ON_ERROR_STOP=1 --command="DROP SCHEMA public CASCADE; CREATE SCHEMA public AUTHORIZATION vikunja;"'
"${compose[@]}" exec -T database sh -c 'exec psql --quiet --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --set=ON_ERROR_STOP=1' < "$staging/database.sql"
docker run --rm -v "$volume:/target" -v "$staging/data.tar.gz:/backup.tar.gz:ro" alpine:3.22 \
  sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /backup.tar.gz'
"${compose[@]}" up -d --wait --wait-timeout 300 vikunja
echo "Backup restored from: $archive"
echo "Archived configuration.env was not activated. Preserve its service secret and use matching application/database versions; compare it with the active .env."
