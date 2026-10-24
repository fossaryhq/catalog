#!/usr/bin/env bash
set -Eeuo pipefail
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
project="beszel-smoke-$(date +%s)-$$"
export COMPOSE_PROJECT_NAME="$project"
export FOSSARY_ENV_FILE="$tmp/.env"
export BESZEL_BACKUP_DIR="$tmp/backups"
export BESZEL_PORT
BESZEL_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
export BESZEL_URL="http://127.0.0.1:$BESZEL_PORT"
export BESZEL_VERSION="${BESZEL_VERSION:-0.21.1}"
export BESZEL_DATA_VOLUME="$project-data"
export BESZEL_ADMIN_EMAIL=recipe@example.com
export BESZEL_ADMIN_PASSWORD
BESZEL_ADMIN_PASSWORD="$(openssl rand -hex 24)"
export TZ=Etc/UTC
export BESZEL_AGENT_NAME="$project-agent"
umask 077
for name in BESZEL_VERSION BESZEL_PORT BESZEL_URL BESZEL_DATA_VOLUME BESZEL_ADMIN_EMAIL BESZEL_ADMIN_PASSWORD TZ; do printf '%s=%s\n' "$name" "${!name}"; done > "$FOSSARY_ENV_FILE"
compose=(docker compose --project-name "$project" --env-file "$FOSSARY_ENV_FILE" --file "$app_dir/compose.yaml")
cleanup() {
  status=$?
  trap - EXIT INT TERM
  "${compose[@]}" logs --no-color --tail=100 || true
  docker logs --tail=30 "$BESZEL_AGENT_NAME" || true
  docker rm --force "$BESZEL_AGENT_NAME" >/dev/null 2>&1 || true
  "${compose[@]}" down --volumes --remove-orphans || true
  rm -rf "$tmp"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
"${compose[@]}" config --quiet
"${compose[@]}" pull --quiet
docker pull "henrygd/beszel-agent:$BESZEL_VERSION" >/dev/null
"${compose[@]}" up -d --wait --wait-timeout 180
cat > "$tmp/check.py" <<'PYCODE'
import os,sys,json,time,urllib.request,urllib.error,urllib.parse,subprocess
from pathlib import Path
base=os.environ['BESZEL_URL'];mode=sys.argv[1];statepath=Path(sys.argv[2])
def req(path,body=None,token=None,method=None):
 headers={'Content-Type':'application/json'}
 if token:headers['Authorization']=token
 return json.load(urllib.request.urlopen(urllib.request.Request(base+path,data=json.dumps(body).encode() if body is not None else None,headers=headers,method=method),timeout=30))
def denied(path,body=None):
 try:req(path,body)
 except urllib.error.HTTPError as e:assert 400<=e.code<500;return
 raise AssertionError('Anonymous operation accepted: '+path)
assert req('/api/health')['code']==200
assert req('/api/beszel/first-run')['firstRun'] is False
denied('/api/beszel/info')
denied('/api/beszel/create-user',{'email':'intruder@example.com','password':'123456789012'})
denied('/api/collections/users/records',{'email':'intruder@example.com','password':'123456789012','passwordConfirm':'123456789012'})
assert req('/api/collections/systems/records')['totalItems']==0
login=req('/api/collections/users/auth-with-password',{'identity':os.environ['BESZEL_ADMIN_EMAIL'],'password':os.environ['BESZEL_ADMIN_PASSWORD']})
token=login['token'];uid=login['record']['id'];info=req('/api/beszel/info',token=token)
assert info['v']==os.environ['BESZEL_VERSION']
if mode=='seed':
 system=req('/api/collections/systems/records',{'name':'Recipe recovery sandbox','host':os.environ['BESZEL_AGENT_NAME'],'port':'45876','users':[uid]},token)
 settings=req('/api/collections/user_settings/records',{'user':uid},token)
 settings=req('/api/collections/user_settings/records/'+settings['id'],{'settings':{**settings['settings'],'lang':'en'}},token,'PATCH')
 state={'system':system['id'],'user':uid,'key':info['key'],'settings':settings['id']}
 statepath.write_text(json.dumps(state));statepath.chmod(0o600)
 subprocess.run(['docker','run','--detach','--rm','--name',os.environ['BESZEL_AGENT_NAME'],'--network',os.environ['COMPOSE_PROJECT_NAME']+'_default','--cap-drop','ALL','--security-opt','no-new-privileges:true','-e','KEY='+info['key'],'-e','LISTEN=45876','-e','DOCKER_HOST=','henrygd/beszel-agent:'+os.environ['BESZEL_VERSION']],check=True,stdout=subprocess.DEVNULL)
elif mode=='empty':
 assert req('/api/collections/systems/records',token=token)['totalItems']==0
 assert req('/api/collections/system_stats/records',token=token)['totalItems']==0
 assert info['key']!=json.loads(statepath.read_text())['key']
 print('Clean hub has no previous systems/history and a different SSH key');sys.exit()
else:
 state=json.loads(statepath.read_text())
 assert uid==state['user'] and info['key']==state['key']
 assert next(x for x in req('/api/collections/user_settings/records',token=token)['items'] if x['id']==state['settings'])['settings']['lang']=='en'
for attempt in range(90):
 system=req('/api/collections/systems/records/'+state['system'],token=token)
 stats=req('/api/collections/system_stats/records?filter='+urllib.parse.quote('system="'+state['system']+'"'),token=token)
 if system['status']=='up' and stats['totalItems']>0:break
 time.sleep(2)
else:raise AssertionError('Real agent never supplied metrics')
assert 'cpu' in stats['items'][0]['stats'] and 'm' in stats['items'][0]['stats']
if mode=='seed':
 state['stat']=stats['items'][0]['id'];statepath.write_text(json.dumps(state))
else:
 assert any(x['id']==state['stat'] for x in stats['items'])
print('Native login, closed registration, private history and real agent metrics verified:',mode)
PYCODE
python3 "$tmp/check.py" seed "$tmp/state.json"
bash "$app_dir/backup.sh"
archive="$(find "$tmp/backups" -name 'beszel-*.tar' | sort | tail -n 1)"
[[ -n "$archive" && "$(stat -c %a "$archive")" == 600 ]]
mkdir "$tmp/bad"
printf invalid > "$tmp/bad/sample"
tar -C "$tmp/bad" -czf "$tmp/bad/data.tar.gz" sample
cp "$FOSSARY_ENV_FILE" "$tmp/bad/configuration.env"
cp "$app_dir/compose.yaml" "$tmp/bad/compose.yaml"
tar -C "$tmp/bad" -cf "$tmp/invalid.tar" data.tar.gz configuration.env compose.yaml
if bash "$app_dir/restore.sh" "$tmp/invalid.tar"; then echo 'Invalid archive accepted' >&2; exit 1; fi
[[ "$("${compose[@]}" ps --status running --quiet beszel)" != '' ]]
"${compose[@]}" stop beszel
"${compose[@]}" rm --force beszel permissions
docker volume rm "$BESZEL_DATA_VOLUME" >/dev/null
"${compose[@]}" up -d --wait --wait-timeout 180
python3 "$tmp/check.py" empty "$tmp/state.json"
bash "$app_dir/restore.sh" "$archive"
python3 "$tmp/check.py" restored "$tmp/state.json"
"${compose[@]}" stop beszel
bash "$app_dir/backup.sh"
[[ "$("${compose[@]}" ps --status running --quiet beszel)" == '' ]]
echo 'Beszel smoke and fresh-volume restore passed; original key/history and stopped state preserved.'
