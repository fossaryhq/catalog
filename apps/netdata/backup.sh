#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
project_directory=${NETDATA_PROJECT_DIRECTORY:-$PWD}
env_file=${NETDATA_ENV_FILE:-$project_directory/.env}
compose=(docker compose --project-directory "$project_directory" --env-file "$env_file" --file "$PWD/compose.yaml")
umask 077
mkdir -p "$project_directory/backups"
chmod 700 "$project_directory/backups"
staging=$(mktemp -d "$project_directory/backups/.netdata-XXXXXX")
running=$("${compose[@]}" ps --status running --services)
finish() {
  if [[ -n $running ]]; then
    mapfile -t services <<< "$running"
    "${compose[@]}" start "${services[@]}" >/dev/null
  fi
  rm -rf -- "$staging"
}
trap finish EXIT
"${compose[@]}" stop gateway netdata
"${compose[@]}" run --rm --no-deps --volume "$staging:/backup" --entrypoint sh netdata -ec '
  tar -C /var/lib/netdata -czf /backup/lib.tar.gz .
  tar -C /var/cache/netdata -czf /backup/cache.tar.gz .
'
cp -R "$project_directory/config" "$staging/config"
cp "$env_file" "$staging/configuration.env"
cp compose.yaml "$staging/compose.yaml"
archive="$project_directory/backups/netdata-$(date -u +%Y%m%dT%H%M%S)-$$.tar.gz"
tar -C "$staging" -czf "$archive" lib.tar.gz cache.tar.gz config configuration.env compose.yaml
chmod 600 "$archive"
printf '%s\n' "$archive"
