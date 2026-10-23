#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/bookstack-backup.tar" >&2
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
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-bookstack}" --env-file "$env_file" --file "$app_dir/compose.yaml")
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

# Validate the complete payload before stopping or replacing the current installation.
tar -C "$staging" -xf "$archive" database.sql config.tar.gz configuration.env compose.yaml
for file in database.sql config.tar.gz configuration.env compose.yaml; do
  [[ -s "$staging/$file" && ! -L "$staging/$file" ]] || { echo "Invalid backup member: $file" >&2; exit 1; }
done
gzip -t "$staging/config.tar.gz"
tar -tzf "$staging/config.tar.gz" > "$staging/config-files"
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$staging/config-files"; then
  echo "Unsafe configuration archive paths" >&2
  exit 1
fi
container_id="$("${compose[@]}" ps --all --quiet bookstack)"
[[ -n "$container_id" ]] || { echo "Start the BookStack recipe before restore" >&2; exit 1; }
volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/config"}}{{.Name}}{{end}}{{end}}' "$container_id")"
[[ -n "$volume" ]] || { echo "No named /config volume found" >&2; exit 1; }
bash "$app_dir/backup.sh"
"${compose[@]}" stop bookstack
"${compose[@]}" up -d --wait --wait-timeout 300 database
"${compose[@]}" exec -T database sh -c 'exec mariadb --user=root --password="$MARIADB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS bookstack; CREATE DATABASE bookstack CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"'
"${compose[@]}" exec -T database sh -c 'exec mariadb --user="$MARIADB_USER" --password="$MARIADB_PASSWORD" "$MARIADB_DATABASE"' < "$staging/database.sql"
docker run --rm -v "$volume:/target" -v "$staging/config.tar.gz:/backup.tar.gz:ro" alpine:3.22 \
  sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /backup.tar.gz'
"${compose[@]}" up -d --wait --wait-timeout 300 bookstack
echo "Backup restored from: $archive"
echo "Archived configuration.env was not activated. Preserve its APP_KEY and use matching application/database versions; compare it with the active .env."
