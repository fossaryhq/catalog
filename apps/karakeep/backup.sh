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
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-karakeep}" --env-file "$env_file" --file "$app_dir/compose.yaml")
backup_dir="${KARAKEEP_BACKUP_DIR:-$app_dir/backups}"
mkdir -p "$backup_dir"
backup_dir="$(cd "$backup_dir" && pwd)"
staging="$(mktemp -d)"
restart=()
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if (( ${#restart[@]} )); then "${compose[@]}" start "${restart[@]}" >/dev/null || status=1; fi
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
# Record and validate both mounts before stopping any writers.
volumes=()
for spec in karakeep:/data meilisearch:/meili_data; do
  service="${spec%%:*}"
  mount="${spec#*:}"
  id="$("${compose[@]}" ps --all --quiet "$service")"
  [[ -n "$id" ]] || { echo "Create the Karakeep containers before backup" >&2; exit 1; }
  volume="$(docker inspect --format "{{range .Mounts}}{{if eq .Destination \"$mount\"}}{{.Name}}{{end}}{{end}}" "$id")"
  [[ -n "$volume" ]] || { echo "Missing named volume at $mount" >&2; exit 1; }
  volumes+=("$volume")
  if [[ "$(docker inspect --format '{{.State.Running}}' "$id")" == true ]]; then restart+=("$service"); fi
done
"${compose[@]}" stop karakeep meilisearch
for index in 0 1; do
  docker run --rm -v "${volumes[$index]}:/source:ro" -v "$staging:/backup" alpine:3.22.2 tar -C /source -czf "/backup/volume-$index.tar.gz" .
done
cp -- "$env_file" "$staging/configuration.env"
cp -- compose.yaml "$staging/compose.yaml"
archive="$backup_dir/karakeep-$(date -u +%Y%m%dT%H%M%S.%NZ).tar"
tar -C "$staging" -cf "$archive" volume-0.tar.gz volume-1.tar.gz configuration.env compose.yaml
echo "Backup created: $archive"
echo "Contains private bookmarks, SQLite, assets, search data and secrets. Encrypt it and copy it off-server."
