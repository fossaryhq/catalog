#!/usr/bin/env bash
set -Eeuo pipefail
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
export COMPOSE_PROJECT_NAME
COMPOSE_PROJECT_NAME="audiobookshelf-smoke-$(date +%s)-$$"
export FOSSARY_ENV_FILE="$tmp/.env"
export AUDIOBOOKSHELF_BACKUP_DIR="$tmp/backups"
export AUDIOBOOKSHELF_VERSION="${AUDIOBOOKSHELF_VERSION:-2.37.2}"
export AUDIOBOOKSHELF_PORT
AUDIOBOOKSHELF_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
export AUDIOBOOKSHELF_DATA_VOLUME="$COMPOSE_PROJECT_NAME-data"
export AUDIOBOOKSHELF_ADMIN_PASSWORD
AUDIOBOOKSHELF_ADMIN_PASSWORD="$(openssl rand -hex 24)"
export TZ=Etc/UTC
umask 077
for name in AUDIOBOOKSHELF_VERSION AUDIOBOOKSHELF_PORT AUDIOBOOKSHELF_DATA_VOLUME AUDIOBOOKSHELF_ADMIN_PASSWORD TZ; do printf '%s=%s\n' "$name" "${!name}"; done > "$FOSSARY_ENV_FILE"
compose=(docker compose --project-name "$COMPOSE_PROJECT_NAME" --env-file "$FOSSARY_ENV_FILE" --file "$app_dir/compose.yaml")
cleanup() {
  status=$?
  trap - EXIT INT TERM
  "${compose[@]}" logs --no-color --tail=60 || true
  "${compose[@]}" down --volumes --remove-orphans || true
  rm -rf "$tmp"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
"${compose[@]}" config --quiet
"${compose[@]}" up -d --wait --wait-timeout 180
if AUDIOBOOKSHELF_ADMIN_PASSWORD=CHANGE_ME_invalid "${compose[@]}" run --rm -T bootstrap; then echo 'Placeholder password accepted' >&2; exit 1; fi
"${compose[@]}" run --rm -T bootstrap
AUDIOBOOKSHELF_ADMIN_PASSWORD=changed-password-must-not-rotate "${compose[@]}" run --rm -T bootstrap
"${compose[@]}" exec -T audiobookshelf sh -c 'mkdir -p "/data/audiobooks/Fossary/Recovery sample" && ffmpeg -hide_banner -loglevel error -y -f lavfi -i "sine=frequency=440:duration=20" -codec:a libmp3lame -q:a 7 -metadata title="Recovery sample" -metadata album="Recovery sample" -metadata artist="Fossary" "/data/audiobooks/Fossary/Recovery sample/01.mp3"'
cat > "$tmp/check.py" <<'PYCODE'
import os,sys,json,time,secrets,hashlib,urllib.request,urllib.error
from pathlib import Path
base='http://127.0.0.1:'+os.environ['AUDIOBOOKSHELF_PORT'];mode=sys.argv[1];statepath=Path(sys.argv[2])
def req(path,body=None,token=None,method=None):
 headers={'Content-Type':'application/json'}
 if token:headers['Authorization']='Bearer '+token
 with urllib.request.urlopen(urllib.request.Request(base+path,data=json.dumps(body).encode() if body is not None else None,headers=headers,method=method),timeout=30) as r:
  data=r.read()
  try:return json.loads(data)
  except ValueError:return data.decode()
def denied(path,token=None,body=None,statuses=(400,401,403,404)):
 try:req(path,body,token)
 except urllib.error.HTTPError as e:assert e.code in statuses;return
 raise AssertionError('Operation accepted: '+path)
def audio(item,token):
 session=req('/api/items/'+item+'/play',{'supportedMimeTypes':['audio/mpeg'],'mediaPlayer':'html5','forceDirectPlay':True},token)
 url=session['audioTracks'][0]['contentUrl']
 denied(url)
 with urllib.request.urlopen(urllib.request.Request(base+url,headers={'Authorization':'Bearer '+token,'Range':'bytes=0-1023'}),timeout=30) as r:
  assert r.status==206;data=r.read();assert len(data)==1024
 return hashlib.sha256(data).hexdigest()
assert req('/ping')['success'] is True
status=req('/status');assert status['isInit'] is True and status['serverVersion']==os.environ['AUDIOBOOKSHELF_VERSION']
denied('/api/libraries')
denied('/init',body={'newRoot':{'username':'intruder','password':'intruder-password-not-accepted'}},statuses=(500,))
root=req('/login',{'username':'admin','password':os.environ['AUDIOBOOKSHELF_ADMIN_PASSWORD']})['user'];token=root['accessToken']
if mode=='empty':
 assert req('/api/libraries',token=token)['libraries']==[]
 print('Fresh volume contains no old library');sys.exit()
if mode=='seed':
 lib=req('/api/libraries',{'name':'Recovery library','folders':[{'fullPath':'/data/audiobooks'}],'mediaType':'book','icon':'audiobooks'},token)
 hidden=req('/api/libraries',{'name':'Private podcasts','folders':[{'fullPath':'/data/podcasts'}],'mediaType':'podcast','icon':'podcast'},token)
 req('/api/libraries/'+lib['id']+'/scan',{},token)
 for attempt in range(60):
  items=req('/api/libraries/'+lib['id']+'/items',token=token)['results']
  if items:break
  time.sleep(1)
 else:raise AssertionError('Media was not scanned')
 item=items[0];assert item['media']['metadata']['title']=='Recovery sample'
 password=secrets.token_hex(24)
 listener=req('/api/users',{'username':'listener','password':password,'type':'user','isActive':True,'permissions':{'accessAllLibraries':False,'upload':False,'update':False,'delete':False},'librariesAccessible':[lib['id']]},token)
 listener=req('/login',{'username':'listener','password':password})['user'];lt=listener['accessToken']
 req('/api/me/progress/'+item['id'],{'currentTime':7,'duration':20,'progress':0.35,'isFinished':False},lt,'PATCH')
 req('/api/me/item/'+item['id']+'/bookmark',{'time':8,'title':'Recovery bookmark'},lt)
 collection=req('/api/collections',{'libraryId':lib['id'],'name':'Recovery collection','description':'Original recipe test media','books':[item['id']]},token)
 state={'library':lib['id'],'hidden':hidden['id'],'item':item['id'],'listener':listener['id'],'password':password,'root':root['id'],'collection':collection['id'],'hash':audio(item['id'],lt),'token':lt}
 statepath.write_text(json.dumps(state));statepath.chmod(0o600)
else:
 state=json.loads(statepath.read_text());assert root['id']==state['root']
 lt=req('/login',{'username':'listener','password':state['password']})['user']['accessToken']
 assert req('/api/me',token=state['token'])['id']==state['listener']
 assert audio(state['item'],lt)==state['hash']
assert req('/api/me/progress/'+state['item'],token=lt)['currentTime']==7
assert any(x['title']=='Recovery bookmark' for x in req('/api/me/bookmarks/'+state['item'],token=lt)['bookmarks'])
assert req('/api/collections/'+state['collection'],token=token)['name']=='Recovery collection'
assert req('/api/libraries/'+state['library']+'/items',token=lt)['total']==1
denied('/api/libraries/'+state['hidden']+'/items',lt)
print('Native accounts, library ACL, audio range, progress, bookmark and collection verified:',mode)
PYCODE
python3 "$tmp/check.py" seed "$tmp/state.json"
bash "$app_dir/backup.sh"
archive="$(find "$tmp/backups" -name 'audiobookshelf-*.tar' | sort | tail -n 1)"
[[ -n "$archive" && "$(stat -c %a "$archive")" == 600 ]]
mkdir "$tmp/bad"
"${compose[@]}" cp audiobookshelf:/data/config/absdatabase.sqlite "$tmp/bad/absdatabase.sqlite"
mkdir "$tmp/bad/config"
mv "$tmp/bad/absdatabase.sqlite" "$tmp/bad/config/"
tar -C "$tmp/bad" -czf "$tmp/bad/data.tar.gz" config
cp "$FOSSARY_ENV_FILE" "$tmp/bad/configuration.env"
cp "$app_dir/compose.yaml" "$tmp/bad/compose.yaml"
tar -C "$tmp/bad" -cf "$tmp/invalid.tar" data.tar.gz configuration.env compose.yaml
if bash "$app_dir/restore.sh" "$tmp/invalid.tar"; then echo 'Database-only archive accepted' >&2; exit 1; fi
[[ "$("${compose[@]}" ps --status running --quiet audiobookshelf)" != '' ]]
"${compose[@]}" down --volumes
"${compose[@]}" up -d --wait --wait-timeout 180
"${compose[@]}" run --rm -T bootstrap
python3 "$tmp/check.py" empty "$tmp/state.json"
bash "$app_dir/restore.sh" "$archive"
python3 "$tmp/check.py" restored "$tmp/state.json"
"${compose[@]}" stop audiobookshelf
bash "$app_dir/backup.sh"
[[ "$("${compose[@]}" ps --status running --quiet audiobookshelf)" == '' ]]
echo 'Audiobookshelf smoke and full fresh-volume restore passed; actual media, credentials and listening state preserved.'
