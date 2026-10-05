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
  librarySearch, librarySettings, settingsButton, settingsScreen,
} from './helpers.js';
import { drive, CLIENT, capacitorPlayed, identityServicesPlayed } from './sync-stores.js';

/** A device running the app: Capacitor played, Drive routed, and the
    build's client (none when client is null) */
async function device(browser, server, { mode = 'token', files = [], client = CLIENT } = {}) {
  const context = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  const kept = await capacitorPlayed(context, { mode, token: server ? server.token : 'token-1', files });
  if (server) await context.route('https://www.googleapis.com/**', server.handle);
  await clientsServed(context, client ? { googleWebClient: client } : {});
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  await page.goto('/');
  await expect(librarySearch(page)).toBeVisible();
  return { context, page, errors, files: kept };
}

/** A device's errors, but a Drive answer the test made fail, which the
    browser logs */
const unexpected = d => d.errors.filter(e => !/status of (401|404)/.test(e));

const panel = page => dialog(page, 'Sync');
const status = page => panel(page).getByRole('status');
const useAndroid = page => panel(page).getByRole('button', { name: 'Use Android' });
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

/** Use Android, from the library: synced */
async function joinAndroid(page) {
  await openSync(page);
  await useAndroid(page).click();
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
  const google = await a.page.evaluate(() => window.__google);
  expect(google.signIns).toBe(1);
  expect(google.initialized[0]).toEqual({ clientId: CLIENT, scopes: ['https://www.googleapis.com/auth/drive.appdata'] });
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
  // a sync the app makes by itself uses the token it has: no sheet
  await toLibrary(b.page);
  const before = server.requests.length;
  await hide(b.page);
  await expect.poll(() => server.requests.length).toBeGreaterThan(before);
  expect(await b.page.evaluate(() => window.__google.signIns)).toBe(1);
  expect(unexpected(a)).toEqual([]);
  expect(unexpected(b)).toEqual([]);
  await a.context.close();
  await b.context.close();
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

test('Use Android is listed only where it can sync, says why it cannot, and Turn off signs out', async ({ browser }) => {
  // in a browser there is no Use Android
  const web = await browser.newContext();
  await clientsServed(web, {});
  const page = await web.newPage();
  await page.goto('/');
  await expect(librarySearch(page)).toBeVisible();
  await openSync(page);
  await expect(useAndroid(page)).toBeHidden();
  // nor, in a build with no client, Google Drive
  await expect(panel(page).getByRole('button', { name: 'Google Drive' })).toBeHidden();
  await web.close();
  // nor, in an app built without a client, Use Android: a row that
  // could only say it is not set up is not listed
  const bare = await device(browser, null, { client: null });
  await openSync(bare.page);
  await expect(useAndroid(bare.page)).toBeHidden();
  await expect(panel(bare.page)).not.toContainText("isn't set up", { useInnerText: true });
  await bare.context.close();

  const server = drive();
  const a = await device(browser, server, { mode: 'none' });
  await openSync(a.page);
  await useAndroid(a.page).click();
  await expect(status(a.page)).toHaveText('Android sync needs a Google account on this device.');
  await a.page.evaluate(() => { window.__google.mode = 'cancel'; });
  await useAndroid(a.page).click();
  await expect(status(a.page)).toHaveText('Google sign-in was canceled.');
  expect(server.requests).toEqual([]);
  // signed in; the token Drive stops taking asks for a sign-in again
  await a.page.evaluate(() => { window.__google.mode = 'token'; });
  await useAndroid(a.page).click();
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  server.token = 'token-2';
  await panel(a.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(a.page)).toContainText('Tap Sync now to sign in to Google again.');
  await a.page.evaluate(() => { window.__google.token = 'token-2'; });
  await panel(a.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  expect(await a.page.evaluate(() => window.__google.signIns)).toBe(4);
  // Turn off: signed out, and the row says Off
  await panel(a.page).getByRole('button', { name: 'Turn off' }).click();
  await expect(status(a.page)).toHaveText('Sync is off.');
  expect(await a.page.evaluate(() => window.__google.signOuts)).toBe(1);
  await a.page.keyboard.press('Escape');
  await expect(row(a.page)).toHaveText('Off');
  expect(unexpected(a)).toEqual([]);
  await a.context.close();
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
  expect(await a.page.evaluate(() => window.__google.signIns)).toBe(0);
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
  await expect(librarySearch(page)).toBeVisible();
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
  const googleDrive = panel(web.page).getByRole('button', { name: 'Google Drive' });
  await expect(panel(web.page)).toContainText('Google signs you in for an hour at a time');
  // the reader closes Google's window: nothing is asked of Drive
  await web.page.evaluate(() => { window.__gis.closed = true; });
  const asked = server.requests.length;
  await googleDrive.click();
  await expect(status(web.page)).toHaveText('Google sign-in was canceled.');
  expect(server.requests.length).toBe(asked);
  await web.page.evaluate(() => { window.__gis.closed = false; });
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
  await settingsButton(web.page, 'Sync ›').click();
  await panel(web.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(web.page)).toContainText('Tap Sync now to sign in to Google again.');
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
