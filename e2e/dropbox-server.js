// Dropbox, played for the e2e tests (#184): its sign-in page, token
// endpoint (which checks the PKCE verifier against the challenge) and
// files API, shared by the devices of a test. No real network.

import { createHash } from 'node:crypto';

export const KEY = 'quiretestkey1234';

const base64url = bytes => Buffer.from(bytes).toString('base64')
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

/** Dropbox, shared by the devices: its sign-ins, tokens, the file (its
    rev and bytes) and every request made */
export function dropbox() {
  const d = {
    file: null, rev: 0, requests: [], uploads: [], revoked: [],
    // each code exchanged for tokens, in order
    exchanged: [],
    // the sign-in page's answer: 'allow' or 'deny'
    answer: 'allow',
    // codes given, by code: { challenge, redirect }
    codes: new Map(),
    // access tokens Dropbox takes, refresh tokens it holds
    access: new Set(), refresh: new Set(), counter: 0,
    // a test's interference: another device's write, made just before
    // the app's upload
    beforeUpload: null,
    authorizations: [],
  };
  const cors = {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'authorization, content-type, dropbox-api-arg',
    'access-control-allow-methods': 'POST',
    'access-control-expose-headers': 'dropbox-api-result',
  };
  const json = (route, body, status = 200) =>
    route.fulfill({ status, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const conflict = (route, summary) => json(route, { error_summary: summary, error: { '.tag': 'path' } }, 409);
  const metadata = () => ({ name: 'quire-sync.json', path_display: '/quire-sync.json', rev: `rev${d.rev}`, size: d.file.length });

  d.write = body => { d.file = body; d.rev++; };

  // Where Dropbox's sign-in page at the address authorize sends the
  // reader back to: the redirect, with a code (or the reader's no) and
  // the state
  d.back = authorize => {
    const url = new URL(authorize);
    const parameters = Object.fromEntries(url.searchParams);
    d.authorizations.push(parameters);
    const back = new URL(parameters.redirect_uri);
    if (d.answer === 'deny') {
      back.searchParams.set('error', 'access_denied');
      back.searchParams.set('error_description', 'The user chose not to give your app access to their Dropbox account.');
    } else {
      const code = `code-${++d.counter}`;
      d.codes.set(code, { challenge: parameters.code_challenge, redirect: parameters.redirect_uri, client: parameters.client_id });
      back.searchParams.set('code', code);
    }
    back.searchParams.set('state', parameters.state);
    return back.href;
  };

  d.authorize = async route => route.fulfill({ status: 200, headers: { 'content-type': 'text/html' },
    body: `<!doctype html><title>Dropbox</title><script>location.replace(${JSON.stringify(d.back(route.request().url()))})</script>` });

  d.api = async route => {
    const request = route.request();
    if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors });
    const url = new URL(request.url());
    d.requests.push(`${request.method()} ${url.pathname}`);
    if (url.pathname === '/oauth2/token') {
      const form = new URLSearchParams(request.postData());
      if (form.get('client_id') !== KEY) return json(route, { error: 'invalid_client' }, 400);
      if (form.has('client_secret')) return json(route, { error: 'a secret in a public client' }, 400);
      const access = `access-${++d.counter}`;
      if (form.get('grant_type') === 'authorization_code') {
        const given = d.codes.get(form.get('code'));
        d.exchanged.push(form.get('code'));
        d.codes.delete(form.get('code'));
        if (!given || given.redirect !== form.get('redirect_uri')) return json(route, { error: 'invalid_grant' }, 400);
        const challenge = base64url(createHash('sha256').update(form.get('code_verifier') || '').digest());
        if (challenge !== given.challenge) return json(route, { error: 'invalid_grant', error_description: 'invalid code verifier' }, 400);
        const refresh = `refresh-${d.counter}`;
        d.access.add(access);
        d.refresh.add(refresh);
        return json(route, { access_token: access, token_type: 'bearer', expires_in: 14400, refresh_token: refresh,
          scope: 'files.content.read files.content.write', uid: '1', account_id: 'dbid:test' });
      }
      if (form.get('grant_type') === 'refresh_token') {
        if (!d.refresh.has(form.get('refresh_token'))) return json(route, { error: 'invalid_grant' }, 400);
        d.access.add(access);
        return json(route, { access_token: access, token_type: 'bearer', expires_in: 14400 });
      }
      return json(route, { error: 'unsupported_grant_type' }, 400);
    }
    const token = (request.headers().authorization || '').replace(/^Bearer /, '');
    if (!d.access.has(token)) return json(route, { error_summary: 'expired_access_token/', error: { '.tag': 'expired_access_token' } }, 401);
    if (url.pathname === '/2/auth/token/revoke') {
      d.revoked.push(token);
      d.access.clear();
      d.refresh.clear();
      return route.fulfill({ status: 200, headers: { ...cors, 'content-type': 'application/json' }, body: 'null' });
    }
    const argument = JSON.parse(request.headers()['dropbox-api-arg'] || '{}');
    if (argument.path !== '/quire-sync.json') return conflict(route, 'path/malformed_path/');
    if (url.pathname === '/2/files/download') {
      if (d.file === null) return conflict(route, 'path/not_found/..');
      return route.fulfill({ status: 200,
        headers: { ...cors, 'content-type': 'application/octet-stream', 'dropbox-api-result': JSON.stringify(metadata()) },
        body: d.file });
    }
    if (url.pathname === '/2/files/upload') {
      if (d.beforeUpload) { const other = d.beforeUpload; d.beforeUpload = null; other(); }
      d.uploads.push(argument.mode);
      const mode = argument.mode;
      const fresh = mode === 'add' || (mode && mode['.tag'] === 'add');
      if (fresh && d.file !== null) return conflict(route, 'path/conflict/file/..');
      if (!fresh && !(mode && mode['.tag'] === 'update' && d.file !== null && mode.update === `rev${d.rev}`))
        return conflict(route, 'path/conflict/file/..');
      d.write(request.postData());
      return json(route, metadata());
    }
    return json(route, { error_summary: 'not found' }, 404);
  };
  d.json = () => JSON.parse(d.file);
  return d;
}
