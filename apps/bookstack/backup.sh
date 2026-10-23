#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$app_dir"
env_file="${FOSSARY_ENV_FILE:-$app_dir/.env}"
[[ -f "$env_file" ]] || { echo "Missing $env_file" >&2; exit 2; }
set -a
# shellcheck disable=SC1091
. "$env_file"
set +a
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-bookstack}" --env-file "$env_file" --file "$app_dir/compose.yaml")
backup_dir="${BOOKSTACK_BACKUP_DIR:-$app_dir/backups}"
mkdir -p "$backup_dir"
backup_dir="$(cd "$backup_dir" && pwd)"
staging="$(mktemp -d)"
stopped=false
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [[ "$stopped" == true ]]; then "${compose[@]}" start bookstack >/dev/null || true; fi
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
container_id="$("${compose[@]}" ps --all --quiet bookstack)"
[[ -n "$container_id" ]] || { echo "Start the BookStack recipe before backup" >&2; exit 1; }
volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/config"}}{{.Name}}{{end}}{{end}}' "$container_id")"
[[ -n "$volume" ]] || { echo "No named /config volume found" >&2; exit 1; }

# Stop writers so the database dump and uploaded files describe one state.
was_running="$(docker inspect --format '{{.State.Running}}' "$container_id")"
"${compose[@]}" stop bookstack
stopped="$was_running"
"${compose[@]}" exec -T database sh -c 'exec mariadb-dump --single-transaction --routines --triggers --user="$MARIADB_USER" --password="$MARIADB_PASSWORD" "$MARIADB_DATABASE"' > "$staging/database.sql"
docker run --rm -v "$volume:/source:ro" -v "$staging:/backup" alpine:3.22 tar -C /source -czf /backup/config.tar.gz .
cp -- "$env_file" "$staging/configuration.env"
cp -- "$app_dir/compose.yaml" "$staging/compose.yaml"
archive="$backup_dir/bookstack-$(date -u +%Y%m%dT%H%M%S.%NZ).tar"
tar -C "$staging" -cf "$archive" database.sql config.tar.gz configuration.env compose.yaml
echo "Backup created: $archive"
echo "The archive contains APP_KEY, database credentials, and private documents. Encrypt it and copy it off-server."
