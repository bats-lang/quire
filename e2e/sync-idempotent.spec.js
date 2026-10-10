// Sync is idempotent on the page, not only in the list (#429). Sony's
// reader duplicated every highlight on each sync, and Kobo's vanished
// from the book after one while still listed: so what a sync leaves is
// looked at in the three places it can be wrong in, the file, the list
// of annotations and the ranges painted over the page (::highlight
// (bats-mark-n), as annotations.spec.js counts them), on both devices,
// after one sync, after many with nothing changed, through every store
// the suite plays, and after a sync that was cut short.
//
// Two browser contexts are two devices (sync-devices.js), each with its
// clock fixed. A device that joins a store while another has, in the app
// (which keeps the Auto Backup file from its first sync), the same
// minute for its number would be taken for it, so the second device
// is a minute on.

import { test, expect } from './fixtures.js';
import { writeFileSync } from 'node:fs';
import {
  epubFile, dialog, librarySettings, settingsButton, restoreInput, exportedBackup,
} from './helpers.js';
import {
  book, NOON, minutesLater, clockFixed, stores, sync, hiddenSync, hide, importFiles, openBook, toLibrary,
  highlight, shown, agree, inBook, reopen, changedPaths, withoutStamps, unexpected, annotationsDialog,
} from './sync-devices.js';
import { clickControl } from './helpers.js';

const LATER = minutesLater(NOON, 1);
const FIRST = 'Para 1.0';
const SECOND = 'orem ipsum';

/** Two devices of one store, each holding the book, signed in, and the
    book open on both */
async function twoDevices(browser, store, file) {
  const server = store.make();
  const a = await store.device(browser, server, NOON);
  const b = await store.device(browser, server, LATER);
  for (const d of [a, b]) {
    await importFiles(d.page, [file], 1);
    await store.join(d, server);
  }
  return { server, a, b };
}

async function closeBoth(...devices) {
  for (const d of devices) await d.context.close();
}

/** What a device shows, the list and the page agreeing */
async function showing(d) {
  const view = await shown(d.page);
  agree(view);
  return view;
}

async function deleteFirstListed(page) {
  await clickControl(page, 'Annotations');
  await expect(annotationsDialog(page)).toBeVisible();
  await annotationsDialog(page).getByRole('button', { name: 'Delete' }).first().click();
  await annotationsDialog(page).getByRole('button', { name: 'Close' }).click();
  await expect(annotationsDialog(page)).toBeHidden();
}

test('after a sync every listed highlight is painted on its page, on both devices, and one deleted elsewhere is gone from the page', async ({ browser }) => {
  const store = stores.webdav;
  const { server, a, b } = await twoDevices(browser, store, epubFile(book));
  for (const d of [a, b]) await openBook(d.page, 'Shared Book');
  await highlight(a.page, 0, 8);
  await highlight(b.page, 10, 20);
  // both are reading: the sync arrives while the book is open, and the
  // other device's highlight is painted on the page shown, with no
  // book reopened (hidden: the app's own sync point, in the book)
  for (const d of [a, b, a]) await hiddenSync(store, server, d);
  for (const d of [a, b]) {
    const view = await showing(d);
    expect(view.quotes).toEqual([FIRST, SECOND]);
    expect(view.painted).toHaveLength(2);
  }
  // and opened again from the library
  for (const d of [a, b]) {
    await toLibrary(d.page);
    await openBook(d.page, 'Shared Book');
    expect((await showing(d)).quotes).toEqual([FIRST, SECOND]);
  }
  expect(server.json().books[0].annotations).toHaveLength(2);

  // A deletes the first; the deletion reaches B, which has the book
  // open: it leaves B's list and B's page
  await deleteFirstListed(a.page);
  expect((await showing(a)).quotes).toEqual([SECOND]);
  for (const d of [a, b]) await hiddenSync(store, server, d);
  await expect.poll(async () => (await shown(b.page)).painted.length).toBe(1);
  const afterDelete = await showing(b);
  expect(afterDelete.quotes).toEqual([SECOND]);
  expect(afterDelete.painted[0]).toMatch(/: orem ipsum$/);
  expect(server.json().books[0].annotations).toHaveLength(1);
  expect(server.json().books[0].deleted).toHaveLength(1);
  // opened again, and synced once more: still gone, not brought back
  await toLibrary(b.page);
  await sync(store, server, b);
  await openBook(b.page, 'Shared Book');
  expect((await showing(b)).quotes).toEqual([SECOND]);
  await hiddenSync(store, server, a);
  expect((await showing(a)).quotes).toEqual([SECOND]);
  expect(unexpected(a)).toEqual([]);
  expect(unexpected(b)).toEqual([]);
  await closeBoth(a, b);
});

test('sync now ten times and the app\'s own sync points a dozen times with nothing changed leave the file, the list and the page as they were', async ({ browser }) => {
  test.setTimeout(300000);
  const store = stores.webdav;
  const { server, a, b } = await twoDevices(browser, store, epubFile(book));
  for (const d of [a, b]) await openBook(d.page, 'Shared Book');
  await highlight(a.page, 0, 8);
  await highlight(b.page, 10, 20);
  for (const d of [a, b, a, b]) await hiddenSync(store, server, d);
  const reference = await showing(a);
  expect(reference.quotes).toEqual([FIRST, SECOND]);
  expect(await showing(b)).toEqual(reference);
  await toLibrary(a.page);

  // Sync now, ten times, a minute apart (so a stamp that moved with the
  // clock would show): after the first the bytes are the same, all of
  // them, for the file keeps no time of the sync itself
  await sync(store, server, a);
  const settled = server.body;
  const settledFile = server.json();
  for (let n = 1; n <= 10; n++) {
    await clockFixed(a.page, minutesLater(NOON, 10 + n));
    await sync(store, server, a);
    expect(changedPaths(settledFile, server.json()), `after Sync now ${n}`).toEqual([]);
    expect(server.body, `after Sync now ${n}`).toBe(settled);
  }
  await openBook(a.page, 'Shared Book');
  expect(await showing(a)).toEqual(reference);

  // The app's own sync points, a dozen: the page hidden, the app opened
  // again, a book opened. The reader's own acts are dated (opening a
  // book stamps it "opened", the library's order; reading time and
  // places are not touched while nothing is read), so those are what may
  // move, and only they: listed here, and asserted
  const allowed = ['books.0.opened'];
  const kinds = ['hidden', 'reopened', 'book opened'];
  for (let n = 0; n < 12; n++) {
    const kind = kinds[n % 3];
    await clockFixed(a.page, minutesLater(NOON, 30 + n));
    const requests = store.requests(server);
    if (kind === 'hidden') {
      await inBook(a.page);
      await hiddenSync(store, server, a);
    } else if (kind === 'reopened') {
      await reopen(a);
      await expect.poll(() => store.requests(server)).toBeGreaterThan(requests);
      await inBook(a.page);
    } else {
      await toLibrary(a.page);
      await openBook(a.page, 'Shared Book');
      await expect.poll(() => store.requests(server)).toBeGreaterThan(requests);
    }
    // no waiting for the layout to settle: a sync while the book is
    // laid out again (_settle in src/reader.bats) sends the pages and
    // place as left, not as counted so far (#448)
    if (kind !== 'hidden') await hiddenSync(store, server, a);
    await a.page.waitForTimeout(300);
    const moved = changedPaths(settledFile, server.json());
    expect(moved.filter(path => !allowed.includes(path)), `after ${kind} (${n + 1})`).toEqual([]);
    // the annotations themselves are never touched
    expect(server.json().books[0].annotations, `after ${kind} (${n + 1})`).toEqual(settledFile.books[0].annotations);
    expect(server.json().books[0].deleted).toEqual([]);
    expect(server.json().devices.length).toBe(settledFile.devices.length);
    expect(await showing(a), `after ${kind} (${n + 1})`).toEqual(reference);
  }
  // the other device, after all that: the same list and page
  await hiddenSync(store, server, b);
  expect(await showing(b)).toEqual(reference);
  expect(server.json().books[0].annotations).toHaveLength(2);
  expect(unexpected(a)).toEqual([]);
  expect(unexpected(b)).toEqual([]);
  await closeBoth(a, b);
});

test('the device named for a place never dated is not changed by the other device syncing (#448)', async ({ browser }) => {
  test.setTimeout(120000);
  const store = stores.webdav;
  const { server, a, b } = await twoDevices(browser, store, epubFile(book));
  for (const d of [a, b]) await openBook(d.page, 'Shared Book');
  await hiddenSync(store, server, a);
  const first = server.json().books[0];
  expect(first.placeModified, 'the place was never dated').toBe(0);
  for (const d of [b, a, b, a]) {
    await hiddenSync(store, server, d);
    const kept = server.json().books[0];
    expect(kept.placeModified).toBe(0);
    expect(kept.placeDevice, 'placeDevice of a place never dated').toBe(first.placeDevice);
  }
  await closeBoth(a, b);
});

/** A backup of a device that has made one highlight, as a file */
async function backupFile(device, testInfo) {
  await toLibrary(device.page);
  await librarySettings(device.page);
  const path = testInfo.outputPath('backup.json');
  writeFileSync(path, await exportedBackup(device.page));
  await settingsButton(device.page, 'Done').click();
  return path;
}

async function restored(page, path) {
  await librarySettings(page);
  await restoreInput(page).setInputFiles([path]);
  await expect(dialog(page, 'Backup restored')).toBeVisible();
  await dialog(page, 'Backup restored').getByRole('button').first().click();
}

/** Two devices that restored the same backup (one highlight, "Para
    1.0"), then each made one new highlight on the same sentence (the
    same characters), synced both ways. a's clock is at NOON; b's is at
    `minute` */
async function sameBackupSameSentence(browser, testInfo, minute) {
  const store = stores.webdav;
  const file = epubFile(book);
  const server = store.make();
  const a = await store.device(browser, server, NOON);
  const b = await store.device(browser, server, minute);
  for (const d of [a, b]) await importFiles(d.page, [file], 1);
  await openBook(a.page, 'Shared Book');
  await highlight(a.page, 0, 8);
  const path = await backupFile(a, testInfo);
  for (const d of [a, b]) await restored(d.page, path);
  for (const d of [a, b]) await store.join(d, server);
  for (const d of [a, b]) {
    await openBook(d.page, 'Shared Book');
    expect((await showing(d)).quotes).toEqual([FIRST]);
    await highlight(d.page, 10, 20);
  }
  for (const d of [a, b, a, b]) await hiddenSync(store, server, d);
  return { server, a, b };
}

// An annotation's id is the SHA-256 of what never changes in it (its
// kind, chapter, start, end and the minute it was made), so what two
// devices made is one annotation when all of that is the same and two
// when the minute is not. Decided by research: no comparable reader
// documents it (KOReader keeps a datetime in each highlight, and its
// HighlightSync plugin merges by latest timestamp, which cannot tell a
// second act from the first's copy either; searched for Readwise, Kindle
// and Kobo too and found no account of two highlights of one passage made
// by two devices); and the rule the spec of ids gives (CLAUDE.md, Sync)
// is the one tested: a highlight made twice in one minute on one passage
// is a double tap, not two highlights (and a sync that finds the same
// thing twice must not double it), and made in different minutes it is
// two acts, both kept, never merged away.
test('two devices that restored one backup and each highlighted the same sentence in the same minute: one new highlight, and the backup\'s, none doubled', async ({ browser }, testInfo) => {
  const { server, a, b } = await sameBackupSameSentence(browser, testInfo, NOON);
  expect(server.json().books[0].annotations).toHaveLength(2);
  for (const d of [a, b]) {
    const view = await showing(d);
    expect(view.quotes).toEqual([FIRST, SECOND]);
    expect(view.painted).toHaveLength(2);
  }
  await closeBoth(a, b);
});

test('two devices that restored one backup and each highlighted the same sentence in different minutes: two new highlights and the backup\'s, none doubled', async ({ browser }, testInfo) => {
  const { server, a, b } = await sameBackupSameSentence(browser, testInfo, LATER);
  const ids = server.json().books[0].annotations.map(annotation => annotation.id);
  expect(new Set(ids).size).toBe(3);
  for (const d of [a, b]) {
    const view = await showing(d);
    expect(view.quotes).toEqual([FIRST, SECOND, SECOND]);
    expect(view.painted).toHaveLength(3);
  }
  // and nothing more however often it is synced
  const settled = server.body;
  for (const d of [a, b, a, b]) await hiddenSync(stores.webdav, server, d);
  expect(server.body).toBe(settled);
  for (const d of [a, b]) expect((await showing(d)).quotes).toEqual([FIRST, SECOND, SECOND]);
  await closeBoth(a, b);
});

// ---- the same merge through each store ----

test.describe('the same merge through every store gives the same file', () => {
  test.describe.configure({ mode: 'serial' });
  const file = epubFile(book);
  /** each store's file, without the stamps */
  const files = {};

  for (const [key, store] of Object.entries(stores)) {
    test(`${store.name}`, async ({ browser }) => {
      test.setTimeout(150000);
      const server = store.make();
      const a = await store.device(browser, server, NOON);
      await importFiles(a.page, [file], 1);
      await store.join(a, server);
      await openBook(a.page, 'Shared Book');
      await highlight(a.page, 0, 8);
      await toLibrary(a.page);
      let b;
      if (store.shared) {
        b = await store.device(browser, server, LATER);
        await importFiles(b.page, [file], 1);
        await store.join(b, server);
      } else {
        // a reinstall: Auto Backup gave back the file the first one kept
        await hiddenSync(store, server, a);
        b = await store.device(browser, server, LATER, [...a.files.entries()]);
        await importFiles(b.page, [file], 1);
      }
      await openBook(b.page, 'Shared Book');
      await highlight(b.page, 10, 20);
      await toLibrary(b.page);
      await sync(store, server, b);
      if (store.shared) await sync(store, server, a);
      const text = store.bytes(server, b);
      const parsed = JSON.parse(text);
      expect(parsed.books).toHaveLength(1);
      expect(parsed.books[0].annotations.map(annotation => annotation.text)).toEqual([FIRST, SECOND]);
      expect(parsed.devices).toHaveLength(2);
      files[key] = withoutStamps(text);
      // the same again, however often
      await sync(store, server, b);
      expect(withoutStamps(store.bytes(server, b))).toBe(files[key]);
      // what each device shows
      for (const d of store.shared ? [a, b] : [b]) {
        await openBook(d.page, 'Shared Book');
        expect((await showing(d)).quotes).toEqual([FIRST, SECOND]);
      }
      expect(unexpected(a)).toEqual([]);
      expect(unexpected(b)).toEqual([]);
      await closeBoth(a, b);
    });
  }

  test('they are the same file, byte for byte apart from the devices\' stamps', () => {
    expect(Object.keys(files)).toEqual(Object.keys(stores));
    for (const key of Object.keys(files)) expect(files[key], `${stores[key].name} against WebDAV`).toBe(files.webdav);
  });
});

// ---- a sync cut short ----

/** A device on a WebDAV folder, its PUT interfered with by the test:
    `fate.next` is 'abort' (the request fails, nothing reaches the
    folder), 'lost' (the folder takes the file and the answer is lost),
    or 'hold' (the request never answers, the page goes away) */
async function cuttable(browser, server, time) {
  const fate = { next: null, seen: 0 };
  const store = stores.webdav;
  const d = await store.device(browser, server, time);
  await d.context.route('**/dav/books/quire-sync.json', async route => {
    const request = route.request();
    if (request.method() !== 'PUT' || !fate.next) return server.handle(route);
    const how = fate.next;
    fate.next = null;
    fate.seen++;
    if (how === 'abort') return route.abort('failed');
    if (how === 'lost') {
      // the folder takes it, as a PUT the answer to which never came
      server.body = request.postData();
      server.version++;
      server.puts++;
      return route.abort('connectionreset');
    }
    return new Promise(() => {});
  });
  return Object.assign(d, { fate });
}

/** The control: the same device doing the same without being cut short */
async function uncut(browser, file) {
  const store = stores.webdav;
  const server = store.make();
  const d = await store.device(browser, server, NOON);
  await importFiles(d.page, [file], 1);
  await store.join(d, server);
  await openBook(d.page, 'Shared Book');
  await highlight(d.page, 0, 8);
  await toLibrary(d.page);
  await hiddenSync(store, server, d);
  const text = server.body;
  await d.context.close();
  return text;
}

for (const how of ['abort', 'lost', 'hold']) {
  const words = {
    abort: 'the write fails (the request is aborted)',
    lost: 'the folder takes the write but the answer is lost',
    hold: 'the write never answers and the page goes away',
  }[how];
  test(`a sync cut short after the read and before the write (${words}), then run again, changes nothing twice`, async ({ browser }) => {
    const store = stores.webdav;
    const file = epubFile(book);
    const control = await uncut(browser, file);
    const server = store.make();
    const a = await cuttable(browser, server, NOON);
    await importFiles(a.page, [file], 1);
    await store.join(a, server);
    await openBook(a.page, 'Shared Book');
    await highlight(a.page, 0, 8);
    await toLibrary(a.page);
    const before = server.body;
    const gets = server.gets;

    // the page hidden starts a sync: it reads, and its write is cut short
    a.fate.next = how;
    await hide(a.page);
    await expect.poll(() => a.fate.seen).toBe(1);
    await expect.poll(() => server.gets).toBeGreaterThan(gets);
    await a.page.waitForTimeout(500);
    if (how === 'lost') expect(server.body).not.toBe(before);
    else expect(server.body).toBe(before);
    if (how === 'hold') {
      // the page goes away with the request pending (the app opened again
      // is a sync point of its own: it is the run again, below)
      await a.page.goto('about:blank');
      await a.page.goto('/');
      await clockFixed(a.page, NOON);
      await expect.poll(() => a.page.getByRole('searchbox', { name: 'Search the library' }).isVisible()).toBe(true);
    }
    // nothing is lost here by the failure: the highlight is where it was
    await openBook(a.page, 'Shared Book');
    expect((await showing(a)).quotes).toEqual([FIRST]);
    await toLibrary(a.page);

    // run again: the file is what it would have been; and again: the same
    await hiddenSync(store, server, a);
    const once = server.body;
    expect(withoutStamps(once)).toBe(withoutStamps(control));
    expect(server.json().books[0].annotations).toHaveLength(1);
    await hiddenSync(store, server, a);
    await sync(store, server, a);
    expect(server.body).toBe(once);
    await openBook(a.page, 'Shared Book');
    expect((await showing(a)).quotes).toEqual([FIRST]);
    // another device takes it once, and adds nothing
    const b = await store.device(browser, server, LATER);
    await importFiles(b.page, [file], 1);
    await store.join(b, server);
    await openBook(b.page, 'Shared Book');
    expect((await showing(b)).quotes).toEqual([FIRST]);
    expect(server.json().books[0].annotations).toHaveLength(1);
    expect(a.errors.filter(e => /^pageerror/.test(e))).toEqual([]);
    await closeBoth(a, b);
  });
}
