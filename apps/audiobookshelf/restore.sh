#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $# -eq 1 && -f "$1" ]] || { echo "Usage: $0 path/to/audiobookshelf-backup.tar" >&2; exit 2; }
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$app_dir"
env_file="${FOSSARY_ENV_FILE:-$app_dir/.env}"
[[ -f "$env_file" ]] || { echo "Missing $env_file" >&2; exit 2; }
set -a
# shellcheck disable=SC1090,SC1091
. "$env_file"
set +a
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-audiobookshelf}" --env-file "$env_file" --file "$app_dir/compose.yaml")
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
# Reject an incomplete or unsafe payload before changing the current installation.
tar -C "$staging" -xf "$archive" data.tar.gz configuration.env compose.yaml
for file in data.tar.gz configuration.env compose.yaml; do
  [[ -f "$staging/$file" && -s "$staging/$file" && ! -L "$staging/$file" ]] || { echo "Invalid backup member: $file" >&2; exit 1; }
done
gzip -t "$staging/data.tar.gz"
tar -tzf "$staging/data.tar.gz" > "$staging/files"
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$staging/files"; then echo 'Unsafe archive paths' >&2; exit 1; fi
for database in config/absdatabase.sqlite metadata/ audiobooks/ podcasts/; do
  if ! grep -Fxq "./$database" "$staging/files" && ! grep -Fxq "$database" "$staging/files"; then echo "Missing $database" >&2; exit 1; fi
done
container="$("${compose[@]}" ps --all --quiet audiobookshelf)"
[[ -n "$container" ]] || { echo 'Start the recipe before restore' >&2; exit 1; }
volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' "$container")"
[[ -n "$volume" ]] || { echo 'Expected a named data volume' >&2; exit 1; }
bash "$app_dir/backup.sh"
"${compose[@]}" stop audiobookshelf
docker run --rm -v "$volume:/data" -v "$staging:/backup:ro" alpine:3.22 \
  sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /data -xzf /backup/data.tar.gz'
"${compose[@]}" up -d --wait --wait-timeout 180
echo "Restored: $archive"
echo 'Archived configuration.env was not activated. Match the saved version. Restored account credentials are authoritative; bootstrap does not rotate them. Verify actual media files as well as the database.'
