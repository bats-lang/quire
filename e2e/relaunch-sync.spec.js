// Quitting Quire and opening it again changes nothing (#302), with sync
// on: with no store and with each store sync keeps its file in, after a
// sync, a book read and gone back in opens where it was left, and no
// place is offered (its own place is never another device's). As
// relaunch.spec.js does, each state is captured whole, the app closed
// and opened again in the same browser, and captured again.

import { test, expect, clientsServed, onAndroid } from './fixtures.js';
import { settled, launch, chapterShown, nextChapter, previousChapter, pagesOn, unchanged } from './relaunch.js';
import { webdav, folder, USER, PASSWORD, capacitorPlayed, drive, CLIENT, identityServicesPlayed } from './sync-stores.js';
import { KEY, dropbox } from './dropbox-server.js';
import {
  epubFile, importFiles, openBook, toLibrary, chapters, dialog, librarySettings, settingsButton, settingsScreen,
} from './helpers.js';

const book = { title: 'Kept Book', author: 'Relaunch Tests', chapters: 4, rawChapters: chapters(4, 40) };

// ---- with each store sync keeps its file in, after a sync ----

/** Whether a place another device read is offered: the offer's button
    is there, and not hidden (it shows with the reader's bars) */
const offered = page => page.evaluate(() => [...document.querySelectorAll('button')]
  .some(b => /^Go to /.test(b.textContent) && !b.closest('[data-hide="1"]')));

const panel = page => dialog(page, 'Sync');
const status = page => panel(page).getByRole('status');

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

/** Each store: how the context plays it, and how a reader turns it on
    (none: no store, and in the app the file kept for Auto Backup). A
    Google store (Use Android, Google Drive) keeps its token on the
    device, so the sync made as the app opens again has it (#304) */
const stores = {
  'no store, in a browser': { browser: true, async play() {}, async join() {} },
  'no store, in the app (the file kept for Auto Backup)': {
    async play(context) { await capacitorPlayed(context); },
    async join() {},
  },
  'a WebDAV folder': {
    async play(context) {
      const server = webdav();
      await context.route('**/dav/books/quire-sync.json', server.handle);
    },
    async join(page) {
      await openSync(page);
      await panel(page).getByRole('button', { name: 'WebDAV ›' }).click();
      await panel(page).getByLabel('Folder URL').fill(folder(page));
      await panel(page).getByLabel('User name').fill(USER);
      await panel(page).getByLabel('Password', { exact: true }).fill(PASSWORD);
      await panel(page).getByRole('button', { name: 'Sync with this folder' }).click();
      await expect(status(page)).toHaveText(/^Last synced on /);
      await closeSync(page);
    },
  },
  // (in a browser only for now: the app's sign-in is still to come)
  'Dropbox': {
    browser: true,
    async play(context) {
      const server = dropbox();
      await context.route('https://www.dropbox.com/oauth2/authorize**', server.authorize);
      await context.route('https://api.dropboxapi.com/**', server.api);
      await context.route('https://content.dropboxapi.com/**', server.api);
      await clientsServed(context, { dropboxClient: KEY });
    },
    async join(page) {
      await openSync(page);
      await panel(page).getByRole('button', { name: 'Dropbox ›' }).click();
      await panel(page).getByRole('button', { name: 'Sign in to Dropbox' }).click();
      await page.waitForURL(url => url.searchParams.get('oauth') === 'dropbox' && url.searchParams.has('code'));
      await expect(status(page)).toHaveText(/^Last synced on /);
      await closeSync(page);
    },
  },
  'Google Drive, in a browser': {
    browser: true,
    async play(context) {
      const server = drive();
      await identityServicesPlayed(context);
      await context.route('https://www.googleapis.com/**', server.handle);
      await clientsServed(context, { googleWebClient: CLIENT });
    },
    async join(page) {
      await openSync(page);
      await panel(page).getByRole('button', { name: 'Google Drive ›' }).click();
      await panel(page).getByRole('button', { name: 'Sign in to Google Drive' }).click();
      await expect(status(page)).toHaveText(/^Last synced on /);
      await closeSync(page);
    },
  },
  'Android, in the app': {
    async play(context) {
      const server = drive();
      await capacitorPlayed(context, { token: server.token });
      await context.route('https://www.googleapis.com/**', server.handle);
      await clientsServed(context, { googleWebClient: CLIENT });
    },
    async join(page) {
      await openSync(page);
      await panel(page).getByRole('button', { name: 'Google Drive ›' }).click();
      await panel(page).getByRole('button', { name: 'Use Android' }).click();
      await expect(status(page)).toHaveText(/^Last synced on /);
      await closeSync(page);
    },
  },
};

for (const [name, store] of Object.entries(stores)) {
  test(`with ${name}, after a sync, a book read and gone back in opens where it was, offering nothing`, async ({ context, page }, testInfo) => {
    test.skip(store.browser && onAndroid(testInfo), 'a browser\'s case: in the Android app, the cases of the app run (no store, WebDAV, Use Android)');
    await store.play(context);
    await launch(context, page);
    await importFiles(page, [epubFile(book)], 1);
    await store.join(page);
    await openBook(page, 'Kept Book');
    await nextChapter(page);
    await nextChapter(page);
    await pagesOn(page, 2);
    await previousChapter(page);
    await previousChapter(page);
    expect(await chapterShown(page)).toBe(1);
    page = await unchanged(page);
    expect(await chapterShown(page)).toBe(1);
    // and from the library, the book opened again
    await toLibrary(page);
    page = await unchanged(page, 'killed');
    await openBook(page, 'Kept Book');
    await settled(page);
    expect(await chapterShown(page)).toBe(1);
    expect(await offered(page)).toBe(false);
  });
}
