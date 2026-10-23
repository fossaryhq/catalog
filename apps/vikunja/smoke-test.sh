#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="smoke-vikunja-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$"
work="$(mktemp -d)"
export COMPOSE_PROJECT_NAME="$project" FOSSARY_ENV_FILE="$work/.env" VIKUNJA_BACKUP_DIR="$work/backups"
cp "$app_dir/.env.example" "$FOSSARY_ENV_FILE"
python3 - "$FOSSARY_ENV_FILE" "$project" <<'PY'
import pathlib, secrets, socket, sys
path = pathlib.Path(sys.argv[1])
with socket.socket() as s:
    s.bind(('127.0.0.1', 0))
    port = s.getsockname()[1]
values = {'VIKUNJA_PORT':str(port), 'VIKUNJA_PUBLIC_URL':f'http://127.0.0.1:{port}/',
    'VIKUNJA_SECRET':secrets.token_hex(32), 'VIKUNJA_DB_PASSWORD':secrets.token_hex(32), 'VIKUNJA_DB_VOLUME':sys.argv[2]+'-database', 'VIKUNJA_DATA_VOLUME':sys.argv[2]+'-data'}
path.write_text('\n'.join(key+'='+values.get(key,value) if '=' in line and not line.startswith('#') else line
    for line in path.read_text().splitlines() for key,_,value in [line.partition('=')])+'\n')
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
"${compose[@]}" up -d --wait --wait-timeout 300
[[ "$("${compose[@]}" port vikunja 3456)" == "127.0.0.1:$VIKUNJA_PORT" ]]
curl --fail --silent --show-error "${VIKUNJA_PUBLIC_URL}health" | grep -Fxq OK
export VIKUNJA_SMOKE_PASSWORD="$(openssl rand -hex 24)"
"${compose[@]}" exec -T vikunja /app/vikunja/vikunja user create \
  --username=smoke --email=smoke@example.com --password="$VIKUNJA_SMOKE_PASSWORD"
cat > "$work/exercise.py" <<'PY'
import json, os, pathlib, secrets, sys, urllib.error, urllib.request
base = os.environ['VIKUNJA_PUBLIC_URL'].rstrip('/')
state = pathlib.Path(sys.argv[2])
def request(path, method='GET', data=None, headers=None):
    if isinstance(data, dict):
        data = json.dumps(data).encode()
        headers = {**(headers or {}), 'Content-Type':'application/json'}
    with urllib.request.urlopen(urllib.request.Request(base+path, data, headers or {}, method=method), timeout=30) as r:
        raw = r.read()
        return json.loads(raw) if raw and 'application/json' in r.headers.get('Content-Type','') else raw
info = request('/api/v1/info')
assert info['version'].lstrip('v') == os.environ['VIKUNJA_VERSION']
assert info['auth']['local']['registration_enabled'] is False
try:
    request('/api/v1/projects')
    raise AssertionError('private projects were readable without authentication')
except urllib.error.HTTPError as error:
    assert error.code == 401
login = request('/api/v1/login','POST',{'username':'smoke','password':os.environ['VIKUNJA_SMOKE_PASSWORD']})
headers = {'Authorization':'Bearer '+login['token']}
def api(path, method='GET', data=None, extra=None):
    return request('/api/v1'+path, method, data, {**headers, **(extra or {})})
if sys.argv[1] == 'seed':
    project = api('/projects','PUT',{'title':'Fossary Restore Check'})
    task = api(f"/projects/{project['id']}/tasks",'PUT',{'title':'Verify the restored task','description':'<p>Database and uploaded file restore check.</p>'})
    view = next(v for v in project['views'] if v['view_kind'] == 'kanban')
    buckets = api(f"/projects/{project['id']}/views/{view['id']}/buckets")
    moved = api(f"/projects/{project['id']}/views/{view['id']}/buckets/{buckets[1]['id']}/tasks",'POST',{'task_id':task['id']})
    assert moved['bucket_id'] == buckets[1]['id']
    boundary = secrets.token_hex(16)
    data = (f'--{boundary}\r\nContent-Disposition: form-data; name="files"; filename="restore-check.txt"\r\nContent-Type: text/plain\r\n\r\nrestore-check\n\r\n--{boundary}--\r\n').encode()
    upload = api(f"/tasks/{task['id']}/attachments",'PUT',data,{'Content-Type':'multipart/form-data; boundary='+boundary})
    assert not upload['errors']
    state.write_text(json.dumps({'task':task['id'], 'attachment':upload['success'][0]['id'], 'project':project['id'], 'view':view['id'], 'bucket':buckets[1]['id']}))
ids = json.loads(state.read_text())
task_path = f"/tasks/{ids['task']}"
attachment_path = task_path+f"/attachments/{ids['attachment']}"
if sys.argv[1] == 'delete':
    api(attachment_path,'DELETE')
    api(task_path,'DELETE')
    for path in [task_path, attachment_path]:
        try:
            api(path)
            raise AssertionError('deleted data still available')
        except urllib.error.HTTPError as error:
            assert error.code == 404, error.code
else:
    assert api(task_path)['title'] == 'Verify the restored task'
    assert api(attachment_path) == b'restore-check\n'
    board = api(f"/projects/{ids['project']}/views/{ids['view']}/tasks")
    assert any(b['id'] == ids['bucket'] and any(t['id'] == ids['task'] for t in b.get('tasks', [])) for b in board)
PY
python3 "$work/exercise.py" seed "$work/state.json"
bash "$app_dir/backup.sh"
archives=("$VIKUNJA_BACKUP_DIR"/vikunja-*.tar)
[[ -s "${archives[0]}" ]]
"${compose[@]}" up -d --wait --wait-timeout 300
# Reject incomplete and traversal archives before touching live data.
tar -C "$work" -cf "$work/incomplete.tar" .env
if bash "$app_dir/restore.sh" "$work/incomplete.tar"; then
  echo "Incomplete archive was accepted" >&2
  exit 1
fi
python3 - "${archives[0]}" "$work/unsafe.tar" <<'PY'
import io,sys,tarfile
payload=io.BytesIO()
with tarfile.open(fileobj=payload,mode='w:gz') as data:
    member=tarfile.TarInfo('../outside-data');member.size=4
    data.addfile(member,io.BytesIO(b'test'))
with tarfile.open(sys.argv[1]) as source, tarfile.open(sys.argv[2],'w') as target:
    for member in source.getmembers():
        data=payload.getvalue() if member.name=='data.tar.gz' else source.extractfile(member).read()
        member.size=len(data);target.addfile(member,io.BytesIO(data))
PY
if bash "$app_dir/restore.sh" "$work/unsafe.tar"; then
  echo "Unsafe archive was accepted" >&2
  exit 1
fi
python3 "$work/exercise.py" verify "$work/state.json"
python3 "$work/exercise.py" delete "$work/state.json"
"${compose[@]}" stop vikunja
bash "$app_dir/backup.sh"
container_id="$("${compose[@]}" ps --all --quiet vikunja)"
[[ "$(docker inspect --format '{{.State.Running}}' "$container_id")" == false ]]
bash "$app_dir/restore.sh" "${archives[0]}"
python3 "$work/exercise.py" verify "$work/state.json"
echo "Vikunja login, tasks, attachment, backup and restore passed"
