#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} != -y || $# != 2 ]]; then
  printf 'Usage: %s -y backup.tar.gz (replaces Netdata identity and metric history)\n' "$0" >&2
  exit 2
fi
archive=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
[[ -f $archive ]] || { printf 'Archive not found\n' >&2; exit 1; }
cd "$(dirname "${BASH_SOURCE[0]}")"
project_directory=${NETDATA_PROJECT_DIRECTORY:-$PWD}
env_file=${NETDATA_ENV_FILE:-$project_directory/.env}
compose=(docker compose --project-directory "$project_directory" --env-file "$env_file" --file "$PWD/compose.yaml")
umask 077
staging=$(mktemp -d "$project_directory/.restore-netdata-XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
for file in lib.tar.gz cache.tar.gz; do
  tar -xOf "$archive" "$file" > "$staging/$file"
  [[ -s $staging/$file ]] || { printf 'Missing archive member: %s\n' "$file" >&2; exit 1; }
  gzip -t "$staging/$file"
  tar -tzf "$staging/$file" > "$staging/paths"
  if grep -Eq '(^/|(^|/)\.\.(/|$))' "$staging/paths"; then
    printf 'Unsafe archive paths\n' >&2; exit 1
  fi
  tar -tvzf "$staging/$file" > "$staging/entries"
  if grep -Eq '^[lh]' "$staging/entries"; then
    printf 'Links are not accepted in metric archives\n' >&2; exit 1
  fi
done
for file in config/netdata.conf config/Caddyfile configuration.env compose.yaml; do
  tar -xOf "$archive" "$file" > "$staging/$(basename "$file")"
  [[ -s $staging/$(basename "$file") ]] || { printf 'Missing configuration: %s\n' "$file" >&2; exit 1; }
done
# Configuration is archived for review, never activated by a data restore.
bash ./backup.sh
"${compose[@]}" stop gateway netdata
"${compose[@]}" run --rm --no-deps --volume "$staging:/backup:ro" --entrypoint sh netdata -ec '
  for directory in /var/lib/netdata /var/cache/netdata; do
    find "$directory" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  done
  tar -C /var/lib/netdata -xzf /backup/lib.tar.gz
  tar -C /var/cache/netdata -xzf /backup/cache.tar.gz
'
"${compose[@]}" up -d --wait --wait-timeout 300
printf 'Restored Netdata identity and metrics. Current config, password hash and image versions were retained.\n'
