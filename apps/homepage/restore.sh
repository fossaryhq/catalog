#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $# -eq 1 && -f "$1" ]] || { echo "Usage: $0 path/to/homepage-backup.tar" >&2; exit 2; }
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$app_dir"
env_file="${FOSSARY_ENV_FILE:-$app_dir/.env}"
[[ -f "$env_file" ]] || { echo "Missing $env_file" >&2; exit 2; }
set -a
# shellcheck disable=SC1090,SC1091
. "$env_file"
set +a
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-homepage}" --env-file "$env_file" --file "$app_dir/compose.yaml")
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
for database in settings.yaml services.yaml bookmarks.yaml widgets.yaml; do
  if ! grep -Fxq "./$database" "$staging/files" && ! grep -Fxq "$database" "$staging/files"; then echo "Missing $database" >&2; exit 1; fi
done
container="$("${compose[@]}" ps --all --quiet homepage)"
[[ -n "$container" ]] || { echo 'Start the recipe before restore' >&2; exit 1; }
volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/config"}}{{.Source}}{{end}}{{end}}' "$container")"
[[ -n "$volume" ]] || { echo 'Expected a config bind mount' >&2; exit 1; }
bash "$app_dir/backup.sh"
"${compose[@]}" stop homepage
docker run --rm -v "$volume:/data" -v "$staging:/backup:ro" alpine:3.22 \
  sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /data -xzf /backup/data.tar.gz'
"${compose[@]}" up -d --wait --wait-timeout 180
echo "Restored: $archive"
echo 'Archived configuration.env was not activated. Compare its login password, session secret, external URL, allowed hosts and application version before reuse.'
