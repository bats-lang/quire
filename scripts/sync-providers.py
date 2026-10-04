#!/usr/bin/env python3
"""The sync services Quire signs in to, checked from outside the app
(bats-lang/quire#184, sync-providers.yml):

  clients       Each OAuth client in scripts/sync-clients.env is asked
                for its sign-in page, with no one signing in: Dropbox's
                app key at each redirect address the app sends readers
                back to, and Google's web client as Google's sign-in
                script asks for a token. An answer that the client, the
                redirect address or the scope is refused (invalid_client,
                redirect_uri_mismatch, invalid_scope, ...) fails; a
                service not reached is only reported. Google's Android
                client is matched by the app's package and signing key,
                never sent, so sync-identity.yml checks it.
  fastmail-cors Whether a browser page may now reach Fastmail's files:
                the CORS preflight a page's PROPFIND would make. Not a
                failure either way; the app's Sync screen asks the same
                each time it opens, and offers Fastmail when it can.
  round-trips   With a test account's secrets (each service skipped
                without its own), the file the app keeps, written,
                read back, written again over a stale version (which
                must be refused as a conflict) and deleted, as the
                app's store for that service does it, in a file of its
                own (quire-sync-ci.json):
                  FASTMAIL_TEST_USER, FASTMAIL_TEST_APP_PASSWORD
                  NEXTCLOUD_TEST_URL, NEXTCLOUD_TEST_USER,
                    NEXTCLOUD_TEST_APP_PASSWORD
                  DROPBOX_TEST_REFRESH_TOKEN (of the app's own key)
                  GOOGLE_TEST_CLIENT_ID, GOOGLE_TEST_CLIENT_SECRET,
                    GOOGLE_TEST_REFRESH_TOKEN (a Desktop test client's)
  dropbox-sign-in, google-sign-in
                For a maintainer, once, on their own machine: signs a
                test account in and prints the refresh token to store as
                the secret above (see the issue that asks for them).

Each command writes Markdown to $GITHUB_STEP_SUMMARY when it is set.

usage: scripts/sync-providers.py clients|fastmail-cors|round-trips|dropbox-sign-in|google-sign-in
"""
import base64
import hashlib
import http.server
import json
import os
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ENV = Path(__file__).resolve().parent / 'sync-clients.env'
# Where the app sends a reader back to from Dropbox's sign-in (#184)
DROPBOX_REDIRECTS = [
    'https://bats-lang.github.io/quire/?oauth=dropbox',
    'http://localhost:3737/?oauth=dropbox',
    'quire://oauth/dropbox',
]
DROPBOX_SCOPE = 'files.content.read files.content.write'
# The origins Google's web client lets sign in (its JavaScript origins)
GOOGLE_ORIGINS = ['https://bats-lang.github.io', 'http://localhost:3737']
GOOGLE_SCOPE = 'https://www.googleapis.com/auth/drive.appdata'
# The errors an authorization server names a refused sign-in request by
REFUSALS = ('invalid_client', 'unauthorized_client', 'deleted_client', 'disabled_client',
            'redirect_uri_mismatch', 'invalid_redirect_uri', 'invalid_scope', 'invalid_request')
CI_FILE = 'quire-sync-ci.json'
FASTMAIL_FILES = 'https://myfiles.fastmail.com/'
TIMEOUT = 30


class Failed(Exception):
    """A check that found something wrong"""


def summary(text):
    print(text)
    path = os.environ.get('GITHUB_STEP_SUMMARY')
    if path:
        with open(path, 'a', encoding='utf-8') as out:
            out.write(text + '\n')


def clients_env():
    values = {}
    for line in ENV.read_text().splitlines():
        if line and not line.startswith('#') and '=' in line:
            name, value = line.split('=', 1)
            values[name] = value
    return values


# ---- requests ----

class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


_opener = urllib.request.build_opener(_NoRedirect)


def request(method, url, body=None, headers=None):
    """status, headers and body of one request (redirects not followed);
    an HTTP error status is an answer, not an exception"""
    req = urllib.request.Request(url, data=body, method=method, headers={'User-Agent': 'quire-sync-providers', **(headers or {})})
    try:
        with _opener.open(req, timeout=TIMEOUT) as answer:
            return answer.status, answer.headers, answer.read()
    except urllib.error.HTTPError as answer:
        return answer.code, answer.headers, answer.read()


def follow(url, hosts):
    """The pages a browser would go through from url while they stay on
    hosts: each one's (url, status); the chain ends at a page that is
    not a redirect, or at one to another host (where the provider hands
    the reader back, say)"""
    chain = []
    for _ in range(10):
        status, headers, _ = request('GET', url)
        chain.append((url, status))
        location = headers.get('Location')
        if status not in (301, 302, 303, 307, 308) or not location:
            return chain
        url = urllib.parse.urljoin(url, location)
        if urllib.parse.urlsplit(url).hostname not in hosts:
            chain.append((url, None))
            return chain
    return chain


def refusal_in(url):
    """The refusal a page's address names (an error parameter, or
    Google's error page's authError), or None"""
    parts = urllib.parse.urlsplit(url)
    query = urllib.parse.parse_qs(parts.query)
    fragment = urllib.parse.parse_qs(parts.fragment)
    for found in (query, fragment):
        if 'error' in found:
            return found['error'][0]
    if '/signin/oauth/error' in parts.path or 'authError' in query:
        reason = 'refused'
        for coded in query.get('authError', []):
            try:
                text = base64.urlsafe_b64decode(coded + '=' * (-len(coded) % 4)).decode('utf-8', 'replace')
            except ValueError:
                text = coded
            named = [code for code in REFUSALS if code in text]
            reason = named[0] if named else reason
        return reason
    return None


def judge(name, chain):
    """A sign-in request's chain of pages: ok, refused (a failure) or
    unknown (not reached, or the service failing)"""
    for url, status in chain:
        refused = refusal_in(url)
        if refused:
            return 'refused', f'{refused} (at {urllib.parse.urlsplit(url).netloc}{urllib.parse.urlsplit(url).path})'
        # a bad request is a refused one (Dropbox's answer to a client or
        # redirect address it does not know); a page kept from a robot
        # (403, 429) or a service failing says nothing of the client
        if status == 400:
            return 'refused', f'HTTP {status} from {urllib.parse.urlsplit(url).netloc}{urllib.parse.urlsplit(url).path}'
        if status is not None and status >= 401:
            return 'unknown', f'HTTP {status}'
    return 'ok', f'sign-in page (HTTP {chain[-1][1] if chain[-1][1] is not None else "redirect"})'


# ---- clients ----

def pkce():
    verifier = secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b'=').decode()
    return verifier, challenge


def dropbox_authorize(key, redirect):
    _, challenge = pkce()
    return 'https://www.dropbox.com/oauth2/authorize?' + urllib.parse.urlencode({
        'response_type': 'code', 'token_access_type': 'offline', 'code_challenge_method': 'S256',
        'scope': DROPBOX_SCOPE, 'client_id': key, 'redirect_uri': redirect,
        'code_challenge': challenge, 'state': secrets.token_urlsafe(16)})


def google_authorize(client, origin):
    # as Google's sign-in script asks for a token (its token model): the
    # page's origin, through its storagerelay address
    scheme, host = origin.split('://', 1)
    return 'https://accounts.google.com/o/oauth2/v2/auth?' + urllib.parse.urlencode({
        'client_id': client, 'redirect_uri': f'storagerelay://{scheme}/{host}?id=auth{secrets.randbelow(10**6)}',
        'response_type': 'token', 'scope': GOOGLE_SCOPE, 'include_granted_scopes': 'true', 'prompt': 'consent'})


def clients():
    values = clients_env()
    checks = []
    key = values.get('DROPBOX_CLIENT_ID', '')
    if key:
        for redirect in DROPBOX_REDIRECTS:
            checks.append((f'Dropbox app key, back to `{redirect}`', dropbox_authorize(key, redirect), {'www.dropbox.com'}))
    google = values.get('GOOGLE_WEB_CLIENT_ID', '')
    if google:
        for origin in GOOGLE_ORIGINS:
            checks.append((f'Google web client, from `{origin}`', google_authorize(google, origin), {'accounts.google.com'}))
    summary('## The sync clients, asked for their sign-in pages\n')
    summary('| Client | Answer |\n|---|---|')
    failures = 0
    for name, url, hosts in checks:
        try:
            verdict, said = judge(name, follow(url, hosts))
        except (urllib.error.URLError, OSError) as error:
            verdict, said = 'unknown', f'not reached ({error})'
        if verdict == 'refused':
            failures += 1
            print(f'::error::{name}: {said}')
        elif verdict == 'unknown':
            print(f'::warning::{name}: {said}')
        summary(f'| {name} | {verdict}: {said} |')
    if not checks:
        summary('| (none in scripts/sync-clients.env) | |')
    summary('')
    summary("Google's Android clients are matched by package and signing key, never sent: sync-identity.yml lists them.\n")
    if failures:
        raise Failed(f'{failures} sign-in request(s) refused')


# ---- Fastmail's CORS ----

def fastmail_cors():
    origin = 'https://bats-lang.github.io'
    status, headers, _ = request('OPTIONS', FASTMAIL_FILES, headers={
        'Origin': origin, 'Access-Control-Request-Method': 'PROPFIND',
        'Access-Control-Request-Headers': 'authorization'})
    allowed = headers.get('Access-Control-Allow-Origin')
    summary("## Fastmail's files from a browser\n")
    if allowed in (origin, '*') and 200 <= status < 300:
        summary(f'The preflight answered {status} with `Access-Control-Allow-Origin: {allowed}`: '
                'a browser page can now reach Fastmail, and the Sync screen offers Fastmail in browsers too.\n')
        print('::notice::Fastmail now lets browser pages reach its files (CORS)')
    else:
        summary(f'The preflight answered {status}, with no CORS headers for a page: '
                "browsers still can't reach Fastmail's files, so only the app offers Fastmail.\n")


# ---- round trips ----

def expect(what, status, wanted):
    if status not in wanted:
        raise Failed(f'{what}: HTTP {status}, not {"/".join(str(s) for s in sorted(wanted))}')


def body_of(n):
    return json.dumps({'quire-sync-ci': n, 'nonce': secrets.token_hex(8)}).encode()


def webdav_round_trip(folder, user, password, make_folder):
    """As sync.bats's WebDAV store: GET with the ETag as version, PUT
    If-Match it, 412 for a stale one"""
    auth = {'Authorization': 'Basic ' + base64.b64encode(f'{user}:{password}'.encode()).decode()}
    file = folder + CI_FILE
    if make_folder:
        status, _, _ = request('MKCOL', folder, headers=auth)
        expect('MKCOL the folder', status, {201, 405})
    status, _, _ = request('DELETE', file, headers=auth)
    expect('DELETE a file left over', status, {200, 204, 404})
    first, second, third = body_of(1), body_of(2), body_of(3)
    status, _, _ = request('PUT', file, first, {**auth, 'Content-Type': 'application/json'})
    expect('PUT the file', status, {200, 201, 204})
    status, headers, read = request('GET', file, headers=auth)
    expect('GET it back', status, {200})
    etag = headers.get('ETag')
    if read != first or not etag:
        raise Failed('GET it back: not what was written, or no ETag')
    status, _, _ = request('PUT', file, second, {**auth, 'Content-Type': 'application/json', 'If-Match': etag})
    expect('PUT If-Match the version read', status, {200, 201, 204})
    status, _, _ = request('PUT', file, third, {**auth, 'Content-Type': 'application/json', 'If-Match': etag})
    expect('PUT If-Match a stale version (a conflict)', status, {412})
    status, _, read = request('GET', file, headers=auth)
    if status != 200 or read != second:
        raise Failed('the stale write changed the file')
    status, _, _ = request('DELETE', file, headers=auth)
    expect('DELETE the file', status, {200, 204})


def fastmail_round_trip(env):
    webdav_round_trip(FASTMAIL_FILES + 'quire/', env['FASTMAIL_TEST_USER'], env['FASTMAIL_TEST_APP_PASSWORD'], True)


def nextcloud_round_trip(env):
    server = env['NEXTCLOUD_TEST_URL'].rstrip('/')
    user, password = env['NEXTCLOUD_TEST_USER'], env['NEXTCLOUD_TEST_APP_PASSWORD']
    auth = 'Basic ' + base64.b64encode(f'{user}:{password}'.encode()).decode()
    # the files folder is the user's id's, as the app finds it
    status, _, read = request('GET', server + '/ocs/v2.php/cloud/user?format=json',
                              headers={'Authorization': auth, 'OCS-APIRequest': 'true'})
    expect("the user's id", status, {200})
    user_id = json.loads(read)['ocs']['data']['id']
    folder = f'{server}/remote.php/dav/files/{urllib.parse.quote(user_id)}/'
    webdav_round_trip(folder, user, password, False)


def dropbox_round_trip(env):
    """As dropbox.bats: upload with mode add, then update of the rev
    read (autorename off), a stale rev refused (409, a conflict)"""
    key = clients_env()['DROPBOX_CLIENT_ID']
    status, _, read = request('POST', 'https://api.dropboxapi.com/oauth2/token', urllib.parse.urlencode({
        'grant_type': 'refresh_token', 'refresh_token': env['DROPBOX_TEST_REFRESH_TOKEN'], 'client_id': key}).encode(),
        {'Content-Type': 'application/x-www-form-urlencoded'})
    expect('an access token from the refresh token', status, {200})
    bearer = {'Authorization': 'Bearer ' + json.loads(read)['access_token']}
    path = '/' + CI_FILE

    def api(endpoint, value):
        return request('POST', 'https://api.dropboxapi.com/2/' + endpoint, json.dumps(value).encode(),
                       {**bearer, 'Content-Type': 'application/json'})

    def upload(body, mode):
        arg = json.dumps({'path': path, 'autorename': False, 'mute': True, 'mode': mode})
        return request('POST', 'https://content.dropboxapi.com/2/files/upload', body,
                       {**bearer, 'Content-Type': 'application/octet-stream', 'Dropbox-API-Arg': arg})

    status, _, _ = api('files/delete_v2', {'path': path})
    expect('delete a file left over', status, {200, 409})
    first, second, third = body_of(1), body_of(2), body_of(3)
    status, _, _ = upload(first, 'add')
    expect('upload the file', status, {200})
    status, headers, read = request('POST', 'https://content.dropboxapi.com/2/files/download', b'',
                                    {**bearer, 'Dropbox-API-Arg': json.dumps({'path': path})})
    expect('download it back', status, {200})
    rev = json.loads(headers.get('Dropbox-API-Result', '{}')).get('rev')
    if read != first or not rev:
        raise Failed('download it back: not what was uploaded, or no rev')
    status, _, _ = upload(second, {'.tag': 'update', 'update': rev})
    expect('upload an update of the rev read', status, {200})
    status, _, read = upload(third, {'.tag': 'update', 'update': rev})
    expect('upload an update of a stale rev (a conflict)', status, {409})
    if b'conflict' not in read:
        raise Failed(f'the stale upload was refused, but not as a conflict: {read[:200]!r}')
    status, _, _ = api('files/delete_v2', {'path': path})
    expect('delete the file', status, {200})


def google_round_trip(env):
    """As drive.bats: the file in appDataFolder, its version read again
    just before a write (Drive has no If-Match), so a write since the
    read is a conflict"""
    status, _, read = request('POST', 'https://oauth2.googleapis.com/token', urllib.parse.urlencode({
        'grant_type': 'refresh_token', 'refresh_token': env['GOOGLE_TEST_REFRESH_TOKEN'],
        'client_id': env['GOOGLE_TEST_CLIENT_ID'], 'client_secret': env['GOOGLE_TEST_CLIENT_SECRET']}).encode(),
        {'Content-Type': 'application/x-www-form-urlencoded'})
    expect('an access token from the refresh token', status, {200})
    bearer = {'Authorization': 'Bearer ' + json.loads(read)['access_token']}
    files = 'https://www.googleapis.com/drive/v3/files'
    query = urllib.parse.urlencode({'spaces': 'appDataFolder', 'q': f"name='{CI_FILE}' and trashed=false", 'fields': 'files(id,version)'})
    status, _, read = request('GET', f'{files}?{query}', headers=bearer)
    expect('list the app data folder', status, {200})
    for left in json.loads(read)['files']:
        status, _, _ = request('DELETE', f'{files}/{left["id"]}', headers=bearer)
        expect('delete a file left over', status, {204, 404})

    def version(file_id):
        status, _, read = request('GET', f'{files}/{file_id}?fields=version', headers=bearer)
        expect('read the version', status, {200})
        return json.loads(read)['version']

    first, second = body_of(1), body_of(2)
    boundary = 'quire-sync-part'
    made = (f'--{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'
            + json.dumps({'name': CI_FILE, 'parents': ['appDataFolder']})
            + f'\r\n--{boundary}\r\nContent-Type: application/json\r\n\r\n').encode() + first + f'\r\n--{boundary}--'.encode()
    status, _, read = request('POST', 'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id%2Cversion',
                              made, {**bearer, 'Content-Type': f'multipart/related; boundary={boundary}'})
    expect('create the file', status, {200})
    file_id = json.loads(read)['id']
    status, _, read = request('GET', f'{files}/{file_id}?alt=media', headers=bearer)
    if status != 200 or read != first:
        raise Failed('read it back: not what was written')
    seen = version(file_id)
    # another device's write, after this one's read
    status, _, _ = request('PATCH', f'https://www.googleapis.com/upload/drive/v3/files/{file_id}?uploadType=media',
                           second, {**bearer, 'Content-Type': 'application/json'})
    expect('update the file', status, {200})
    if version(file_id) == seen:
        raise Failed("a write did not change the file's version: a conflict would go unseen")
    status, _, _ = request('DELETE', f'{files}/{file_id}', headers=bearer)
    expect('delete the file', status, {204})


ROUND_TRIPS = [
    ('Fastmail', ('FASTMAIL_TEST_USER', 'FASTMAIL_TEST_APP_PASSWORD'), fastmail_round_trip),
    ('Nextcloud', ('NEXTCLOUD_TEST_URL', 'NEXTCLOUD_TEST_USER', 'NEXTCLOUD_TEST_APP_PASSWORD'), nextcloud_round_trip),
    ('Dropbox', ('DROPBOX_TEST_REFRESH_TOKEN',), dropbox_round_trip),
    ('Google Drive', ('GOOGLE_TEST_CLIENT_ID', 'GOOGLE_TEST_CLIENT_SECRET', 'GOOGLE_TEST_REFRESH_TOKEN'), google_round_trip),
]


def round_trips():
    summary('## Round trips with test accounts\n')
    summary('| Service | Result |\n|---|---|')
    failures = 0
    for name, needs, run in ROUND_TRIPS:
        missing = [need for need in needs if not os.environ.get(need)]
        if missing:
            summary(f'| {name} | skipped: no {", ".join(missing)} |')
            continue
        try:
            run(os.environ)
            summary(f'| {name} | written, read back, a stale write refused, deleted |')
        except (Failed, urllib.error.URLError, OSError, KeyError, ValueError) as error:
            failures += 1
            print(f'::error::{name}: {error}')
            summary(f'| {name} | failed: {error} |')
    summary('')
    if failures:
        raise Failed(f'{failures} round trip(s) failed')


# ---- signing a test account in (a maintainer, once) ----

def dropbox_sign_in():
    key = clients_env()['DROPBOX_CLIENT_ID']
    verifier, challenge = pkce()
    redirect = 'http://localhost:3737/?oauth=dropbox'
    url = 'https://www.dropbox.com/oauth2/authorize?' + urllib.parse.urlencode({
        'response_type': 'code', 'token_access_type': 'offline', 'code_challenge_method': 'S256',
        'scope': DROPBOX_SCOPE, 'client_id': key, 'redirect_uri': redirect, 'code_challenge': challenge})
    print('Open this address, signed in to the Dropbox test account, and allow Quire:\n\n' + url + '\n')
    print('Dropbox then opens http://localhost:3737/?oauth=dropbox&code=... (the page may not load).')
    code = input('Paste that address (or its code) here: ').strip()
    if '://' in code:
        code = urllib.parse.parse_qs(urllib.parse.urlsplit(code).query)['code'][0]
    status, _, read = request('POST', 'https://api.dropboxapi.com/oauth2/token', urllib.parse.urlencode({
        'grant_type': 'authorization_code', 'code': code, 'client_id': key, 'redirect_uri': redirect,
        'code_verifier': verifier}).encode(), {'Content-Type': 'application/x-www-form-urlencoded'})
    expect('the code exchanged', status, {200})
    print('\nDROPBOX_TEST_REFRESH_TOKEN=' + json.loads(read)['refresh_token'])


def google_sign_in():
    client = input('The Desktop test client ID: ').strip()
    secret = input('Its client secret: ').strip()
    verifier, challenge = pkce()
    got = {}

    class Back(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            got.update(urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'Signed in: back to the terminal.')

        def log_message(self, *args):
            pass

    server = http.server.HTTPServer(('127.0.0.1', 0), Back)
    redirect = f'http://127.0.0.1:{server.server_port}/'
    url = 'https://accounts.google.com/o/oauth2/v2/auth?' + urllib.parse.urlencode({
        'client_id': client, 'redirect_uri': redirect, 'response_type': 'code', 'scope': GOOGLE_SCOPE,
        'access_type': 'offline', 'prompt': 'consent', 'code_challenge': challenge, 'code_challenge_method': 'S256'})
    print('Open this address, signed in to the Google test account, and allow it:\n\n' + url + '\n')
    server.handle_request()
    if 'code' not in got:
        raise Failed(f'no code: {got.get("error", ["?"])[0]}')
    status, _, read = request('POST', 'https://oauth2.googleapis.com/token', urllib.parse.urlencode({
        'grant_type': 'authorization_code', 'code': got['code'][0], 'client_id': client, 'client_secret': secret,
        'redirect_uri': redirect, 'code_verifier': verifier}).encode(), {'Content-Type': 'application/x-www-form-urlencoded'})
    expect('the code exchanged', status, {200})
    print('\nGOOGLE_TEST_REFRESH_TOKEN=' + json.loads(read)['refresh_token'])


COMMANDS = {'clients': clients, 'fastmail-cors': fastmail_cors, 'round-trips': round_trips,
            'dropbox-sign-in': dropbox_sign_in, 'google-sign-in': google_sign_in}

if __name__ == '__main__':
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        sys.exit(__doc__)
    try:
        COMMANDS[sys.argv[1]]()
    except Failed as failure:
        sys.exit(f'error: {failure}')
