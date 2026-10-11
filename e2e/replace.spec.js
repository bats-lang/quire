// Replacing a book (quire#425): importing a file that is already in the
// library and choosing Replace. The decision is written in the issue:
// Replace keeps everything the reader made (the place, the shelf, the
// collections, the finished mark, the minutes, every annotation and
// note, the library's order and the card's progress, and the book's
// id) and replaces the file and the cover, so the book is one book
// before and after. The books are those of replace-books.js.

import { test, expect } from './fixtures.js';
import {
  start, importFiles, importInput, openBook, toLibrary, epubFile, chapters, dialog, menuItem, bookMenu,
  cards, card, titles, place, placeChanged, oneColumn, selectText, selectionButton,
  clickControl, reload,
} from './helpers.js';
import { stored, settled } from './relaunch.js';
import { writeFileSync, statSync } from 'node:fs';
import { librarySettings, settingsButton, restoreInput, exportedBackup, openShelf, shelfTitle } from './helpers.js';
import { NOON, minutesLater, stores, sync, highlight, shown } from './sync-devices.js';
import { replaceBook } from './replace-books.js';
import { panel, note, readMinutes, highlightWithNote, bookmarkPage, inCollection, fileSizes, replaceWith } from './replace-steps.js';

const FIXED = new Date('2026-06-01T10:00:00Z');

test('replacing a book with the identical file changes nothing the reader made', async ({ page }) => {
  await page.clock.install({ time: FIXED });
  const errors = await start(page);
  const file = epubFile(replaceBook);
  const short = epubFile({ title: 'Finished One', author: 'Replace Tests', rawChapters: chapters(1, 3) });
  await importFiles(page, [file, short], 2);
  // a book finished
  await openBook(page, 'Finished One');
  await page.keyboard.press('End');
  await toLibrary(page);
  // a book read: minutes, a place in the second chapter, a bookmark,
  // two highlights with notes, in a collection
  await openBook(page, 'Replace Me');
  await oneColumn(page);
  await highlightWithNote(page, 'First thought');
  await bookmarkPage(page);
  await readMinutes(page, 2);
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  await highlightWithNote(page, 'Second thought');
  await readMinutes(page, 3);
  const where = await place(page);
  expect(where.p).toBeGreaterThan(3);
  await toLibrary(page);
  await inCollection(page, 'Replace Me', 'To keep');
  await settled(page);

  const before = await stored(page);
  const order = await titles(page);
  const progress = await card(page, 'Replace Me').innerText();

  await replaceWith(page, file);
  await replaceWith(page, short);
  await settled(page);
  const after = await stored(page);
  const changed = Object.keys({ ...before, ...after }).filter(key => before[key] !== after[key]).sort();
  expect(changed.map(key => `${key}\n  before ${before[key]}\n  after  ${after[key]}`), 'the stored records that changed').toEqual([]);
  // one file for each book, of the file's size, and the cover is still the book's
  expect(Object.values(await fileSizes(page)).sort()).toEqual([statSync(file).size, statSync(short).size].sort());
  await expect(card(page, 'Replace Me').locator('img')).toHaveCount(1);
  expect(await titles(page)).toEqual(order);
  expect(await card(page, 'Replace Me').innerText()).toBe(progress);

  await openBook(page, 'Replace Me');
  expect(await place(page)).toEqual(where);
  expect(errors).toEqual([]);
});

test('replacing a hidden book keeps it hidden', async ({ page }) => {
  const errors = await start(page);
  const file = epubFile(replaceBook);
  await importFiles(page, [file], 1);
  await bookMenu(page, 'Replace Me');
  await menuItem(page, 'Hide').click();
  await expect(cards(page)).toHaveCount(0);
  await replaceWith(page, file);
  // still not in the Library, and in Hidden
  await expect(cards(page)).toHaveCount(0);
  await openShelf(page, 'Hidden');
  await expect(shelfTitle(page)).toHaveText('Hidden');
  await expect(cards(page)).toHaveCount(1);
  await openBook(page, 'Replace Me');
  expect(errors).toEqual([]);
});

test('replacing a book in the Trash puts it back in the Library, with what the reader made', async ({ page }) => {
  await start(page);
  const file = epubFile(replaceBook);
  await importFiles(page, [file], 1);
  await openBook(page, 'Replace Me');
  await oneColumn(page);
  await highlightWithNote(page, 'Kept in the Trash');
  await readMinutes(page, 2);
  const where = await place(page);
  await toLibrary(page);
  await bookMenu(page, 'Replace Me');
  await menuItem(page, 'Move to Trash').click();
  await expect(cards(page)).toHaveCount(0);
  await replaceWith(page, file);
  await expect(cards(page)).toHaveCount(1);
  await openBook(page, 'Replace Me');
  expect(await place(page)).toEqual(where);
  await clickControl(page, 'Annotations');
  await expect(panel(page)).toContainText('Kept in the Trash');
});

test('importing an archived book again puts it back in the Library, with what the reader made', async ({ page }) => {
  await start(page);
  const file = epubFile(replaceBook);
  await importFiles(page, [file], 1);
  await openBook(page, 'Replace Me');
  await oneColumn(page);
  await highlightWithNote(page, 'Kept in the archive');
  await readMinutes(page, 2);
  const where = await place(page);
  await toLibrary(page);
  await bookMenu(page, 'Replace Me');
  await menuItem(page, 'Archive').click();
  await expect(cards(page)).toHaveCount(0);
  // an archived book is restored by importing it: nothing is asked
  await importInput(page).setInputFiles([file]);
  await expect(cards(page)).toHaveCount(1);
  await openBook(page, 'Replace Me');
  expect(await place(page)).toEqual(where);
  await clickControl(page, 'Annotations');
  await expect(panel(page)).toContainText('Kept in the archive');
});

test('a backup made before a replace restores onto the same book', async ({ page }, testInfo) => {
  await page.clock.install({ time: FIXED });
  const errors = await start(page);
  const file = epubFile(replaceBook);
  await importFiles(page, [file], 1);
  await openBook(page, 'Replace Me');
  await oneColumn(page);
  await highlightWithNote(page, 'Before the backup');
  await readMinutes(page, 2);
  await toLibrary(page);
  await librarySettings(page);
  const text = await exportedBackup(page);
  await settingsButton(page, 'Done').click();
  const backup = JSON.parse(text);
  expect(backup.books).toHaveLength(1);
  // after the backup: a note more, and the book replaced
  await openBook(page, 'Replace Me');
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  await highlightWithNote(page, 'After the backup');
  await toLibrary(page);
  await replaceWith(page, file);
  await librarySettings(page);
  const replaced = JSON.parse(await exportedBackup(page));
  await settingsButton(page, 'Done').click();
  expect(replaced.books).toHaveLength(1);
  expect(replaced.books[0].id).toBe(backup.books[0].id);
  // the backup restores onto it: one book, the notes it had
  await librarySettings(page);
  const path = testInfo.outputPath('before-replace.json');
  writeFileSync(path, text);
  await restoreInput(page).setInputFiles([path]);
  await expect(dialog(page, 'Backup restored')).toBeVisible();
  await dialog(page, 'Backup restored').getByRole('button').first().click();
  await expect(cards(page)).toHaveCount(1);
  await librarySettings(page);
  const restored = JSON.parse(await exportedBackup(page));
  await settingsButton(page, 'Done').click();
  expect(restored.books).toHaveLength(1);
  // everything of the backup's, but the place: a restore takes the file's place only when it is
  // later than the library's, and the library's is (it was moved on after the backup)
  const moved = ['chapter', 'page', 'pages', 'anchor', 'placeModified', 'progressWeighted', 'placeDevice', 'opened'];
  const without = book => Object.fromEntries(Object.entries(book).filter(([key]) => !moved.includes(key)));
  expect(without(restored.books[0])).toEqual(without(backup.books[0]));
  for (const key of moved) expect(restored.books[0][key], key).toEqual(replaced.books[0][key]);
  await openBook(page, 'Replace Me');
  await clickControl(page, 'Annotations');
  await expect(panel(page)).toContainText('Before the backup');
  await expect(panel(page)).not.toContainText('After the backup');
  expect(errors).toEqual([]);
});

test('a replaced book syncs as the same book, and the other device keeps its own place and notes', async ({ browser }) => {
  const store = stores.webdav;
  const server = store.make();
  const a = await store.device(browser, server, NOON);
  const b = await store.device(browser, server, minutesLater(NOON, 1));
  const file = epubFile(replaceBook);
  for (const d of [a, b]) {
    await importFiles(d.page, [file], 1);
    await store.join(d, server);
  }
  // this device notes the first chapter; the other reads on to the second and notes it
  await openBook(a.page, 'Replace Me');
  await highlight(a.page, 0, 8);
  await openBook(b.page, 'Replace Me');
  await b.page.keyboard.press('End');
  await b.page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(b.page)).ch).toBe(2);
  await highlight(b.page, 0, 8);
  const placeBefore = await place(b.page);
  for (const d of [a, b]) await toLibrary(d.page);
  for (const d of [a, b, a]) await sync(store, server, d);
  const first = JSON.parse(server.body);
  expect(first.books).toHaveLength(1);
  // this device replaces the book
  await replaceWith(a.page, file);
  for (const d of [a, b, a]) await sync(store, server, d);
  const second = JSON.parse(server.body);
  expect(second.books).toHaveLength(1);
  expect(second.books[0].id).toBe(first.books[0].id);
  // the other device: one book, its own place, both notes
  await expect(cards(b.page)).toHaveCount(1);
  await openBook(b.page, 'Replace Me');
  expect(await place(b.page)).toEqual(placeBefore);
  // (the page paints the chapter shown's notes, the list has them all)
  const view = await shown(b.page);
  expect(view.quotes).toEqual(['Para 1.0', 'Para 2.0']);
  expect(view.painted).toHaveLength(1);
  for (const d of [a, b]) await d.context.close();
});

test('replacing a book in another tab leaves the open tab reading, and neither loses what the other did', async ({ page, context }) => {
  const errors = await start(page);
  const file = epubFile(replaceBook);
  await importFiles(page, [file], 1);
  await openBook(page, 'Replace Me');
  await oneColumn(page);
  await highlightWithNote(page, 'Made before');
  const other = await context.newPage();
  await other.goto('/');
  // the app opens where it was left: in the book
  await toLibrary(other);
  await expect(cards(other)).toHaveCount(1);
  await replaceWith(other, file);
  await inCollection(other, 'Replace Me', 'Made elsewhere');
  // the first tab reads on and notes the second chapter
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  await highlightWithNote(page, 'Made after');
  await toLibrary(page);
  // the other tab is closed; what this tab reads from the stored records
  // has what both did: the notes of this one, and the collection of the other
  await other.close();
  await reload(page);
  await expect(cards(page)).toHaveCount(1);
  await openBook(page, 'Replace Me');
  await clickControl(page, 'Annotations');
  await expect(panel(page)).toContainText('Made before');
  await expect(panel(page)).toContainText('Made after');
  await panel(page).getByRole('button', { name: 'Close' }).click();
  await toLibrary(page);
  await bookMenu(page, 'Replace Me');
  await menuItem(page, 'Collections').click();
  await expect(dialog(page, 'Collections').getByRole('button', { name: 'Made elsewhere', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');
  expect(errors).toEqual([]);
});
