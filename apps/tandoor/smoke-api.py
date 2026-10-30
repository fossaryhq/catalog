#!/usr/bin/env python3
"""Check native owner setup, session login and persisted recipe/media data."""
import datetime
import hashlib
import http.cookiejar
import json
import pathlib
import secrets
import struct
import sys
import urllib.error
import urllib.parse
import urllib.request
import zlib
from html.parser import HTMLParser

base, action, state_path = sys.argv[1:]
cookies = http.cookiejar.CookieJar()
session = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookies))


class Tokens(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.csrf = None
        self.feed(html)

    def handle_starttag(self, tag, attributes):
        values = dict(attributes)
        if tag == 'input' and values.get('name') == 'csrfmiddlewaretoken':
            self.csrf = values.get('value')


def request(path, fields=None, raw=None, content_type=None, anonymous=False, method=None):
    is_json = path.startswith(('/api/', '/_allauth/'))
    headers = {'Accept': 'application/json' if is_json else 'text/html', 'Referer': base + '/'}
    for cookie in cookies:
        if cookie.name == 'csrftoken':
            headers['X-CSRFToken'] = cookie.value
    data = raw
    if fields is not None:
        if is_json:
            data = json.dumps(fields).encode()
            headers['Content-Type'] = 'application/json'
        else:
            data = urllib.parse.urlencode(fields).encode()
    if content_type:
        headers['Content-Type'] = content_type
    opener = urllib.request.build_opener() if anonymous else session
    try:
        with opener.open(urllib.request.Request(base + path, data=data, headers=headers, method=method), timeout=90) as response:
            return response.status, response.read(), response.url
    except urllib.error.HTTPError as error:
        return error.code, error.read(), error.url


def api(path, fields=None):
    status, body, _ = request('/api/' + path, fields)
    assert 200 <= status < 300, f'{path}: HTTP {status}: {body[:500]!r}'
    return json.loads(body) if body else None


def login(state):
    request('/_allauth/browser/v1/auth/session')
    status, body, _ = request('/_allauth/browser/v1/auth/login', {'username': state['username'], 'password': state['password']})
    assert status == 200 and json.loads(body)['meta']['is_authenticated'], f'owner must log in: HTTP {status}: {body[:300]!r}'


if action == 'seed':
    state = {'username': 'recovery-owner', 'password': secrets.token_hex(24)}
    pathlib.Path(state_path).write_text(json.dumps(state))
    pathlib.Path(state_path).chmod(0o600)
    status, body, _ = request('/setup/')
    assert status == 200
    csrf = Tokens(body.decode()).csrf
    assert csrf, 'setup needs its native CSRF token'
    status, _, url = request('/setup/', {'csrfmiddlewaretoken': csrf, 'name': state['username'], 'password': state['password'], 'password_confirm': state['password']})
    assert status == 200 and '/setup/' not in urllib.parse.urlparse(url).path, 'first owner setup must succeed'
    login(state)
    recipe = api('recipe/', {'name': 'Weeknight lentil soup', 'description': 'A private household recipe for the recovery check.', 'servings': 4, 'working_time': 15, 'waiting_time': 20, 'internal': True, 'private': True, 'keywords': [{'name': 'weeknight'}], 'steps': [{'name': 'Simmer the soup', 'instruction': 'Rinse the lentils. Simmer with vegetables and water for 20 minutes; season and serve.', 'ingredients': [{'food': {'name': 'Red lentils'}, 'unit': {'name': 'g'}, 'amount': 200, 'order': 0}], 'order': 0}]})
    state['recipe_id'] = recipe['id']
    def chunk(kind, value):
        return struct.pack('>I', len(value)) + kind + value + struct.pack('>I', zlib.crc32(kind + value) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 32, 32, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\0' + b'\x88\xaa\x44' * 32) * 32)) + chunk(b'IEND', b'')
    boundary = 'fossary-' + secrets.token_hex(12)
    data = ('--' + boundary + '\r\nContent-Disposition: form-data; name="image"; filename="recipe.png"\r\nContent-Type: image/png\r\n\r\n').encode() + png + ('\r\n--' + boundary + '--\r\n').encode()
    status, body, _ = request(f'/api/recipe/{recipe["id"]}/image/', raw=data, content_type='multipart/form-data; boundary=' + boundary, method='PUT')
    assert 200 <= status < 300, f'image upload: HTTP {status}: {body[:300]!r}'
    recipe = api(f'recipe/{state["recipe_id"]}/')
    image_path = urllib.parse.urlparse(recipe['image']).path
    status, image, _ = request(image_path)
    assert status == 200 and len(image) > 50
    state['image_sha256'] = hashlib.sha256(image).hexdigest()
    path = pathlib.Path(state_path)
    path.write_text(json.dumps(state))
    path.chmod(0o600)
elif action == 'verify':
    state = json.loads(pathlib.Path(state_path).read_text())
    login(state)
else:
    raise SystemExit('action must be seed or verify')

recipe = api(f'recipe/{state["recipe_id"]}/')
assert recipe['name'] == 'Weeknight lentil soup' and recipe['servings'] == 4
assert recipe['private'] is True
assert any(keyword['name'] == 'weeknight' for keyword in recipe['keywords'])
assert recipe['steps'][0]['ingredients'][0]['food']['name'] == 'Red lentils'
assert 'Simmer with vegetables' in recipe['steps'][0]['instruction']
status, image, _ = request(urllib.parse.urlparse(recipe['image']).path)
assert status == 200 and hashlib.sha256(image).hexdigest() == state['image_sha256'], 'stored recipe media must return byte-for-byte'
status, _, _ = request('/api/recipe/', anonymous=True)
assert status in (401, 403), 'anonymous recipe API access must be denied'
status, body, _ = request('/_allauth/browser/v1/config', anonymous=True)
assert status == 200 and json.loads(body)['data']['account']['is_open_for_signup'] is False, 'public registration must be disabled'
print('Tandoor owner login, private recipe, ingredient, keyword, instructions, stored image and closed registration verified')
