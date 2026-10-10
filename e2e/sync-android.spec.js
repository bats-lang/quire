// "Use Android" (#184): in the app, sync goes through the Google account
// on the device, the file in its Drive's app data folder; and with no
// store chosen, the app keeps the file for Android's Auto Backup, which
// a reinstall gives back. Each browser context is a device running the
// app: its Capacitor is played by an init script (GoogleSignIn gives a
// token for the device's account, Filesystem keeps files in a map), and
// Google Drive's API is a mock routed in each (no real network).

import { test, expect, clientsServed } from './fixtures.js';
import {
  epubFile, importFiles, openBook, place, toLibrary, chapters, dialog,
  librarySearch, librarySettings, settingsButton, settingsScreen, libraryShown,
} from './helpers.js';
import { drive, CLIENT, SCOPE, capacitorPlayed, identityServicesPlayed } from './sync-stores.js';

/** A device running the app: Capacitor played, Drive routed, and the
    build's client (none when client is null) */
async function device(browser, server, { mode = 'consent', files = [], client = CLIENT } = {}) {
  const context = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  const { files: kept, google } = await capacitorPlayed(context, { mode, token: server ? server.token : 'token-1', files });
  if (server) await context.route('https://www.googleapis.com/**', server.handle);
  if (server) await context.route('https://oauth2.googleapis.com/revoke', server.revoke);
  await clientsServed(context, client ? { googleWebClient: client } : {});
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  await page.goto('/');
  await expect(libraryShown(page)).toBeVisible();
  return { context, page, errors, files: kept, google };
}

/** A device's errors, but a Drive answer the test made fail, which the
    browser logs */
const unexpected = d => d.errors.filter(e => !/status of (401|404)/.test(e));

const panel = page => dialog(page, 'Sync');
const status = page => panel(page).getByRole('status');
const useAndroid = page => panel(page).getByRole('button', { name: 'Sign in to Google Drive' });
/** The Google Drive row's own step (#331), then its Use Android */
async function chooseAndroid(page) {
  await panel(page).getByRole('button', { name: 'Google Drive', exact: true }).click();
  await useAndroid(page).click();
}
const row = page => settingsScreen(page).getByRole('group', { name: 'Sync' }).getByRole('status');

async function openSync(page) {
  await librarySettings(page);
  await settingsButton(page, 'Sync').click();
  await expect(panel(page)).toBeVisible();
}

async function closeSync(page) {
  await panel(page).getByRole('button', { name: 'Done' }).click();
  await expect(panel(page)).toBeHidden();
  await settingsButton(page, 'Done').click();
  await expect(settingsScreen(page)).toBeHidden();
}

/** Use Android, from the library: synced */
async function joinAndroid(page) {
  await openSync(page);
  await chooseAndroid(page);
  await expect(status(page)).toHaveText(/^Last synced on /);
  await closeSync(page);
}

async function nextChapter(page, chapter) {
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(chapter);
}

/** The page hidden (the app put in the background): a sync */
async function hide(page) {
  await page.evaluate(() => {
    Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
    document.dispatchEvent(new Event('visibilitychange'));
    Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true });
  });
}

const book = { title: 'Shared Book', author: 'Sync Tests', chapters: 4, rawChapters: chapters(4) };

test('Use Android syncs through the app data folder of the device\'s Google account', async ({ browser }) => {
  const server = drive();
  const file = epubFile(book);
  const a = await device(browser, server);
  const b = await device(browser, server);
  // A reads to chapter 3 and turns on Use Android: one sheet, then the
  // file made in the app data folder with its token
  await importFiles(a.page, [file], 1);
  await openBook(a.page, 'Shared Book');
  await nextChapter(a.page, 2);
  await nextChapter(a.page, 3);
  await toLibrary(a.page);
  await joinAndroid(a.page);
  // the first time, Google's consent (authorizeScopes), for drive.appdata
  // alone, and nothing else asked of Google
  expect(a.google.calls).toEqual([{ method: 'authorizeScopes', options: { scopes: [SCOPE] } }]);
  expect(server.file.metadata).toEqual({ name: 'quire-sync.json', parents: ['appDataFolder'] });
  expect(server.json().books[0]).toMatchObject({ chapter: 2, title: 'Shared Book' });
  await librarySettings(a.page);
  await expect(row(a.page)).toHaveText(/^Android · synced (just now|1 min ago)$/);
  await settingsButton(a.page, 'Done').click();
  // B joins: A's place is taken; its write replaces the file's bytes
  await importFiles(b.page, [file], 1);
  await joinAndroid(b.page);
  expect(server.file.version).toBe(2);
  await openBook(b.page, 'Shared Book');
  await expect.poll(async () => (await place(b.page)).ch).toBe(3);
  // a sync the app makes by itself uses the token it has: nothing is
  // asked of Google
  await toLibrary(b.page);
  const before = server.requests.length;
  await hide(b.page);
  await expect.poll(() => server.requests.length).toBeGreaterThan(before);
  expect(b.google.calls.map(c => c.method)).toEqual(['authorizeScopes']);
  expect(unexpected(a)).toEqual([]);
  expect(unexpected(b)).toEqual([]);
  await a.context.close();
  await b.context.close();
});

/** The app opened again (a relaunch): its page loaded anew */
async function reopened(page) {
  await page.reload();
  await expect(libraryShown(page)).toBeVisible();
}

test('opened again, the app syncs with the token it kept, and once its hour is up gets another with nothing shown', async ({ browser }) => {
  const server = drive();
  const a = await device(browser, server);
  await importFiles(a.page, [epubFile(book)], 1);
  await joinAndroid(a.page);
  expect(a.google.calls.map(c => c.method)).toEqual(['authorizeScopes']);
  // opened again: the sync made as it opens has the token, and asks
  // Google nothing
  const asked = server.requests.length;
  await reopened(a.page);
  await expect.poll(() => server.requests.length).toBeGreaterThan(asked);
  await librarySettings(a.page);
  await expect(row(a.page)).toHaveText(/^Android · synced (just now|1 min ago)$/);
  await settingsButton(a.page, 'Done').click();
  expect(a.google.calls.map(c => c.method)).toEqual(['authorizeScopes']);
  // the token's hour is up: Drive refuses it as the app opens again; the
  // refused token is taken out of Play services' cache, and another is
  // given with nothing shown, so the sync goes on
  server.token = a.google.token = 'token-2';
  await reopened(a.page);
  await expect.poll(() => server.accepted.includes('token-2')).toBe(true);
  await librarySettings(a.page);
  await expect(row(a.page)).toHaveText(/^Android · synced (just now|1 min ago)$/);
  expect(a.google.calls.slice(1)).toEqual([
    { method: 'clearAuthorizationToken', options: { accessToken: 'token-1' } },
    { method: 'authorizationForScopes', options: { scopes: [SCOPE] } },
  ]);
  expect(unexpected(a)).toEqual([]);
  await a.context.close();
});

test('access taken back in the Google account pauses sync until Sync now asks for consent again', async ({ browser }) => {
  const server = drive();
  const a = await device(browser, server);
  await importFiles(a.page, [epubFile(book)], 1);
  await joinAndroid(a.page);
  // the reader removes Quire in the Google account's settings: Drive
  // refuses the token, and Google gives none without the reader
  a.google.granted = false;
  server.token = a.google.token = 'token-2';
  await reopened(a.page);
  await librarySettings(a.page);
  await expect(row(a.page)).toHaveText('Android · paused, tap Sync now');
  await settingsButton(a.page, 'Done').click();
  expect(a.google.asked('authorizeScopes')).toHaveLength(1);
  // opened again while paused: the app asks Google with nothing shown,
  // and with no token reaches no Drive, and stays paused
  const requests = server.requests.length;
  const calls = a.google.calls.length;
  await reopened(a.page);
  await hide(a.page);
  await expect.poll(() => a.google.calls.length).toBeGreaterThan(calls);
  await openSync(a.page);
  await expect(status(a.page)).toContainText('Sync paused: tap Sync now to sign in to Google again.');
  expect(server.requests.length).toBe(requests);
  expect(a.google.calls.slice(calls).map(c => c.method).filter(m => m !== 'authorizationForScopes')).toEqual([]);
  // Sync now asks for Google's consent, then syncs
  await panel(a.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  expect(a.google.asked('authorizeScopes')).toHaveLength(2);
  expect(unexpected(a)).toEqual([]);
  await a.context.close();
});

test('a file another device wrote meanwhile is read again and merged', async ({ browser }) => {
  const server = drive();
  const file = epubFile(book);
  const a = await device(browser, server);
  const b = await device(browser, server);
  await importFiles(a.page, [file], 1);
  await joinAndroid(a.page);
  await importFiles(b.page, [file], 1);
  await openBook(b.page, 'Shared Book');
  await nextChapter(b.page, 2);
  await toLibrary(b.page);
  // another write lands between B's read and B's: B's version check
  // sees it, and B reads the file again and merges before it writes
  server.beforeCheck = () => { server.file.version++; };
  const listings = () => server.requests.filter(r => r.startsWith('GET /drive/v3/files?')).length;
  const before = listings();
  await joinAndroid(b.page);
  expect(listings() - before).toBe(2);
  expect(server.json().books[0]).toMatchObject({ chapter: 1, title: 'Shared Book' });
  await a.context.close();
  await b.context.close();
});

test('Use Android is listed only where it can sync, says why it cannot, and Turn off takes the grant back', async ({ browser }) => {
  // in a browser there is no Use Android
  const web = await browser.newContext();
  await clientsServed(web, {});
  const page = await web.newPage();
  await page.goto('/');
  await expect(libraryShown(page)).toBeVisible();
  await openSync(page);
  await expect(useAndroid(page)).toBeHidden();
  // nor, in a build with no client, Google Drive
  await expect(panel(page).getByRole('button', { name: 'Google Drive', exact: true })).toBeHidden();
  await web.close();
  // nor, in an app built without a client, Use Android: a row that
  // could only say it is not set up is not listed
  const bare = await device(browser, null, { client: null });
  await openSync(bare.page);
  await expect(useAndroid(bare.page)).toBeHidden();
  await expect(panel(bare.page)).not.toContainText("isn't set up", { useInnerText: true });
  await bare.context.close();

  const server = drive();
  const a = await device(browser, server, { mode: 'cancel' });
  await openSync(a.page);
  await chooseAndroid(a.page);
  await expect(status(a.page)).toHaveText('Google sign-in was canceled.');
  a.google.mode = 'fail';
  await chooseAndroid(a.page);
  await expect(status(a.page)).toHaveText("Google refused: this build of Quire isn't registered with it. Copy the details and post them in a report. Details: DEVELOPER_ERROR (10)");
  // said in the banner too, over whatever the reader is on (#334)
  await expect(a.page.getByRole('alert')).toContainText('Details: DEVELOPER_ERROR (10)');
  await a.page.getByRole('alert').getByRole('button', { name: 'Dismiss' }).click();
  expect(server.requests).toEqual([]);
  // granted: Use Android syncs
  a.google.mode = 'consent';
  await chooseAndroid(a.page);
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  // Turn off: Undo puts it back, token and all, with nothing asked
  await panel(a.page).getByRole('button', { name: 'Turn off' }).click();
  await expect(status(a.page)).toHaveText('Sync is off.');
  await a.page.getByRole('button', { name: 'Undo' }).click();
  await panel(a.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  expect(a.google.calls.map(c => c.method)).toEqual(['authorizeScopes', 'authorizeScopes', 'authorizeScopes']);
  // Turn off, made final: the grant taken back for the account Google
  // named, and the row says Off
  await panel(a.page).getByRole('button', { name: 'Turn off' }).click();
  await expect(status(a.page)).toHaveText('Sync is off.');
  // the offer stays until it is dismissed (quire#364); made final, it gives the grant back
  await a.page.getByRole('status').filter({ hasText: 'Sync turned off' }).getByRole('button', { name: 'Dismiss' }).click();
  await expect.poll(() => a.google.asked('revokeAccess'), { timeout: 15000 })
    .toEqual([{ account: 'reader@example.com', scopes: [SCOPE] }]);
  expect(server.revoked).toEqual([]);
  await a.page.keyboard.press('Escape');
  await expect(row(a.page)).toHaveText('Off');
  // and opened again, nothing is asked of Google or Drive
  const requests = server.requests.length;
  const calls = a.google.calls.length;
  await reopened(a.page);
  await hide(a.page);
  await librarySettings(a.page);
  await expect(row(a.page)).toHaveText('Off');
  expect(server.requests.length).toBe(requests);
  expect(a.google.calls.length).toBe(calls);
  expect(unexpected(a)).toEqual([]);
  await a.context.close();
});

test('an authorization that names no account takes Drive\'s address, and with none from either, Turn off takes the grant back with the token', async ({ browser }) => {
  // Google names no account: Drive's about gives its address, which
  // Turn off takes the grant back for
  const server = drive();
  server.address = 'drive-reader@example.com';
  const a = await device(browser, server);
  a.google.account = null;
  await openSync(a.page);
  await chooseAndroid(a.page);
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  expect(server.requests).toContain('GET /drive/v3/about?fields=user%2FemailAddress');
  await panel(a.page).getByRole('button', { name: 'Turn off' }).click();
  // the offer stays until it is dismissed (quire#364); made final, it gives the grant back
  await a.page.getByRole('status').filter({ hasText: 'Sync turned off' }).getByRole('button', { name: 'Dismiss' }).click();
  await expect.poll(() => a.google.asked('revokeAccess'), { timeout: 15000 })
    .toEqual([{ account: 'drive-reader@example.com', scopes: [SCOPE] }]);
  expect(server.revoked).toEqual([]);
  expect(unexpected(a)).toEqual([]);
  await a.context.close();
  // nor does Drive give one: Turn off takes the grant back with the
  // token, at Google's revocation endpoint
  const other = drive();
  other.address = null;
  const b = await device(browser, other);
  b.google.account = null;
  await openSync(b.page);
  await chooseAndroid(b.page);
  await expect(status(b.page)).toHaveText(/^Last synced on /);
  await panel(b.page).getByRole('button', { name: 'Turn off' }).click();
  await b.page.getByRole('status').filter({ hasText: 'Sync turned off' }).getByRole('button', { name: 'Dismiss' }).click();
  await expect.poll(() => other.revoked, { timeout: 15000 }).toEqual(['token-1']);
  expect(b.google.asked('revokeAccess')).toEqual([]);
  expect(unexpected(b)).toEqual([]);
  await b.context.close();
});

test('with no store chosen, the app keeps the file for Auto Backup, and a reinstall merges it', async ({ browser }) => {
  const file = epubFile(book);
  const a = await device(browser, null);
  await importFiles(a.page, [file], 1);
  await openBook(a.page, 'Shared Book');
  await nextChapter(a.page, 2);
  await nextChapter(a.page, 3);
  await toLibrary(a.page);
  // the app put in the background: the file written where Auto Backup
  // keeps it, and nothing asked of Google
  await hide(a.page);
  const backedUp = () => {
    const data = a.files.get('backup/quire-sync.json');
    return data ? JSON.parse(Buffer.from(data, 'base64').toString()) : null;
  };
  // (opening the book synced too, at its start: the file is the merge
  // as last written)
  await expect.poll(async () => (((await backedUp()) || { books: [] }).books[0] || {}).chapter).toBe(2);
  expect((await backedUp()).books).toEqual([expect.objectContaining({ title: 'Shared Book' })]);
  expect(a.google.calls).toEqual([]);
  // Sync stays off
  await librarySettings(a.page);
  await expect(row(a.page)).toHaveText('Off');
  const files = [...a.files.entries()];
  await a.context.close();
  // reinstalled: Auto Backup gave the file back; the book, imported
  // again, opens at its place
  const b = await device(browser, null, { files });
  await importFiles(b.page, [file], 1);
  await openBook(b.page, 'Shared Book');
  await expect.poll(async () => (await place(b.page)).ch).toBe(3);
  expect(unexpected(b)).toEqual([]);
  await b.context.close();
});

/** A browser: Google's script and Drive routed, and the build's client */
async function browserDevice(browser, server) {
  const context = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  await identityServicesPlayed(context);
  await context.route('https://www.googleapis.com/**', server.handle);
  await clientsServed(context, { googleWebClient: CLIENT });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  await page.goto('/');
  await expect(libraryShown(page)).toBeVisible();
  return { context, page, errors };
}

test('in a browser, Google Drive syncs through the same app data folder, an hour at a time', async ({ browser }) => {
  const server = drive();
  const file = epubFile(book);
  // the app's device writes the file; the browser joins it
  const phone = await device(browser, server);
  await importFiles(phone.page, [file], 1);
  await openBook(phone.page, 'Shared Book');
  await nextChapter(phone.page, 2);
  await toLibrary(phone.page);
  await joinAndroid(phone.page);
  await phone.context.close();

  const web = await browserDevice(browser, server);
  await importFiles(web.page, [file], 1);
  await openSync(web.page);
  await expect(useAndroid(web.page)).toBeHidden();
  // (its row, then its step's Sign in to Google Drive: one name holds both)
  const googleDrive = panel(web.page).getByRole('button', { name: 'Google Drive' });
  await googleDrive.click();
  await expect(panel(web.page)).toContainText('Google signs you in for an hour at a time');
  // the reader closes Google's window: nothing is asked of Drive
  await web.page.evaluate(() => { window.__gis.closed = true; });
  const asked = server.requests.length;
  await googleDrive.click();
  await expect(status(web.page)).toHaveText('Google sign-in was canceled.');
  expect(server.requests.length).toBe(asked);
  await web.page.evaluate(() => { window.__gis.closed = false; });
  await googleDrive.click();
  await googleDrive.click();
  await expect(status(web.page)).toHaveText(/^Last synced on /);
  expect(await web.page.evaluate(() => window.__gis.clients[0])).toEqual({ client_id: CLIENT, scope: 'https://www.googleapis.com/auth/drive.appdata' });
  await closeSync(web.page);
  await openBook(web.page, 'Shared Book');
  await expect.poll(async () => (await place(web.page)).ch).toBe(2);
  await toLibrary(web.page);
  await librarySettings(web.page);
  await expect(row(web.page)).toHaveText(/^Google Drive · synced (just now|1 min ago)$/);
  // the hour is up: Drive refuses the token, and Sync now asks Google again
  server.token = 'token-2';
  await web.page.evaluate(() => { window.__gis.token = 'token-2'; });
  await settingsButton(web.page, 'Sync').click();
  await panel(web.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(web.page)).toContainText('Sync paused: tap Sync now to sign in to Google again.');
  await panel(web.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(web.page)).toHaveText(/^Last synced on /);
  expect(await web.page.evaluate(() => window.__gis.requests)).toBe(3);
  // Turn off revokes the token
  await panel(web.page).getByRole('button', { name: 'Turn off' }).click();
  await expect(status(web.page)).toHaveText('Sync is off.');
  expect(await web.page.evaluate(() => window.__gis.revoked)).toEqual(['token-2']);
  expect(unexpected(web)).toEqual([]);
  await web.context.close();
});

test('in a browser opened again, Google Drive syncs with the token it kept; once Drive refuses it, sync is paused until Sync now', async ({ browser }) => {
  const server = drive();
  const web = await browserDevice(browser, server);
  await importFiles(web.page, [epubFile(book)], 1);
  await openSync(web.page);
  await panel(web.page).getByRole('button', { name: 'Google Drive', exact: true }).click();
  await panel(web.page).getByRole('button', { name: 'Sign in to Google Drive' }).click();
  await expect(status(web.page)).toHaveText(/^Last synced on /);
  await closeSync(web.page);
  // opened again: the sync made as it opens has the token, and opens
  // no Google window (a page may open one only at a tap)
  let asked = server.requests.length;
  await reopened(web.page);
  await expect.poll(() => server.requests.length).toBeGreaterThan(asked);
  await librarySettings(web.page);
  await expect(row(web.page)).toHaveText(/^Google Drive · synced (just now|1 min ago)$/);
  await settingsButton(web.page, 'Done').click();
  expect(await web.page.evaluate(() => window.__gis.requests)).toBe(0);
  // the hour is up: paused, said in the Sync row and on its screen
  server.token = 'token-2';
  await reopened(web.page);
  await librarySettings(web.page);
  await expect(row(web.page)).toHaveText('Google Drive · paused, tap Sync now');
  await settingsButton(web.page, 'Done').click();
  // opened again while paused: nothing is tried, nothing changes
  asked = server.requests.length;
  await reopened(web.page);
  await hide(web.page);
  await openSync(web.page);
  await expect(status(web.page)).toContainText('Sync paused: tap Sync now to sign in to Google again.');
  expect(server.requests.length).toBe(asked);
  expect(await web.page.evaluate(() => window.__gis.requests)).toBe(0);
  // one tap: Sync now asks Google (its window), then syncs
  await web.page.evaluate(() => { window.__gis.token = 'token-2'; });
  await panel(web.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(web.page)).toHaveText(/^Last synced on /);
  expect(await web.page.evaluate(() => window.__gis.requests)).toBe(1);
  expect(unexpected(web)).toEqual([]);
  await web.context.close();
});
