#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $# -eq 1 && -f "$1" ]] || { echo "Usage: $0 path/to/tandoor-backup.tar" >&2; exit 2; }
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$app_dir"
env_file="${FOSSARY_ENV_FILE:-$app_dir/.env}"
[[ -f "$env_file" ]] || { echo "Missing $env_file" >&2; exit 2; }
set -a
# shellcheck disable=SC1090
. "$env_file"
set +a
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-tandoor}" --env-file "$env_file" --file "$app_dir/compose.yaml")
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
tar -C "$staging" -xf "$archive" database.sql.gz volume-0.tar.gz configuration.env compose.yaml
for file in database.sql.gz volume-0.tar.gz configuration.env compose.yaml; do
  [[ -s "$staging/$file" && ! -L "$staging/$file" ]] || { echo "Invalid backup member: $file" >&2; exit 1; }
done
gzip -t "$staging/database.sql.gz"
for index in 0; do
  gzip -t "$staging/volume-$index.tar.gz"
  tar -tzf "$staging/volume-$index.tar.gz" > "$staging/paths"
  if grep -Eq '(^/|(^|/)\.\.(/|$))' "$staging/paths"; then echo "Unsafe archive path" >&2; exit 1; fi
done
volumes=()
id="$("${compose[@]}" ps --all --quiet tandoor)"
[[ -n "$id" ]] || { echo "Create the Tandoor containers before restore" >&2; exit 1; }
for mount in /opt/recipes/mediafiles; do
  volume="$(docker inspect --format "{{range .Mounts}}{{if eq .Destination \"$mount\"}}{{.Name}}{{end}}{{end}}" "$id")"
  [[ -n "$volume" ]] || { echo "Missing named volume at $mount" >&2; exit 1; }
  volumes+=("$volume")
done
bash "$app_dir/backup.sh"
"${compose[@]}" stop tandoor
"${compose[@]}" exec -T database dropdb --username=tandoor --if-exists --force tandoor
"${compose[@]}" exec -T database createdb --username=tandoor --owner=tandoor tandoor
gzip -dc "$staging/database.sql.gz" | "${compose[@]}" exec -T database psql --username=tandoor --dbname=tandoor --set ON_ERROR_STOP=1 >/dev/null
for index in 0; do
  docker run --rm -v "${volumes[$index]}:/target" -v "$staging/volume-$index.tar.gz:/backup.tar.gz:ro" alpine:3.22.2 \
    sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /backup.tar.gz'
done
"${compose[@]}" up -d --wait --wait-timeout 600
echo "Restored: $archive"
echo "Archived configuration.env was not activated. Use the matching application version and SECRET_KEY; verify recipes and images before reopening access."
