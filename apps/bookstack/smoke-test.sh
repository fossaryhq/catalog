#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="smoke-bookstack-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$"
work="$(mktemp -d)"
export COMPOSE_PROJECT_NAME="$project" FOSSARY_ENV_FILE="$work/.env" BOOKSTACK_BACKUP_DIR="$work/backups"
cp "$app_dir/.env.example" "$FOSSARY_ENV_FILE"
python3 - "$FOSSARY_ENV_FILE" "$project" <<'PY'
import base64, pathlib, secrets, socket, sys
path = pathlib.Path(sys.argv[1])
with socket.socket() as s:
    s.bind(('127.0.0.1', 0))
    port = s.getsockname()[1]
values = {
    'BOOKSTACK_PORT': str(port), 'BOOKSTACK_APP_URL': f'http://127.0.0.1:{port}',
    'BOOKSTACK_APP_KEY': 'base64:' + base64.b64encode(secrets.token_bytes(32)).decode(),
    'BOOKSTACK_DB_PASSWORD': secrets.token_hex(24), 'BOOKSTACK_DB_ROOT_PASSWORD': secrets.token_hex(24),
    'BOOKSTACK_CONFIG_VOLUME': sys.argv[2] + '-config', 'BOOKSTACK_DB_VOLUME': sys.argv[2] + '-database',
}
path.write_text('\n'.join(key + '=' + values.get(key, value) if '=' in line and not line.startswith('#') else line
    for line in path.read_text().splitlines() for key, _, value in [line.partition('=')]) + '\n')
PY
set -a
# shellcheck disable=SC1090
. "$FOSSARY_ENV_FILE"
set +a
compose=(docker compose --project-name "$project" --env-file "$FOSSARY_ENV_FILE" --file "$app_dir/compose.yaml")
cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=100
  "${compose[@]}" down --volumes --remove-orphans --timeout 30
  rm -rf "$work"
  exit "$status"
}
trap 'echo "Check failed on line $LINENO" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up -d --wait --wait-timeout 600
published="$("${compose[@]}" port bookstack 80)"
[[ "$published" == "127.0.0.1:$BOOKSTACK_PORT" ]]
[[ "$("${compose[@]}" exec -T bookstack cat /app/www/version | tr -d '\r\n')" == "$BOOKSTACK_VERSION" ]]
curl --fail --silent --show-error "$BOOKSTACK_APP_URL/status" | python3 -c 'import json,sys; assert json.load(sys.stdin) == {"database":True,"cache":True,"session":True}'
password="$(openssl rand -hex 24)"
export BOOKSTACK_SMOKE_PASSWORD="$password"
"${compose[@]}" exec -T bookstack php /app/www/artisan bookstack:create-admin --initial \
  --email=smoke@example.com --name='Restore Check' --password="$password"

login_and_check() {
  python3 - "$1" <<'PY'
import html, http.cookiejar, os, re, sys, urllib.parse, urllib.request
base = os.environ['BOOKSTACK_APP_URL']
client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
def get(path):
    return client.open(base + path, timeout=30).read().decode()
def token(page):
    return html.unescape(re.search(r'name="_token"[^>]*value="([^"]+)"', page)[1])
def post(path, data):
    return client.open(base + path, urllib.parse.urlencode(data).encode(), timeout=30)
login = get('/login')
result = post('/login', {'email':'smoke@example.com', 'password':os.environ['BOOKSTACK_SMOKE_PASSWORD'], '_token':token(login)})
assert '/login' not in result.url, 'login did not succeed'
if sys.argv[1] == 'seed':
    form = get('/create-book')
    response = post('/books', {'name':'Fossary Restore Check','description_html':'<p>Database restore verification</p>','_token':token(form)})
    assert response.url.endswith('/books/fossary-restore-check'), response.url
assert 'Database restore verification' in get('/books/fossary-restore-check')
PY
}
login_and_check seed
"${compose[@]}" exec -T bookstack sh -c 'printf "restore-check\n" > /config/www/uploads/fossary-restore-check'
bash "$app_dir/backup.sh"
archives=("$BOOKSTACK_BACKUP_DIR"/bookstack-*.tar)
[[ -s "${archives[0]}" ]]
"${compose[@]}" up -d --wait --wait-timeout 300
# An incomplete backup must fail before touching live data.
tar -C "$work" -cf "$work/incomplete.tar" .env
if bash "$app_dir/restore.sh" "$work/incomplete.tar"; then
  echo "Incomplete backup was accepted" >&2
  exit 1
fi
python3 - "${archives[0]}" "$work/unsafe.tar" <<'PYTEST'
import io, sys, tarfile
payload = io.BytesIO()
with tarfile.open(fileobj=payload, mode='w:gz') as config:
    member = tarfile.TarInfo('../outside-config')
    member.size = 4
    config.addfile(member, io.BytesIO(b'test'))
with tarfile.open(sys.argv[1]) as original, tarfile.open(sys.argv[2], 'w') as target:
    for member in original.getmembers():
        data = payload.getvalue() if member.name == 'config.tar.gz' else original.extractfile(member).read()
        member.size = len(data)
        target.addfile(member, io.BytesIO(data))
PYTEST
if bash "$app_dir/restore.sh" "$work/unsafe.tar"; then
  echo "Unsafe configuration archive was accepted" >&2
  exit 1
fi
login_and_check verify
"${compose[@]}" exec -T database sh -c 'mariadb --user="$MARIADB_USER" --password="$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "DELETE FROM entities WHERE slug = '\''fossary-restore-check'\'';"'
"${compose[@]}" exec -T bookstack rm /config/www/uploads/fossary-restore-check
"${compose[@]}" stop bookstack
bash "$app_dir/backup.sh"
container_id="$("${compose[@]}" ps --all --quiet bookstack)"
[[ "$(docker inspect --format '{{.State.Running}}' "$container_id")" == false ]]
bash "$app_dir/restore.sh" "${archives[0]}"
"${compose[@]}" exec -T bookstack grep -Fxq restore-check /config/www/uploads/fossary-restore-check
login_and_check verify
curl --fail --silent --show-error "$BOOKSTACK_APP_URL/status" >/dev/null
echo "BookStack login, database/files backup and restore passed on $published"
