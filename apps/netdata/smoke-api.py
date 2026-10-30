#!/usr/bin/env python3
"""Verify the authenticated Agent API and persisted native metric history."""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

base, state_path, mode = sys.argv[1:]
credentials = os.environ['NETDATA_TEST_USER'] + ':' + os.environ['NETDATA_TEST_PASSWORD']
authorization = 'Basic ' + base64.b64encode(credentials.encode()).decode()


def get(path, authenticated=True):
    headers = {'Authorization': authorization} if authenticated else {}
    with urllib.request.urlopen(urllib.request.Request(base + path, headers=headers), timeout=20) as response:
        return json.load(response)


for path in ['/', '/api/v1/info', '/api/v1/charts', '/api/v3/contexts']:
    try:
        get(path, authenticated=False)
    except urllib.error.HTTPError as error:
        assert error.code == 401, (path, error.code)
    else:
        raise AssertionError('Anonymous access was accepted: ' + path)

for attempt in range(60):
    info = get('/api/v1/info')
    charts = get('/api/v1/charts')['charts']
    if 'system.cpu' in charts and 'system.ram' in charts and charts['system.cpu']['last_entry'] > 0:
        break
    time.sleep(2)
else:
    raise AssertionError('Native CPU and RAM charts did not become available')

assert info['version'] == 'v2.12.2', info['version']
assert int(info['cores_total']) == int(os.environ['NETDATA_TEST_CORES'])
assert info['agent-claimed'] is False, 'The recipe must remain unclaimed'
assert info['stream-enabled'] is False, 'Streaming must remain disabled'

if mode == 'record':
    # Query completed samples, so ongoing collection cannot change this interval.
    time.sleep(25)
    before = int(time.time()) - 5
    query = '/api/v1/data?' + urllib.parse.urlencode({
        'chart': 'system.cpu', 'after': before - 15, 'before': before,
        'points': 30, 'format': 'json', 'group': 'average',
    })
    history = get(query)
    assert len(history['data']) >= 5, history
    assert any(any(isinstance(value, (int, float)) for value in row[1:]) for row in history['data'])
    state = {'uid': info['uid'], 'query': query, 'labels': history['labels'], 'data': history['data']}
    with open(state_path, 'w', encoding='utf-8') as output:
        json.dump(state, output)
elif mode == 'verify':
    with open(state_path, encoding='utf-8') as source:
        state = json.load(source)
    assert info['uid'] == state['uid'], 'The original Agent identity was not restored'
    history = get(state['query'])
    assert history['labels'] == state['labels'], 'Historical metric dimensions changed'
    assert history['data'] == state['data'], 'Historical measurements were not restored exactly'
else:
    raise AssertionError('Unknown verification mode')
print('Authenticated Agent API, anonymous denial, host CPU/RAM, identity and native metric history verified')
