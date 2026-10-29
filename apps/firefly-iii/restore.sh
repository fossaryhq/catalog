#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $# -eq 1 && -f "$1" ]] || { echo "Usage: $0 path/to/firefly-iii-backup.tar" >&2; exit 2; }
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$app_dir"
env_file="${FOSSARY_ENV_FILE:-$app_dir/.env}"
[[ -f "$env_file" ]] || { echo "Missing $env_file" >&2; exit 2; }
set -a
# shellcheck disable=SC1090
. "$env_file"
set +a
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-firefly-iii}" --env-file "$env_file" --file "$app_dir/compose.yaml")
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
tar -C "$staging" -xf "$archive" database.sql.gz volume-0.tar.gz volume-1.tar.gz configuration.env compose.yaml
for file in database.sql.gz volume-0.tar.gz volume-1.tar.gz configuration.env compose.yaml; do
  [[ -s "$staging/$file" && ! -L "$staging/$file" ]] || { echo "Invalid backup member: $file" >&2; exit 1; }
done
gzip -t "$staging/database.sql.gz"
for index in 0 1; do
  gzip -t "$staging/volume-$index.tar.gz"
  tar -tzf "$staging/volume-$index.tar.gz" > "$staging/paths"
  if grep -Eq '(^/|(^|/)\.\.(/|$))' "$staging/paths"; then echo "Unsafe archive path" >&2; exit 1; fi
done
volumes=()
id="$("${compose[@]}" ps --all --quiet firefly)"
[[ -n "$id" ]] || { echo "Create the Firefly III containers before restore" >&2; exit 1; }
for mount in /var/www/html/storage /var/www/html/storage/upload; do
  volume="$(docker inspect --format "{{range .Mounts}}{{if eq .Destination \"$mount\"}}{{.Name}}{{end}}{{end}}" "$id")"
  [[ -n "$volume" ]] || { echo "Missing named volume at $mount" >&2; exit 1; }
  volumes+=("$volume")
done
bash "$app_dir/backup.sh"
"${compose[@]}" stop cron firefly
"${compose[@]}" exec -T database dropdb --username=firefly --if-exists --force firefly
"${compose[@]}" exec -T database createdb --username=firefly --owner=firefly firefly
gzip -dc "$staging/database.sql.gz" | "${compose[@]}" exec -T database psql --username=firefly --dbname=firefly --set ON_ERROR_STOP=1 >/dev/null
for index in 0 1; do
  docker run --rm -v "${volumes[$index]}:/target" -v "$staging/volume-$index.tar.gz:/backup.tar.gz:ro" alpine:3.22.2 \
    sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /backup.tar.gz'
done
"${compose[@]}" up -d --wait --wait-timeout 600
echo "Restored: $archive"
echo "Archived configuration.env was not activated. Use the matching application version and APP_KEY; verify records and attachments before reopening access."
