#!/usr/bin/env bash
set -Eeuo pipefail
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
project="homepage-smoke-$(date +%s)-$$"
cleanup() {
  status=$?
  trap - EXIT INT TERM
  "${compose[@]}" logs --no-color --tail=100 || true
  "${compose[@]}" down --volumes --remove-orphans || true
  docker run --rm -v "$tmp:/cleanup" alpine:3.22 sh -c 'rm -rf /cleanup/config /cleanup/backups' || true
  rm -rf "$tmp"
  exit "$status"
}
export COMPOSE_PROJECT_NAME="$project"
export FOSSARY_ENV_FILE="$tmp/.env"
export HOMEPAGE_BACKUP_DIR="$tmp/backups"
cp -R "$app_dir/config" "$tmp/config"
export HOMEPAGE_PORT
HOMEPAGE_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
export HOMEPAGE_CONFIG_DIR="$tmp/config"
export HOMEPAGE_ALLOWED_HOSTS="127.0.0.1:$HOMEPAGE_PORT"
export HOMEPAGE_EXTERNAL_URL="http://127.0.0.1:$HOMEPAGE_PORT"
export HOMEPAGE_AUTH_PASSWORD
HOMEPAGE_AUTH_PASSWORD="$(openssl rand -hex 16)"
export HOMEPAGE_AUTH_SECRET
HOMEPAGE_AUTH_SECRET="$(openssl rand -hex 32)"
export HOMEPAGE_VERSION="${HOMEPAGE_VERSION:-v2.7.0}"
export TZ=Etc/UTC
umask 077
for name in HOMEPAGE_VERSION HOMEPAGE_PORT HOMEPAGE_CONFIG_DIR HOMEPAGE_ALLOWED_HOSTS HOMEPAGE_EXTERNAL_URL HOMEPAGE_AUTH_PASSWORD HOMEPAGE_AUTH_SECRET TZ; do printf '%s=%s\n' "$name" "${!name}"; done > "$FOSSARY_ENV_FILE"
compose=(docker compose --project-name "$project" --env-file "$FOSSARY_ENV_FILE" --file "$app_dir/compose.yaml")
trap cleanup EXIT
trap 'exit 130' INT TERM
"${compose[@]}" config --quiet
"${compose[@]}" pull --quiet
"${compose[@]}" up -d --wait --wait-timeout 180
cat > "$tmp/check.py" <<'PYCODE'
import os, sys, json, urllib.request, urllib.parse, urllib.error, http.cookiejar
base=os.environ['HOMEPAGE_EXTERNAL_URL']
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs): return None
public=urllib.request.build_opener(NoRedirect)
def status(path,headers={}):
 try: return public.open(urllib.request.Request(base+path,headers=headers),timeout=30).status
 except urllib.error.HTTPError as e: return e.code
assert urllib.request.urlopen(base+'/api/healthcheck').read()==b'up'
assert status('/api/services')==307
assert status('/api/bookmarks')==307
assert status('/api/config/settings')==307
assert status('/api/healthcheck',{'Host':'unexpected.invalid'})==400
jar=http.cookiejar.CookieJar();client=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
csrf=json.load(client.open(base+'/api/auth/csrf'))['csrfToken']
def login(password):
 data=urllib.parse.urlencode({'csrfToken':csrf,'password':password,'callbackUrl':base+'/','json':'true'}).encode()
 try: return json.load(client.open(urllib.request.Request(base+'/api/auth/callback/credentials',data=data)))
 except urllib.error.HTTPError as e:
  if e.code!=401: raise
  return json.load(e)
assert 'error=' in login('invalid-password')['url']
assert status('/api/services')==307
assert 'error=' not in login(os.environ['HOMEPAGE_AUTH_PASSWORD'])['url']
services=json.load(client.open(base+'/api/services'))
bookmarks=json.load(client.open(base+'/api/bookmarks'))
if sys.argv[1]=='empty':
 assert 'Recovery sentinel' not in json.dumps(services)
else:
 assert 'Recovery sentinel' in json.dumps(services)
 assert 'Recovery bookmark' in json.dumps(bookmarks)
assert json.load(client.open(base+'/api/auth/session'))['user']['name']=='Homepage'
print('Login, blocked anonymous APIs/Host and dashboard content verified:',sys.argv[1])
PYCODE
cat >> "$tmp/config/services.yaml" <<'YAML'
- Recovery:
    - Recovery sentinel:
        href: https://example.com/recovered
        description: Dashboard entry preserved by backup
YAML
cat >> "$tmp/config/bookmarks.yaml" <<'YAML'
- Recovery:
    - Recovery bookmark:
        - abbr: RB
          href: https://example.com/bookmark
YAML
"${compose[@]}" restart homepage
"${compose[@]}" up -d --wait --wait-timeout 180
python3 "$tmp/check.py" populated
bash "$app_dir/backup.sh"
archive="$(find "$tmp/backups" -name 'homepage-*.tar' | sort | tail -n 1)"
[[ -n "$archive" && "$(stat -c %a "$archive")" == 600 ]]
# An incomplete archive must be rejected while the existing service keeps running.
mkdir "$tmp/invalid"
printf test > "$tmp/invalid/test"
tar -C "$tmp/invalid" -czf "$tmp/invalid-data.tar.gz" test
mkdir "$tmp/bad"
cp "$tmp/invalid-data.tar.gz" "$tmp/bad/data.tar.gz"
cp "$FOSSARY_ENV_FILE" "$tmp/bad/configuration.env"
cp "$app_dir/compose.yaml" "$tmp/bad/compose.yaml"
tar -C "$tmp/bad" -cf "$tmp/invalid.tar" data.tar.gz configuration.env compose.yaml
if bash "$app_dir/restore.sh" "$tmp/invalid.tar"; then echo 'Invalid backup was accepted' >&2; exit 1; fi
[[ "$("${compose[@]}" ps --status running --quiet homepage)" != '' ]]
"${compose[@]}" stop homepage
docker run --rm -v "$tmp/config:/data" alpine:3.22 sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +'
"${compose[@]}" up -d --wait --wait-timeout 180
python3 "$tmp/check.py" empty
bash "$app_dir/restore.sh" "$archive"
python3 "$tmp/check.py" restored
"${compose[@]}" stop homepage
bash "$app_dir/backup.sh"
[[ "$("${compose[@]}" ps --status running --quiet homepage)" == '' ]]
echo 'Homepage smoke and clean-data restore passed; stopped-state backup preserved.'
