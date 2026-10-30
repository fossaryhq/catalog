#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
runtime=$(mktemp -d "$PWD/.smoke-netdata-XXXXXX")
project="smoke-netdata-${GITHUB_RUN_ID:-local}-$$"
compose=(docker compose --project-name "$project" --project-directory "$runtime" --env-file "$runtime/.env" --file "$PWD/compose.yaml")
cleanup() {
  status=$?
  "${compose[@]}" logs --no-color --tail 50 || true
  "${compose[@]}" down --volumes --remove-orphans --timeout 60 || true
  rm -rf -- "$runtime"
  exit "$status"
}
trap cleanup EXIT
umask 077
cp -R config "$runtime/config"
chmod 644 "$runtime/config/Caddyfile" "$runtime/config/netdata.conf"
export NETDATA_TEST_USER=recipe-check
NETDATA_TEST_PASSWORD=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
export NETDATA_TEST_PASSWORD
hash=$(docker run --rm --entrypoint caddy caddy:2.11.7-alpine hash-password --plaintext "$NETDATA_TEST_PASSWORD")
printf "NETDATA_VERSION=2.12.2\nNETDATA_PORT=0\nNETDATA_HOSTNAME=recipe-monitor\nNETDATA_AUTH_USER=%s\nNETDATA_AUTH_HASH='%s'\nTZ=Etc/UTC\n" "$NETDATA_TEST_USER" "$hash" > "$runtime/.env"
export NETDATA_PROJECT_DIRECTORY="$runtime" NETDATA_ENV_FILE="$runtime/.env" COMPOSE_PROJECT_NAME="$project"
"${compose[@]}" config --quiet
"${compose[@]}" pull --quiet
"${compose[@]}" up -d --wait --wait-timeout 300
port=$("${compose[@]}" port gateway 8080)
base="http://$port"
NETDATA_TEST_CORES=$("${compose[@]}" exec -T netdata sh -c 'grep -c "^processor" /host/proc/cpuinfo')
export NETDATA_TEST_CORES
python3 smoke-api.py "$base" "$runtime/state.json" record
key_before=$("${compose[@]}" exec -T netdata sha256sum /var/lib/netdata/netdata.api.key)
bash ./backup.sh
archive=$(find "$runtime/backups" -maxdepth 1 -name 'netdata-*.tar.gz' -type f | sort | tail -1)
[[ $(stat -c %a "$archive") == 600 ]]
digest_before=$(sha256sum "$archive")
"${compose[@]}" down --volumes --remove-orphans --timeout 60
"${compose[@]}" create --no-build netdata
bash ./restore.sh -y "$archive"
port=$("${compose[@]}" port gateway 8080)
python3 smoke-api.py "http://$port" "$runtime/state.json" verify
[[ $("${compose[@]}" exec -T netdata sha256sum /var/lib/netdata/netdata.api.key) == "$key_before" ]]
[[ $(sha256sum "$archive") == "$digest_before" ]]
[[ $(find "$runtime/backups" -maxdepth 1 -name 'netdata-*.tar.gz' | wc -l) -ge 2 ]]
printf 'invalid archive\n' > "$runtime/invalid.tar.gz"
if bash ./restore.sh -y "$runtime/invalid.tar.gz"; then
  printf 'An invalid backup was accepted\n' >&2; exit 1
fi
python3 smoke-api.py "http://$port" "$runtime/state.json" verify
"${compose[@]}" stop gateway netdata
bash ./backup.sh
[[ -z $("${compose[@]}" ps --status running --services) ]]
printf 'Netdata full volume-loss recovery, private archive, safety backup and stopped-state backup passed on %s\n' "$(uname -m)"
