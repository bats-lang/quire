// A book's record that lost a group (its place, shelf or finished mark) or
// its notes' record is repaired by the next sync from the file the store
// keeps (#615). A lost group is read with a substitute whose stamp is 0 (a
// value never dated), and the merge takes the later change by stamp, so the
// store file's value should win; this plays it, through each store the
// suite plays (a WebDAV folder, Google Drive's app data folder, and the
// file Android's Auto Backup keeps), for each group the record can lose,
// lost absent and with a bad CRC, and for the notes' record deleted.
//
// A device holds the book read to its last page (finished, at its last
// chapter), with a bookmark in chapter 2, moved to Hidden, and has synced.
// The record in its store is then damaged, the app opened again (a sync
// runs as it opens), and what the book shows is looked at.

import { test, expect } from './fixtures.js';
import {
  epubFile, cards, card, dialog, bookMenu, menuItem, openShelf, place, control, showChrome, indicator, reload, libraryShown,
} from './helpers.js';
import { store, put, bookKey, hex7 } from './legacy-library.js';
import {
  book, NOON, stores, sync, importFiles, openBook, toLibrary, clockFixed, unexpected,
} from './sync-devices.js';

const kinds = ['webdav', 'drive', 'autobackup'];

/** The chunks of a record: its tag, where it starts and ends, and its data (a record's layout is in .claude/rules/library-records.md) */
function chunksOf(record) {
  const out = [];
  for (let at = 7; at + 8 <= record.length;) {
    const length = record[at] + record[at + 1] * 256 + record[at + 2] * 65536 + record[at + 3] * 16777216;
    out.push({ tag: String.fromCharCode(...record.slice(at + 4, at + 8)), start: at, end: at + 12 + length, data: at + 8, length });
    at += 12 + length;
  }
  return out;
}
const tagsOf = record => chunksOf(record).map(one => one.tag).sort();

/** The record with the chunks of tags cut out (absent) or one data byte changed (the CRC no longer holds) */
function lost(record, tags, how) {
  const found = chunksOf(record).filter(one => tags.includes(one.tag));
  expect(found.map(one => one.tag).sort(), 'the record holds the groups to lose').toEqual([...tags].sort());
  if (how === 'absent') return Uint8Array.from([...record].filter((_, i) => !found.some(one => i >= one.start && i < one.end)));
  const damaged = Uint8Array.from(record);
  for (const one of found) damaged[one.data] ^= 0x5a;
  return damaged;
}

const star = page => page.getByRole('button', { name: 'Bookmark this page' });
const contents = page => dialog(page, 'Contents');

/** The bookmarks the open book lists, by the chapter they name */
async function bookmarks(page) {
  await control(page, 'Contents').click();
  const tab = contents(page).getByRole('tab', { name: 'Bookmarks' });
  await tab.click();
  const listed = await contents(page).getByRole('tabpanel', { name: 'Bookmarks' }).getByRole('button').allInnerTexts();
  await contents(page).getByRole('button', { name: 'Close' }).click();
  await expect(contents(page)).toBeHidden();
  return listed.map(text => text.split('\n')[0].trim()).filter(text => /^Chapter \d/.test(text));
}

/** The app opened again, its clock fixed again: the library shown (with its one book on the Hidden
    shelf it has no search box, which `reopen` in sync-devices.js waits for) */
async function reopened(d) {
  await reload(d.page);
  await clockFixed(d.page, d.time);
  await expect(libraryShown(d.page)).toBeVisible();
}

/** One device holding the book as the reader left it: read to the last page, a bookmark in
    chapter 2, moved to Hidden; synced */
async function readerWithState(browser, store, server) {
  const d = await store.device(browser, server, NOON);
  await importFiles(d.page, [epubFile(book)], 1);
  await store.join(d, server);
  await openBook(d.page, 'Shared Book');
  await d.page.keyboard.press('End');
  await d.page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(d.page)).ch).toBe(2);
  await showChrome(d.page);
  await star(d.page).click();
  await expect(star(d.page)).toHaveAttribute('aria-pressed', 'true');
  for (const chapter of [3, 4]) {
    await d.page.keyboard.press('End');
    await d.page.keyboard.press('ArrowRight');
    await expect.poll(async () => (await place(d.page)).ch).toBe(chapter);
  }
  await d.page.keyboard.press('End');
  await toLibrary(d.page);
  await expect(card(d.page, 'Shared Book')).toContainText('Finished');
  await bookMenu(d.page, 'Shared Book');
  await menuItem(d.page, 'Hide').click();
  await expect(cards(d.page)).toHaveCount(0);
  await sync(store, server, d);
  return d;
}

/** What the file the store keeps says of the book */
function filed(store, server, d) {
  const text = store.bytes(server, d);
  expect(text, 'the store holds the sync file').toBeTruthy();
  return JSON.parse(text).books.find(one => one.title === 'Shared Book');
}

/** The book as the reader sees it: on the Hidden shelf and not the library's, finished, read to
    its last chapter, with the bookmark of chapter 2 */
async function expectRestored(d) {
  const page = d.page;
  await expect(cards(page), 'the library holds no book: it is on the Hidden shelf again').toHaveCount(0, { timeout: 20000 });
  await openShelf(page, 'Hidden');
  await expect(card(page, 'Shared Book')).toBeVisible();
  await expect(card(page, 'Shared Book')).toContainText('Finished');
  await card(page, 'Shared Book').click();
  await expect(indicator(page)).toContainText('in chapter');
  expect((await place(page)).ch, 'the place is the last chapter').toBe(4);
  expect(await bookmarks(page), 'the bookmark of chapter 2').toEqual([expect.stringMatching(/Chapter 2/)]);
}

// (the finished flag `done` is a field of SIZE, its stamp `finished_modified` one of FNSH: a lost SIZE
// reads as not finished with the stamp kept, a lost FNSH as finished with no stamp, both lost as neither)
const cases = [
  { name: 'its place, shelf, finished mark and size absent', tags: ['PLCE', 'SHLF', 'FNSH', 'SIZE'], how: 'absent' },
  { name: 'its place, shelf, finished mark and size with a bad CRC', tags: ['PLCE', 'SHLF', 'FNSH', 'SIZE'], how: 'crc' },
  { name: 'its place absent', tags: ['PLCE'], how: 'absent' },
  { name: 'its shelf with a bad CRC', tags: ['SHLF'], how: 'crc' },
  { name: 'its finished mark absent', tags: ['FNSH'], how: 'absent' },
  { name: 'its size, which holds the finished flag, absent', tags: ['SIZE'], how: 'absent' },
  { name: 'its finished mark and its size with a bad CRC', tags: ['FNSH', 'SIZE'], how: 'crc' },
  { name: 'its title and author absent', tags: ['TITL', 'AUTH'], how: 'absent' },
];

for (const kind of kinds) {
  const kept = stores[kind];

  for (const { name, tags, how } of cases) {
    test(`${kept.name}: a record that lost ${name} is repaired by the next sync (#615)`, async ({ browser }) => {
      const server = kept.make();
      const d = await readerWithState(browser, kept, server);
      // the file holds what the reader made
      const before = filed(kept, server, d);
      expect(before).toMatchObject({ chapter: 3, done: 1 });
      expect(before.shelf, 'moved to Hidden').toBeGreaterThan(0);
      const records = await store(d.page);
      const key = Object.keys(records).find(one => one.startsWith('library/book/'));
      const id = key.slice('library/book/'.length);
      const whole = Uint8Array.from(records[key]);
      expect(tagsOf(whole)).toEqual(expect.arrayContaining(tags));
      // the record loses groups; the app opened again syncs as it opens
      const damaged = lost(whole, tags, how);
      await put(d.page, key, damaged);
      await reopened(d);
      if (!tags.includes('TITL')) await expectRestored(d);
      else {
        // the title is "Untitled" until the book is opened, and its title and author are read from its
        // file then (stage 2c); the shelf, finished mark and place were never lost
        await openShelf(d.page, 'Hidden');
        await expect(card(d.page, 'Untitled')).toContainText('Finished');
        await card(d.page, 'Untitled').click();
        await expect(indicator(d.page)).toContainText('in chapter');
        expect((await place(d.page)).ch, 'the place is the last chapter').toBe(4);
        await toLibrary(d.page);
        await openShelf(d.page, 'Hidden');
        await expect(card(d.page, 'Shared Book')).toContainText('Sync Tests');
        await expect(card(d.page, 'Shared Book')).toContainText('Finished');
      }
      // and the repair is kept: the record has every group again, and the bytes it had are kept
      await expect.poll(async () => tagsOf(Uint8Array.from((await store(d.page))[key]))).toEqual(tagsOf(whole));
      const after = await store(d.page);
      expect(Object.keys(after).filter(one => one.startsWith(`library/damaged/${id}/`)), 'the damaged bytes are kept').toHaveLength(1);
      expect(unexpected(d)).toEqual([]);
      await d.context.close();
    });
  }

  test(`${kept.name}: a book whose notes' record is gone has its bookmark back from the next sync (#615)`, async ({ browser }) => {
    const server = kept.make();
    const d = await readerWithState(browser, kept, server);
    const records = await store(d.page);
    const bookKeyFound = Object.keys(records).find(one => one.startsWith('library/book/'));
    const id = bookKeyFound.slice('library/book/'.length);
    // the notes are the book's "a" key: a bookmark made in chapter 2
    expect(records[`a${id}`], 'the book has a record of its notes').toBeDefined();
    await put(d.page, `a${id}`, null);
    await reopened(d);
    await expectRestored(d);
    expect(unexpected(d)).toEqual([]);
    await d.context.close();
  });
}
