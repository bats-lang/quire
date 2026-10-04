// Dropbox (#184): in a browser, sync goes through the reader's Dropbox,
// the file in the app's own folder. The sign-in is OAuth's code flow
// with PKCE (no secret in the app): the page leaves for Dropbox's and
// comes back with a code. Dropbox (its sign-in page, token endpoint and
// files API) is a mock routed in each browser context: no real network.

import { test, expect, clientsServed, fastmailStubbed, fastmailRefused } from './fixtures.js';
import { KEY, dropbox } from './dropbox-server.js';
import {
  epubFile, importFiles, openBook, place, toLibrary, chapters, dialog,
  librarySearch, librarySettings, settingsButton, settingsScreen,
} from './helpers.js';

/** A browser with Dropbox routed, and the build's key (none: key '') */
async function device(browser, server, { key = KEY } = {}) {
  const context = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  await fastmailStubbed(context);
  await context.route('https://www.dropbox.com/oauth2/authorize**', server.authorize);
  await context.route('https://api.dropboxapi.com/**', server.api);
  await context.route('https://content.dropboxapi.com/**', server.api);
  await clientsServed(context, key ? { dropboxClient: key } : {});
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error' && !fastmailRefused(m)) errors.push('console: ' + m.text()); });
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
