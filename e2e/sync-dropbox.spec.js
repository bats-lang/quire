// Dropbox (#184): in a browser, sync goes through the reader's Dropbox,
// the file in the app's own folder. The sign-in is OAuth's code flow
// with PKCE (no secret in the app): the page leaves for Dropbox's and
// comes back with a code. Dropbox (its sign-in page, token endpoint and
// files API) is a mock routed in each browser context: no real network.

import { test, expect } from '@playwright/test';
import { createHash } from 'node:crypto';
import {
  epubFile, importFiles, openBook, place, toLibrary, chapters, dialog,
  librarySearch, librarySettings, settingsButton, settingsScreen,
} from './helpers.js';

const KEY = 'quiretestkey1234';

const base64url = bytes => Buffer.from(bytes).toString('base64')
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

/** Dropbox, shared by the devices: its sign-ins, tokens, the file (its
    rev and bytes) and every request made */
function dropbox() {
  const d = {
    file: null, rev: 0, requests: [], uploads: [], revoked: [],
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

  d.authorize = async route => {
    const url = new URL(route.request().url());
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
    return route.fulfill({ status: 200, headers: { 'content-type': 'text/html' },
      body: `<!doctype html><title>Dropbox</title><script>location.replace(${JSON.stringify(back.href)})</script>` });
  };

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

/** A browser with Dropbox routed, and the build's key (none: key '') */
async function device(browser, server, { key = KEY } = {}) {
  const context = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  await context.route('https://www.dropbox.com/oauth2/authorize**', server.authorize);
  await context.route('https://api.dropboxapi.com/**', server.api);
  await context.route('https://content.dropboxapi.com/**', server.api);
  await context.route('**/sync-clients.json', route => route.fulfill({
    status: 200, headers: { 'content-type': 'application/json' }, body: JSON.stringify(key ? { dropboxClient: key } : {}),
  }));
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  await page.goto('/');
  await expect(librarySearch(page)).toBeVisible();
  return { context, page, errors };
}

/** A device's errors, but a Dropbox answer the test made fail, which
    the browser logs */
const unexpected = d => d.errors.filter(e => !/status of (401|409)/.test(e));

const panel = page => dialog(page, 'Sync');
const status = page => panel(page).getByRole('status');
const dropboxButton = page => panel(page).getByRole('button', { name: 'Dropbox' });
const row = page => settingsScreen(page).getByRole('group', { name: 'Sync' }).getByRole('status');

async function openSync(page) {
  await librarySettings(page);
  await settingsButton(page, 'Sync ›').click();
  await expect(panel(page)).toBeVisible();
}

async function closeSync(page) {
  await panel(page).getByRole('button', { name: 'Done' }).click();
  await expect(panel(page)).toBeHidden();
  await settingsButton(page, 'Done').click();
  await expect(settingsScreen(page)).toBeHidden();
}

/** Dropbox, from the library: the page goes to Dropbox's and comes back
    to the sync screen, over Settings, synced */
async function joinDropbox(page) {
  await openSync(page);
  await dropboxButton(page).click();
  await page.waitForURL(url => url.searchParams.get('oauth') === 'dropbox' && url.searchParams.has('code'));
  await expect(status(page)).toHaveText(/^Last synced on /);
  // the code is not left in the address
  expect(new URL(page.url()).search).toBe('');
  await closeSync(page);
}

async function nextChapter(page, chapter) {
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(chapter);
}

const book = { title: 'Shared Book', author: 'Sync Tests', chapters: 4, rawChapters: chapters(4) };

test('Dropbox signs in with PKCE and syncs two browsers through the app folder', async ({ browser }) => {
  const server = dropbox();
  const file = epubFile(book);
  const a = await device(browser, server);
  await importFiles(a.page, [file], 1);
  await openBook(a.page, 'Shared Book');
  await nextChapter(a.page, 2);
  await toLibrary(a.page);
  await openSync(a.page);
  await expect(panel(a.page)).toContainText('in a folder of its own (Apps, then Quire) that only Quire sees');
  await closeSync(a.page);
  await joinDropbox(a.page);
  // the sign-in asked for the app folder's files only, with S256 PKCE
  const origin = new URL(a.page.url()).origin;
  expect(server.authorizations[0]).toMatchObject({
    client_id: KEY, response_type: 'code', token_access_type: 'offline', code_challenge_method: 'S256',
    scope: 'files.content.read files.content.write', redirect_uri: `${origin}/?oauth=dropbox`,
  });
  expect(server.authorizations[0].state).toMatch(/^[A-Za-z0-9_-]{22}$/);
  expect(server.uploads).toEqual(['add']);
  expect(server.json().books).toHaveLength(1);

  const b = await device(browser, server);
  await importFiles(b.page, [file], 1);
  await joinDropbox(b.page);
  // an update of the rev it read
  expect(server.uploads[1]).toEqual({ '.tag': 'update', update: 'rev1' });
  await openBook(b.page, 'Shared Book');
  await expect.poll(async () => (await place(b.page)).ch).toBe(2);
  await toLibrary(b.page);
  await librarySettings(b.page);
  await expect(row(b.page)).toHaveText(/^Dropbox · synced (just now|1 min ago)$/);

  // the access token expires: the refresh token gets another, with no
  // sign-in, and the sync goes on
  server.access.clear();
  await settingsButton(b.page, 'Sync ›').click();
  await panel(b.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(b.page)).toHaveText(/^Last synced on /);

  // another device writes as this one uploads: Dropbox refuses the
  // stale rev, and the file is read and merged again
  const uploads = server.uploads.length;
  server.beforeUpload = () => {
    const other = server.json();
    other.devices = other.devices || [];
    server.write(JSON.stringify(other));
  };
  await panel(b.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(b.page)).toHaveText(/^Last synced on /);
  expect(server.uploads.length).toBe(uploads + 2);

  // Turn off, made final: the grant is given back to Dropbox
  await panel(b.page).getByRole('button', { name: 'Turn off' }).click();
  await expect(status(b.page)).toHaveText('Sync is off.');
  await expect.poll(() => server.revoked.length, { timeout: 15000 }).toBe(1);
  expect(server.refresh.size).toBe(0);
  expect(unexpected(a)).toEqual([]);
  expect(unexpected(b)).toEqual([]);
  await a.context.close();
  await b.context.close();
});

test('a Dropbox sign-in the reader refuses changes nothing, and a code it did not ask for is refused', async ({ browser }) => {
  const server = dropbox();
  const a = await device(browser, server);
  server.answer = 'deny';
  await openSync(a.page);
  await dropboxButton(a.page).click();
  await a.page.waitForURL(url => url.searchParams.get('error') === 'access_denied');
  await expect(status(a.page)).toHaveText('Dropbox sign-in was canceled.');
  expect(new URL(a.page.url()).search).toBe('');
  expect(server.requests).toEqual([]);
  await closeSync(a.page);
  await librarySettings(a.page);
  await expect(row(a.page)).toHaveText('Off');
  await settingsButton(a.page, 'Done').click();

  // a code with a state this page did not send is refused
  server.answer = 'allow';
  server.codes.set('stolen', { challenge: 'x', redirect: `${new URL(a.page.url()).origin}/?oauth=dropbox`, client: KEY });
  await a.page.goto('/?oauth=dropbox&code=stolen&state=AAAAAAAAAAAAAAAAAAAAAA');
  await expect(status(a.page)).toHaveText('Dropbox didn\'t sign Quire in. Try again.');
  expect(server.requests).toEqual([]);
  expect(unexpected(a)).toEqual([]);
  await a.context.close();
});

test('a build with no Dropbox key says Dropbox sync is not set up', async ({ browser }) => {
  const server = dropbox();
  const a = await device(browser, server, { key: '' });
  await openSync(a.page);
  await expect(panel(a.page)).toContainText('Dropbox sync isn\'t set up in this build of Quire.');
  await expect(dropboxButton(a.page)).toBeHidden();
  expect(unexpected(a)).toEqual([]);
  await a.context.close();
});
