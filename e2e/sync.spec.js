// Sync between devices: two browser contexts are two devices, and a
// WebDAV folder is a mock routed in both (no real network): GET gives
// the file and its ETag, PUT honours If-Match (412 when the file
// changed) and keeps what it is sent.

import { test, expect, googleStubbed } from './fixtures.js';
import { readFileSync, writeFileSync } from 'node:fs';
import {
  start, epubFile, importFiles, openBook, place, toLibrary, chapters, dialog, menuItem, libraryMenu,
  selectText, selectionButton, showChrome, control, clickControl, oneColumn, pageShown, cards,
  librarySettings, settingsButton, settingsScreen, restoreInput,
} from './helpers.js';

/** The WebDAV folder: on the page's own origin, whatever port the
    suite is served on (a request to another origin would be
    cross-origin, and read as one the server does not let in) */
const folder = page => new URL('/dav/books/', page.url()).href;
const USER = 'reader';
const PASSWORD = 'app-pass-4417';

/** A WebDAV folder holding quire-sync.json, shared by the devices */
function webdav() {
  const server = {
    body: null, version: 0, gets: 0, puts: 0,
    // a test's interference: the status every request gets, a network
    // failure, a missing folder, a write of another device's before
    // the next PUT
    status: null, offline: false, noFolder: false, putStatus: null, beforePut: null,
  };
  server.handle = async route => {
    const request = route.request();
    if (server.offline) return route.abort('internetdisconnected');
    if (server.status) return route.fulfill({ status: server.status, body: '' });
    const expected = 'Basic ' + Buffer.from(`${USER}:${PASSWORD}`).toString('base64');
    if (request.headers().authorization !== expected) return route.fulfill({ status: 401, body: '' });
    if (request.method() === 'GET') {
      server.gets++;
      if (server.body === null) return route.fulfill({ status: 404, body: '' });
      return route.fulfill({ status: 200, body: server.body, headers: { ETag: `"v${server.version}"` } });
    }
    if (request.method() === 'PUT') {
      server.puts++;
      if (server.noFolder) return route.fulfill({ status: 409, body: '' });
      if (server.putStatus) return route.fulfill({ status: server.putStatus, body: '' });
      if (server.beforePut) { const write = server.beforePut; server.beforePut = null; write(); }
      const match = request.headers()['if-match'];
      if (match !== undefined && match !== `"v${server.version}"`) return route.fulfill({ status: 412, body: '' });
      server.body = request.postData();
      server.version++;
      return route.fulfill({ status: 201, body: '' });
    }
    return route.fulfill({ status: 405, body: '' });
  };
  server.json = () => JSON.parse(server.body);
  return server;
}

/** A device: a browser context of its own, the folder routed in it */
async function device(browser, server, time) {
  const context = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  await googleStubbed(context);
  await context.route('**/dav/books/quire-sync.json', server.handle);
  const page = await context.newPage();
  if (time) await page.clock.install({ time });
  const errors = await start(page);
  return { context, page, errors };
}

/** A device's errors, but the 404 of a file not there yet, which the
    browser logs */
const unexpected = d => d.errors.filter(e => !/status of 404/.test(e));

const panel = page => dialog(page, 'Sync');
const status = page => panel(page).getByRole('status');

/** Opens the sync panel from Settings, opened from the library menu */
async function openSync(page) {
  await librarySettings(page);
  await settingsButton(page, 'Sync ›').click();
  await expect(panel(page)).toBeVisible();
}

/** Closes the sync panel with its Done, then Settings with its own */
async function closeSync(page) {
  await panel(page).getByRole('button', { name: 'Done' }).click();
  await expect(panel(page)).toBeHidden();
  await settingsButton(page, 'Done').click();
  await expect(settingsScreen(page)).toBeHidden();
}

/** Sync set up, and a first sync: the folder, user name and password */
async function setUp(page, password = PASSWORD) {
  await openSync(page);
  await panel(page).getByLabel('Folder URL').fill(folder(page));
  await panel(page).getByLabel('User name').fill(USER);
  await panel(page).getByLabel('Password').fill(password);
  await panel(page).getByRole('button', { name: 'Sync now' }).click();
}

/** Sync set up and done, its screen closed */
async function joinSync(page) {
  await setUp(page);
  await expect(status(page)).toHaveText(/^Last synced on /);
  await closeSync(page);
}

/** A sync from the library, done */
async function syncNow(page) {
  if (!(await panel(page).isVisible())) await openSync(page);
  await panel(page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(page)).toHaveText(/^Last synced on /);
  await closeSync(page);
}

/** The page hidden (the app put in the background): a sync */
async function hide(page) {
  await page.evaluate(() => {
    Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
    document.dispatchEvent(new Event('visibilitychange'));
    Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true });
  });
}

async function nextChapter(page, chapter) {
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(chapter);
}

const annotations = page => dialog(page, 'Annotations');
async function openAnnotations(page) {
  await clickControl(page, 'Annotations');
  await expect(annotations(page)).toBeVisible();
}
async function closeAnnotations(page) {
  await annotations(page).getByRole('button', { name: 'Close' }).click();
  await expect(annotations(page)).toBeHidden();
}

// (its contents name each of its 4 chapters)
const book = { title: 'Shared Book', author: 'Sync Tests', chapters: 4, rawChapters: chapters(4) };

test('the furthest place is taken, and offered for a book that is open', async ({ browser }) => {
  const server = webdav();
  const file = epubFile(book);
  const a = await device(browser, server);
  const b = await device(browser, server);
  // A reads to chapter 3 and syncs
  await importFiles(a.page, [file], 1);
  await openBook(a.page, 'Shared Book');
  await nextChapter(a.page, 2);
  await nextChapter(a.page, 3);
  await toLibrary(a.page);
  await joinSync(a.page);
  expect(server.json().books[0]).toMatchObject({ chapter: 2, title: 'Shared Book' });
  // B has the book at its start: a sync takes A's place
  await importFiles(b.page, [file], 1);
  await joinSync(b.page);
  await openBook(b.page, 'Shared Book');
  await expect.poll(async () => (await place(b.page)).ch).toBe(3);
  // A reads on; B, reading, is offered A's place rather than moved
  await openBook(a.page, 'Shared Book');
  await expect.poll(async () => (await place(a.page)).ch).toBe(3);
  await nextChapter(a.page, 4);
  await toLibrary(a.page);
  await syncNow(a.page);
  await hide(b.page);
  const go = b.page.getByRole('button', { name: 'Go to the furthest place (chapter 4)' });
  await expect(go).toBeVisible();
  expect((await place(b.page)).ch).toBe(3);
  await go.click();
  await expect.poll(async () => (await place(b.page)).ch).toBe(4);
  await expect(go).toBeHidden();
  expect(unexpected(a)).toEqual([]);
  expect(unexpected(b)).toEqual([]);
  await a.context.close();
  await b.context.close();
});

test('annotations made on each device are merged; a deletion and the later of two notes win', async ({ browser }) => {
  const server = webdav();
  const file = epubFile(book);
  const time = new Date('2026-06-01T10:00:00Z');
  const a = await device(browser, server, time);
  const b = await device(browser, server, time);
  for (const d of [a, b]) {
    await importFiles(d.page, [file], 1);
    await joinSync(d.page);
    await openBook(d.page, 'Shared Book');
  }
  // a highlight on each
  await selectText(a.page, 0, 8);
  await selectionButton(a.page, 'Highlight').click();
  await selectText(b.page, 10, 20);
  await selectionButton(b.page, 'Highlight').click();
  for (const d of [a, b, a]) {
    await toLibrary(d.page);
    await syncNow(d.page);
    await openBook(d.page, 'Shared Book');
  }
  for (const d of [a, b]) {
    await openAnnotations(d.page);
    await expect(annotations(d.page).getByRole('button', { name: 'Delete' })).toHaveCount(2);
    await closeAnnotations(d.page);
  }
  expect(server.json().books[0].annotations).toHaveLength(2);

  // a note on the first on each: B's is the later
  await openAnnotations(a.page);
  await annotations(a.page).getByRole('button', { name: 'Add note' }).first().click();
  await dialog(a.page, 'Note').getByRole('textbox', { name: 'Note' }).fill('Note from A');
  await dialog(a.page, 'Note').getByRole('button', { name: 'Save' }).click();
  await closeAnnotations(a.page);
  await a.page.clock.fastForward('02:00');
  await b.page.clock.fastForward('02:00');
  await openAnnotations(b.page);
  await annotations(b.page).getByRole('button', { name: 'Add note' }).first().click();
  await dialog(b.page, 'Note').getByRole('textbox', { name: 'Note' }).fill('Note from B');
  await dialog(b.page, 'Note').getByRole('button', { name: 'Save' }).click();
  await closeAnnotations(b.page);
  for (const d of [a, b, a]) {
    await toLibrary(d.page);
    await syncNow(d.page);
    await openBook(d.page, 'Shared Book');
  }
  for (const d of [a, b]) {
    await openAnnotations(d.page);
    await expect(annotations(d.page)).toContainText('Note from B');
    await expect(annotations(d.page)).not.toContainText('Note from A');
    await closeAnnotations(d.page);
  }

  // A deletes the second; the deletion reaches B
  await openAnnotations(a.page);
  await annotations(a.page).getByRole('button', { name: 'Delete' }).nth(1).click();
  await expect(annotations(a.page).getByRole('button', { name: 'Delete' })).toHaveCount(1);
  await closeAnnotations(a.page);
  for (const d of [a, b]) {
    await toLibrary(d.page);
    await syncNow(d.page);
    await openBook(d.page, 'Shared Book');
  }
  await openAnnotations(b.page);
  await expect(annotations(b.page).getByRole('button', { name: 'Delete' })).toHaveCount(1);
  await expect(annotations(b.page)).toContainText('Note from B');
  const synced = server.json().books[0];
  expect(synced.annotations).toHaveLength(1);
  expect(synced.deleted).toHaveLength(1);
  expect(unexpected(a)).toEqual([]);
  expect(unexpected(b)).toEqual([]);
  await a.context.close();
  await b.context.close();
});

test('a write another device made first is read again and merged (412)', async ({ browser }) => {
  const server = webdav();
  const a = await device(browser, server);
  await importFiles(a.page, [epubFile(book)], 1);
  await setUp(a.page);
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  const written = server.json();
  // another device writes between this one's read and its write
  server.beforePut = () => {
    const other = JSON.parse(server.body);
    other.devices.push({ device: 7, readingLog: [], books: [] });
    server.body = JSON.stringify(other);
    server.version++;
  };
  const gets = server.gets, puts = server.puts;
  await panel(a.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  expect(server.gets - gets).toBe(2);
  expect(server.puts - puts).toBe(2);
  // the other device's write is kept
  expect(server.json().devices.map(d => d.device)).toContain(7);
  expect(server.json().books).toHaveLength(written.books.length);
  await a.context.close();
});

test('a sync that fails says why, and changes nothing here', async ({ browser }) => {
  const server = webdav();
  const file = epubFile(book);
  const a = await device(browser, server);
  const b = await device(browser, server);
  await importFiles(a.page, [file], 1);
  await openBook(a.page, 'Shared Book');
  await nextChapter(a.page, 2);
  await toLibrary(a.page);
  await joinSync(a.page);

  await importFiles(b.page, [file], 1);
  // a wrong password
  await setUp(b.page, 'not-the-password');
  await expect(status(b.page)).toContainText('The user name or password is wrong.');
  // the folder missing (its file can be read, it cannot be written)
  await panel(b.page).getByLabel('Password').fill(PASSWORD);
  server.putStatus = 403;
  await panel(b.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(b.page)).toContainText('The user name or password is wrong.');
  server.putStatus = null;
  server.noFolder = true;
  await panel(b.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(b.page)).toContainText("The folder wasn't found.");
  server.noFolder = false;
  // no network
  server.offline = true;
  await panel(b.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(b.page)).toContainText("Can't reach the server.");
  server.offline = false;
  // the file was read each time, but nothing of it was taken
  await closeSync(b.page);
  await openBook(b.page, 'Shared Book');
  expect((await place(b.page)).ch).toBe(1);
  await toLibrary(b.page);
  await syncNow(b.page);
  await openBook(b.page, 'Shared Book');
  await expect.poll(async () => (await place(b.page)).ch).toBe(2);
  await a.context.close();
  await b.context.close();
});

test('the folder, user name and password are kept on the device, never in a backup', async ({ browser }) => {
  const server = webdav();
  const a = await device(browser, server);
  await importFiles(a.page, [epubFile(book)], 1);
  await joinSync(a.page);
  await librarySettings(a.page);
  const download = a.page.waitForEvent('download');
  await settingsButton(a.page, 'Export backup').click();
  const json = readFileSync(await (await download).path(), 'utf8');
  expect(json).not.toContain(PASSWORD);
  expect(json).not.toContain('dav/books');
  // kept across a reload
  await a.page.reload();
  await expect(cards(a.page)).toHaveCount(1);
  await openSync(a.page);
  await expect(panel(a.page).getByLabel('Folder URL')).toHaveValue(folder(a.page));
  await expect(panel(a.page).getByLabel('Password')).toHaveValue(PASSWORD);
  // turned off, and back with Undo
  await panel(a.page).getByRole('button', { name: 'Turn off' }).click();
  await expect(status(a.page)).toHaveText('Sync is off.');
  await expect(panel(a.page).getByLabel('Password')).toHaveValue('');
  await a.page.getByRole('button', { name: 'Undo' }).click();
  await expect(panel(a.page).getByLabel('Password')).toHaveValue(PASSWORD);
  await a.context.close();
});

// Turns n pages, a minute apart
async function readMinutes(page, n) {
  for (let k = 0; k < n; k++) {
    const before = await place(page);
    await page.clock.fastForward('01:00');
    await page.keyboard.press('ArrowRight');
    await expect.poll(async () => JSON.stringify(await place(page))).not.toBe(JSON.stringify(before));
  }
}

test('the minutes read on each device are summed', async ({ browser }) => {
  const server = webdav();
  const file = epubFile({ ...book, chapters: 3, rawChapters: chapters(3, 60) });
  const time = new Date('2026-06-01T10:00:00Z');
  const a = await device(browser, server, time);
  const b = await device(browser, server, time);
  for (const [d, minutes] of [[a, 3], [b, 2]]) {
    await importFiles(d.page, [file], 1);
    await openBook(d.page, 'Shared Book');
    await oneColumn(d.page);
    await readMinutes(d.page, minutes);
    await toLibrary(d.page);
  }
  await joinSync(a.page);
  await joinSync(b.page);
  await syncNow(a.page);
  for (const d of [a, b]) {
    await libraryMenu(d.page);
    await menuItem(d.page, 'Reading statistics').click();
    await expect(d.page.locator('#stats-today')).toHaveText('5 min');
    await d.page.keyboard.press('Escape');
  }
  expect(server.json().devices).toHaveLength(2);
  await a.context.close();
  await b.context.close();
});

test('annotations from before ids, restored on two devices from one backup, sync without duplicates', async ({ browser }, testInfo) => {
  const server = webdav();
  const file = epubFile(book);
  const a = await device(browser, server);
  const b = await device(browser, server);
  await importFiles(a.page, [file], 1);
  await openBook(a.page, 'Shared Book');
  await selectText(a.page, 0, 8);
  await selectionButton(a.page, 'Note').click();
  await dialog(a.page, 'Note').getByRole('textbox', { name: 'Note' }).fill('An old note');
  await dialog(a.page, 'Note').getByRole('button', { name: 'Save' }).click();
  await toLibrary(a.page);
  await librarySettings(a.page);
  const download = a.page.waitForEvent('download');
  await settingsButton(a.page, 'Export backup').click();
  const backup = JSON.parse(readFileSync(await (await download).path(), 'utf8'));
  await settingsButton(a.page, 'Done').click();
  // as a version before ids wrote it
  for (const kept of backup.books) for (const n of kept.annotations) { delete n.id; delete n.modified; }
  const path = testInfo.outputPath('old-backup.json');
  writeFileSync(path, JSON.stringify(backup));
  for (const d of [a, b]) {
    if (d === b) await importFiles(b.page, [file], 1);
    await librarySettings(d.page);
    await restoreInput(d.page).setInputFiles([path]);
    await expect(dialog(d.page, 'Backup restored')).toBeVisible();
    await dialog(d.page, 'Backup restored').getByRole('button').first().click();
  }
  await joinSync(a.page);
  await joinSync(b.page);
  await syncNow(a.page);
  expect(server.json().books[0].annotations).toHaveLength(1);
  for (const d of [a, b]) {
    await openBook(d.page, 'Shared Book');
    await pageShown(d.page);
    await openAnnotations(d.page);
    await expect(annotations(d.page).getByRole('button', { name: 'Delete' })).toHaveCount(1);
    await expect(annotations(d.page)).toContainText('An old note');
  }
  await a.context.close();
  await b.context.close();
});

test('the Settings screen\'s Sync row says whether sync is on, and when it last synced', async ({ browser }) => {
  const server = webdav();
  const a = await device(browser, server, new Date('2026-06-01T10:00:00Z'));
  const row = settingsScreen(a.page).getByRole('group', { name: 'Sync' }).getByRole('status');
  await librarySettings(a.page);
  await expect(row).toHaveText('Off');
  await settingsButton(a.page, 'Done').click();
  await joinSync(a.page);
  await librarySettings(a.page);
  await expect(row).toHaveText(/^WebDAV · synced (just now|1 min ago)$/);
  await settingsButton(a.page, 'Done').click();
  await a.page.clock.fastForward('02:00');
  await librarySettings(a.page);
  await expect(row).toHaveText(/^WebDAV · synced [23] min ago$/);
  // a failure says why, in short
  server.status = 401;
  await settingsButton(a.page, 'Sync ›').click();
  await panel(a.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(a.page)).toContainText('The user name or password is wrong.');
  await a.page.keyboard.press('Escape');
  await expect(row).toHaveText('Wrong user name or password');
  // turned off, it says so
  server.status = null;
  await settingsButton(a.page, 'Sync ›').click();
  await panel(a.page).getByRole('button', { name: 'Turn off' }).click();
  await a.page.keyboard.press('Escape');
  await expect(row).toHaveText('Off');
  await a.context.close();
});
