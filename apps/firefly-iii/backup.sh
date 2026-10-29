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
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-firefly-iii}" --env-file "$env_file" --file "$app_dir/compose.yaml")
id="$("${compose[@]}" ps --all --quiet firefly)"
[[ -n "$id" ]] || { echo "Create the Firefly III containers before backup" >&2; exit 1; }
volumes=()
for mount in /var/www/html/storage /var/www/html/storage/upload; do
  volume="$(docker inspect --format "{{range .Mounts}}{{if eq .Destination \"$mount\"}}{{.Name}}{{end}}{{end}}" "$id")"
  [[ -n "$volume" ]] || { echo "Missing named volume at $mount" >&2; exit 1; }
  volumes+=("$volume")
done
backup_dir="${FIREFLY_BACKUP_DIR:-$app_dir/backups}"
mkdir -p "$backup_dir"
backup_dir="$(cd "$backup_dir" && pwd)"
staging="$(mktemp -d)"
mapfile -t running < <("${compose[@]}" ps --status running --services firefly cron)
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [[ ${#running[@]} -gt 0 ]]; then "${compose[@]}" start "${running[@]}" >/dev/null || status=1; fi
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
"${compose[@]}" stop cron firefly
"${compose[@]}" exec -T database pg_dump --username=firefly --dbname=firefly --no-owner --no-privileges | gzip > "$staging/database.sql.gz"
for index in 0 1; do
  docker run --rm -v "${volumes[$index]}:/source:ro" -v "$staging:/backup" alpine:3.22.2 tar -C /source -czf "/backup/volume-$index.tar.gz" .
done
cp -- "$env_file" "$staging/configuration.env"
cp -- compose.yaml "$staging/compose.yaml"
archive="$backup_dir/firefly-iii-$(date -u +%Y%m%dT%H%M%S.%NZ).tar"
tar -C "$staging" -cf "$archive" database.sql.gz volume-0.tar.gz volume-1.tar.gz configuration.env compose.yaml
echo "Backup created: $archive"
echo "Contains financial records, accounts, attachments, OAuth signing keys and deployment secrets. Encrypt it and copy it off-server."
