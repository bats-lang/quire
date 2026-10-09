// Sync between devices: two browser contexts are two devices, and a
// WebDAV folder is a mock routed in both (no real network): GET gives
// the file and its ETag, PUT honours If-Match (412 when the file
// changed) and keeps what it is sent.

import { test, expect, googleStubbed } from './fixtures.js';
import { readFileSync, writeFileSync } from 'node:fs';
import {
  start, epubFile, importFiles, openBook, place, toLibrary, chapters, dialog, menuItem, libraryMenu,
  selectText, selectionButton, showChrome, control, clickControl, oneColumn, pageShown, cards,
  librarySettings, settingsButton, settingsScreen, restoreInput, exportedBackup, reload, jumpBack,
} from './helpers.js';
import { webdav, folder, USER, PASSWORD } from './sync-stores.js';

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
  await settingsButton(page, 'Sync').click();
  await expect(panel(page)).toBeVisible();
}

/** Closes the sync panel with its Done, then Settings with its own */
async function closeSync(page) {
  await panel(page).getByRole('button', { name: 'Done' }).click();
  await expect(panel(page)).toBeHidden();
  await settingsButton(page, 'Done').click();
  await expect(settingsScreen(page)).toBeHidden();
}

/** The WebDAV row's own step (#331): its fields and its button */
async function webdavStep(page) {
  await panel(page).getByRole('button', { name: 'WebDAV', exact: true }).click();
  await expect(panel(page).getByLabel('Folder URL')).toBeVisible();
}

/** Sync set up, and a first sync: the folder, user name and password */
async function setUp(page, password = PASSWORD) {
  await openSync(page);
  await webdavStep(page);
  await panel(page).getByLabel('Folder URL').fill(folder(page));
  await panel(page).getByLabel('User name').fill(USER);
  await panel(page).getByLabel('Password', { exact: true }).fill(password);
  await panel(page).getByRole('button', { name: 'Sign in to WebDAV' }).click();
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

/** The offer of a place another device read: its button, shown with
    the reader's bars */
const offer = (page, chapter) =>
  page.getByRole('button', { name: `Go to where you were on another device (chapter ${chapter})` });

/** Whether any place is offered: the offer's button there, its row not
    hidden */
const offered = page => page.evaluate(() => [...document.querySelectorAll('button')]
  .some(b => /^Go to /.test(b.textContent) && !b.closest('[data-hide="1"]')));

/** The page hidden, and the sync it starts ended */
async function hiddenSynced(d, server) {
  const puts = server.puts;
  await hide(d.page);
  await expect.poll(() => server.puts).toBeGreaterThan(puts);
  await d.page.waitForTimeout(300);
}

test('the latest place is taken, and offered for a book that is open', async ({ browser }) => {
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
  await hiddenSynced(b, server);
  expect((await place(b.page)).ch).toBe(3);
  await showChrome(b.page);
  await expect(offer(b.page, 4)).toBeVisible();
  await offer(b.page, 4).click();
  await expect.poll(async () => (await place(b.page)).ch).toBe(4);
  expect(await offered(b.page)).toBe(false);
  expect(unexpected(a)).toEqual([]);
  expect(unexpected(b)).toEqual([]);
  await a.context.close();
  await b.context.close();
});

test('another device\'s place is offered once; dismissed, only a later one of its is offered, backwards too', async ({ browser }) => {
  const server = webdav();
  const file = epubFile(book);
  const a = await device(browser, server);
  const b = await device(browser, server);
  for (const d of [a, b]) {
    await importFiles(d.page, [file], 1);
    await joinSync(d.page);
  }
  // A reads at the start; B reads to chapter 3 and syncs
  await openBook(a.page, 'Shared Book');
  await openBook(b.page, 'Shared Book');
  await nextChapter(b.page, 2);
  await nextChapter(b.page, 3);
  await hiddenSynced(b, server);
  // A, reading, is offered B's place, and dismisses it
  await hiddenSynced(a, server);
  await showChrome(a.page);
  await expect(offer(a.page, 3)).toBeVisible();
  await a.page.getByRole('button', { name: 'Dismiss' }).click();
  expect(await offered(a.page)).toBe(false);
  expect((await place(a.page)).ch).toBe(1);
  // not offered again: by a sync, by the book closed and opened (its
  // place not taken either), by the app opened again
  await hiddenSynced(a, server);
  expect(await offered(a.page)).toBe(false);
  await toLibrary(a.page);
  await syncNow(a.page);
  await openBook(a.page, 'Shared Book');
  await a.page.waitForTimeout(1000);
  expect(await offered(a.page)).toBe(false);
  expect((await place(a.page)).ch).toBe(1);
  await reload(a.page);
  await pageShown(a.page);
  await a.page.waitForTimeout(1000);
  expect(await offered(a.page)).toBe(false);
  expect((await place(a.page)).ch).toBe(1);
  // B reads on: that place is offered, once
  await nextChapter(b.page, 4);
  await hiddenSynced(b, server);
  await hiddenSynced(a, server);
  await showChrome(a.page);
  await expect(offer(a.page, 4)).toBeVisible();
  await a.page.getByRole('button', { name: 'Dismiss' }).click();
  // B goes back to chapter 2, later than anything A did: offered too
  await jumpTo(b.page, 'Chapter 2');
  await hiddenSynced(b, server);
  await hiddenSynced(a, server);
  await showChrome(a.page);
  await expect(offer(a.page, 2)).toBeVisible();
  await offer(a.page, 2).click();
  await expect.poll(async () => (await place(a.page)).ch).toBe(2);
  expect(unexpected(a)).toEqual([]);
  expect(unexpected(b)).toEqual([]);
  await a.context.close();
  await b.context.close();
});

/** A jump to the chapter named title, from the contents */
async function jumpTo(page, title) {
  await clickControl(page, 'Contents');
  const contents = dialog(page, 'Contents');
  await expect(contents).toBeVisible();
  await contents.getByRole('tabpanel', { name: 'Contents' }).getByRole('button', { name: title, exact: true }).click();
  await expect(contents).toBeHidden();
}

test('a jump to a far chapter and back leaves no far place: not after a reopen, a sync or a restore', async ({ browser }, testInfo) => {
  const server = webdav();
  const file = epubFile(book);
  const a = await device(browser, server);
  await importFiles(a.page, [file], 1);
  await joinSync(a.page);
  await openBook(a.page, 'Shared Book');
  // a jump to the last chapter, and back
  await jumpTo(a.page, 'Chapter 4');
  await expect.poll(async () => (await place(a.page)).ch).toBe(4);
  await expect(jumpBack(a.page)).toBeVisible();
  await jumpBack(a.page).click();
  await expect.poll(async () => (await place(a.page)).ch).toBe(1);
  await hiddenSynced(a, server);
  expect(server.json().books[0].chapter).toBe(0);
  // reopened
  await reload(a.page);
  await pageShown(a.page);
  await a.page.waitForTimeout(1000);
  expect((await place(a.page)).ch).toBe(1);
  expect(await offered(a.page)).toBe(false);
  // synced from the library, and opened
  await toLibrary(a.page);
  await syncNow(a.page);
  await openBook(a.page, 'Shared Book');
  expect((await place(a.page)).ch).toBe(1);
  await toLibrary(a.page);
  // a backup, restored
  await librarySettings(a.page);
  const path = testInfo.outputPath('backup.json');
  writeFileSync(path, await exportedBackup(a.page));
  expect(JSON.parse(readFileSync(path, 'utf8')).books[0].chapter).toBe(0);
  await restoreInput(a.page).setInputFiles([path]);
  await expect(dialog(a.page, 'Backup restored')).toBeVisible();
  await dialog(a.page, 'Backup restored').getByRole('button').first().click();
  await expect(settingsScreen(a.page)).toBeHidden();
  await openBook(a.page, 'Shared Book');
  expect((await place(a.page)).ch).toBe(1);
  expect(unexpected(a)).toEqual([]);
  await a.context.close();
});

test('two places changed at once: the further one is kept, on each device', async ({ browser }) => {
  const server = webdav();
  const file = epubFile(book);
  const a = await device(browser, server);
  await importFiles(a.page, [file], 1);
  await openBook(a.page, 'Shared Book');
  await nextChapter(a.page, 2);
  await toLibrary(a.page);
  await joinSync(a.page);
  const written = server.json().books[0];
  expect(written).toMatchObject({ chapter: 1 });
  expect(written.placeModified).toBeGreaterThan(0);
  // another device's change at the same stamp, behind: this one's is kept
  const other = (chapter) => {
    const file = server.json();
    Object.assign(file.books[0], { chapter, page: 0, anchor: -1, placeDevice: 1 });
    server.body = JSON.stringify(file);
    server.version++;
  };
  other(0);
  await syncNow(a.page);
  expect(server.json().books[0]).toMatchObject({ chapter: 1 });
  await openBook(a.page, 'Shared Book');
  expect((await place(a.page)).ch).toBe(2);
  await toLibrary(a.page);
  // at the same stamp, further: that one is taken
  other(2);
  await syncNow(a.page);
  expect(server.json().books[0]).toMatchObject({ chapter: 2 });
  await openBook(a.page, 'Shared Book');
  expect((await place(a.page)).ch).toBe(3);
  expect(unexpected(a)).toEqual([]);
  await a.context.close();
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
  await webdavStep(b.page);
  await panel(b.page).getByLabel('Password', { exact: true }).fill(PASSWORD);
  server.putStatus = 403;
  await panel(b.page).getByRole('button', { name: 'Sign in to WebDAV' }).click();
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
  const json = await exportedBackup(a.page);
  expect(json).not.toContain(PASSWORD);
  expect(json).not.toContain('dav/books');
  // kept across a reload
  await a.page.reload();
  await expect(cards(a.page)).toHaveCount(1);
  await openSync(a.page);
  await expect(panel(a.page).getByLabel('Folder URL')).toHaveValue(folder(a.page));
  await expect(panel(a.page).getByLabel('Password', { exact: true })).toHaveValue(PASSWORD);
  // turned off, and back with Undo
  await panel(a.page).getByRole('button', { name: 'Turn off' }).click();
  await expect(status(a.page)).toHaveText('Sync is off.');
  await expect(panel(a.page).getByLabel('Password', { exact: true })).toHaveValue('');
  await a.page.getByRole('button', { name: 'Undo' }).click();
  await expect(panel(a.page).getByLabel('Password', { exact: true })).toHaveValue(PASSWORD);
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
  const backup = JSON.parse(await exportedBackup(a.page));
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
  await settingsButton(a.page, 'Sync').click();
  await panel(a.page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(a.page)).toContainText('The user name or password is wrong.');
  await a.page.keyboard.press('Escape');
  await expect(row).toHaveText('Wrong user name or password');
  // turned off, it says so
  server.status = null;
  await settingsButton(a.page, 'Sync').click();
  await panel(a.page).getByRole('button', { name: 'Turn off' }).click();
  await a.page.keyboard.press('Escape');
  await expect(row).toHaveText('Off');
  await a.context.close();
});
