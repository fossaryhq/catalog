#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$app_dir"
env_file="${FOSSARY_ENV_FILE:-$app_dir/.env}"
[[ -f "$env_file" ]] || { echo "Missing $env_file" >&2; exit 2; }
set -a
# shellcheck disable=SC1090
. "$env_file"
set +a
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-tandoor}" --env-file "$env_file" --file "$app_dir/compose.yaml")
[[ -z "$("${compose[@]}" ps --status running --quiet initialize)" ]] || { echo "Wait for initialization before backup" >&2; exit 1; }
id="$("${compose[@]}" ps --all --quiet tandoor)"
[[ -n "$id" ]] || { echo "Create the Tandoor containers before backup" >&2; exit 1; }
volumes=()
for mount in /opt/recipes/mediafiles; do
  volume="$(docker inspect --format "{{range .Mounts}}{{if eq .Destination \"$mount\"}}{{.Name}}{{end}}{{end}}" "$id")"
  [[ -n "$volume" ]] || { echo "Missing named volume at $mount" >&2; exit 1; }
  volumes+=("$volume")
done
backup_dir="${TANDOOR_BACKUP_DIR:-$app_dir/backups}"
mkdir -p "$backup_dir"
backup_dir="$(cd "$backup_dir" && pwd)"
staging="$(mktemp -d)"
mapfile -t running < <("${compose[@]}" ps --status running --services tandoor)
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [[ ${#running[@]} -gt 0 ]]; then "${compose[@]}" start "${running[@]}" >/dev/null || status=1; fi
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
"${compose[@]}" stop tandoor
"${compose[@]}" exec -T database pg_dump --username=tandoor --dbname=tandoor --no-owner --no-privileges | gzip > "$staging/database.sql.gz"
for index in 0; do
  docker run --rm -v "${volumes[$index]}:/source:ro" -v "$staging:/backup" alpine:3.22.2 tar -C /source -czf "/backup/volume-$index.tar.gz" .
done
cp -- "$env_file" "$staging/configuration.env"
cp -- compose.yaml "$staging/compose.yaml"
archive="$backup_dir/tandoor-$(date -u +%Y%m%dT%H%M%S.%NZ).tar"
tar -C "$staging" -cf "$archive" database.sql.gz volume-0.tar.gz configuration.env compose.yaml
echo "Backup created: $archive"
echo "Contains recipes, accounts, meal plans, shopping lists, images and deployment secrets. Encrypt it and copy it off-server."
