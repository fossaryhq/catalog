#!/usr/bin/env python3
"""Exercise the documented login, OAuth client form, and article API."""
import http.cookiejar
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

base, phase, state_file = sys.argv[1:]

class Form(HTMLParser):
    def __init__(self, source):
        super().__init__(convert_charrefs=True)
        self.inputs = {}
        self.codes = []
        self.in_code = False
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'input' and attrs.get('name'):
            self.inputs[attrs['name']] = attrs.get('value', '')
        if tag == 'code':
            self.in_code = True
            self.codes.append('')

    def handle_endtag(self, tag):
        if tag == 'code':
            self.in_code = False

    def handle_data(self, data):
        if self.in_code:
            self.codes[-1] += data

opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

def request(path, fields=None, token=None, authenticated=True):
    headers = {'Origin': base}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    body = None
    if fields is not None:
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
        body = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(base + path, data=body, headers=headers)
    try:
        response = (opener.open if authenticated else urllib.request.urlopen)(req, timeout=30)
        return response.status, response.read().decode(), response.url
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode(), error.url

def api(path, fields=None, token=None):
    status, text, _ = request(path, fields, token)
    assert 200 <= status < 300, f'{path}: HTTP {status}'
    return json.loads(text)

def token_for(client):
    return api('/oauth/v2/token', {'grant_type': 'password', 'client_id': client['client_id'], 'client_secret': client['client_secret'], 'username': 'wallabag', 'password': os.environ['WALLABAG_ADMIN_PASSWORD']})['access_token']

if phase == 'seed':
    info = api('/api/info')
    assert info['version'] == os.environ.get('WALLABAG_VERSION', '2.6.15'), 'wrong application version'
    assert info['allowed_registration'] is False, 'registration must be closed'
    status, page, _ = request('/login')
    assert status == 200
    fields = Form(page).inputs
    assert '_csrf_token' in fields
    fields.update({'_username': 'wallabag', '_password': os.environ['WALLABAG_ADMIN_PASSWORD']})
    status, page, target = request('/login_check', fields)
    assert status == 200 and '/login' not in urllib.parse.urlsplit(target).path, 'administrator login failed'
    status, page, _ = request('/developer/client/create')
    fields = Form(page).inputs
    assert 'client[_token]' in fields
    fields.update({'client[name]': 'Recovery verification', 'client[redirect_uris]': base})
    status, page, _ = request('/developer/client/create', fields)
    assert status == 200
    codes = Form(page).codes
    index = next(i for i, code in enumerate(codes) if re.fullmatch(r'[0-9]+_[a-z0-9]+', code.strip()))
    client = {'client_id': codes[index].strip(), 'client_secret': codes[index + 1].strip()}
    assert len(client['client_secret']) > 10
    status, _, _ = request('/oauth/v2/token', {'grant_type': 'password', **client, 'username': 'wallabag', 'password': 'wallabag'})
    assert status in (400, 401), 'the upstream default password must not work'
    token = token_for(client)
    entry = api('/api/entries.json', {'url': 'https://example.com/fossary-recovery', 'title': 'Recovery checklist', 'content': '<article><h1>Recovery checklist</h1><p>Keep the complete SQLite database and saved images in one verified backup.</p></article>', 'tags': 'recovery,home-server'}, token)
    assert entry['id'] and 'complete SQLite' in entry['content']
    with os.fdopen(os.open(state_file, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), 'w') as output:
        json.dump({'client': client, 'entry': entry}, output)
elif phase == 'verify':
    state = json.load(open(state_file))
    token = token_for(state['client'])
    entry = api(f"/api/entries/{state['entry']['id']}.json", token=token)
    assert entry['title'] == state['entry']['title']
    assert 'complete SQLite' in entry['content']
    assert {tag['label'] for tag in entry['tags']} == {'recovery', 'home-server'}
    status, _, _ = request(f"/api/entries/{entry['id']}.json", authenticated=False)
    assert status == 401, f'private entry exposed anonymously: {status}'
    assert api('/api/info')['allowed_registration'] is False
else:
    raise RuntimeError(f'Unknown phase: {phase}')
print(f'Wallabag API {phase} passed')
