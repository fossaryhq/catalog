#!/usr/bin/env python3
"""Exercise public web/API flows and verify a restored financial record."""
import datetime
import http.cookiejar
import json
import os
import pathlib
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

base, action, state_path = sys.argv[1:]
cookies = http.cookiejar.CookieJar()
session = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookies))
receipt = b'Fossary recovery receipt\nGroceries: EUR 37.45\n'


class Tokens(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.csrf = None
        self.feed(html)

    def handle_starttag(self, tag, attributes):
        values = dict(attributes)
        if tag == 'input' and values.get('name') == '_token':
            self.csrf = values.get('value')
        if tag == 'meta' and values.get('name') == 'csrf-token':
            self.csrf = values.get('content')


def request(path, fields=None, token=None, csrf=None, raw=None, anonymous=False):
    headers = {'Accept': 'application/json' if token or csrf else 'text/html'}
    data = raw
    if raw is not None:
        headers['Content-Type'] = 'application/octet-stream'
    if fields is not None:
        if token or csrf:
            data = json.dumps(fields).encode()
            headers['Content-Type'] = 'application/json'
        else:
            data = urllib.parse.urlencode(fields).encode()
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if csrf:
        headers['X-CSRF-TOKEN'] = csrf
        headers['X-Requested-With'] = 'XMLHttpRequest'
    opener = urllib.request.build_opener() if anonymous else session
    try:
        with opener.open(urllib.request.Request(base + path, data=data, headers=headers), timeout=90) as response:
            return response.status, response.read(), response.url
    except urllib.error.HTTPError as error:
        return error.code, error.read(), error.url


def api(path, token, fields=None, raw=None):
    status, body, _ = request('/api/v1' + path, fields, token, raw=raw)
    assert 200 <= status < 300, f'{path}: HTTP {status}: {body[:500]!r}'
    return json.loads(body) if body else None


def login(state):
    status, body, _ = request('/login')
    assert status == 200
    csrf = Tokens(body.decode()).csrf
    assert csrf, 'login form must contain a CSRF token'
    status, _, url = request('/login', {'_token': csrf, 'email': state['email'], 'password': state['password']})
    assert status == 200 and '/login' not in urllib.parse.urlparse(url).path, 'stored credentials must sign in'


if action == 'seed':
    state = {'email': 'recovery@example.com', 'password': secrets.token_hex(24)}
    status, body, _ = request('/register')
    assert status == 200
    csrf = Tokens(body.decode()).csrf
    assert csrf, 'registration must contain a CSRF token'
    status, _, url = request('/register', {'_token': csrf, 'email': state['email'], 'password': state['password'], 'password_confirmation': state['password']})
    assert status == 200 and '/register' not in urllib.parse.urlparse(url).path, 'first account registration must succeed'
    status, body, _ = request('/profile/oauth')
    assert status == 200
    csrf = Tokens(body.decode()).csrf
    assert csrf, 'OAuth page must contain a CSRF token'
    status, body, _ = request('/oauth/personal-access-tokens', {'name': 'Recovery check'}, csrf=csrf)
    assert status == 200, f'token creation: HTTP {status}'
    state['token'] = json.loads(body)['accessToken']
    account = api('/accounts', state['token'], {'name': 'Household current account', 'type': 'asset', 'account_role': 'defaultAsset', 'currency_code': 'EUR', 'opening_balance': '1200.00', 'opening_balance_date': datetime.date.today().replace(day=1).isoformat()})['data']
    state['account_id'] = account['id']
    transaction = api('/transactions', state['token'], {'error_if_duplicate_hash': True, 'apply_rules': False, 'fire_webhooks': False, 'transactions': [{'type': 'withdrawal', 'date': datetime.date.today().isoformat(), 'amount': '37.45', 'description': 'Weekly groceries', 'source_id': account['id'], 'destination_name': 'Neighbourhood market', 'currency_code': 'EUR', 'category_name': 'Groceries', 'tags': ['household'], 'notes': 'Recovery check: retain this private financial record.'}]})['data']
    state['transaction_id'] = transaction['id']
    journal = transaction['attributes']['transactions'][0]['transaction_journal_id']
    attachment = api('/attachments', state['token'], {'filename': 'receipt.txt', 'title': 'Groceries receipt', 'attachable_type': 'TransactionJournal', 'attachable_id': journal})['data']
    state['attachment_id'] = attachment['id']
    api('/attachments/' + attachment['id'] + '/upload', state['token'], raw=receipt)
    path = pathlib.Path(state_path)
    path.write_text(json.dumps(state))
    path.chmod(0o600)
elif action == 'verify':
    state = json.loads(pathlib.Path(state_path).read_text())
else:
    raise SystemExit('action must be seed or verify')

login(state)
token = state['token']
account = api('/accounts/' + state['account_id'], token)['data']
assert account['attributes']['name'] == 'Household current account'
transaction = api('/transactions/' + state['transaction_id'], token)['data']['attributes']['transactions'][0]
assert transaction['description'] == 'Weekly groceries'
assert abs(float(transaction['amount']) - 37.45) < 0.00001
assert transaction['category_name'] == 'Groceries' and 'household' in transaction['tags']
status, body, _ = request('/api/v1/attachments/' + state['attachment_id'] + '/download', token=token)
assert status == 200 and body == receipt, 'the encrypted attachment must download byte-for-byte'
status, _, _ = request('/api/v1/accounts', token='invalid', anonymous=True)
assert status == 401, 'anonymous API access must be rejected'
status, body, _ = request('/register', anonymous=True)
assert status != 200 or b'name="password_confirmation"' not in body, 'public registration must close after the first account'
print('Firefly III login, API token, account, transaction, category, tag, attachment and closed registration verified')
