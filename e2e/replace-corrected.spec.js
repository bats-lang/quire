// A corrected file of a book in the library (quire#425). A book's id is
// its file's, so a corrected file has another id and was a new book with
// none of the reader's notes, as it is in Apple Books and on a Kobo
// (the issue's research). When a file's title and author are those of a
// book in the library, the import asks "Newer file of a book?": Replace
// keeps the book, with its shelf, collections and order, and finds the
// place and each note in the new file by the chapter's name (its href);
// a note whose chapter or nodes the new file has not is kept in the list,
// under "Not found in this version", with its text and its note; Add as
// new book makes a book of its own. The books are those of
// replace-books.js (all checked by epubcheck).

import { test, expect } from './fixtures.js';
import {
  start, importFiles, importInput, openBook, toLibrary, epubFile, dialog, bookMenu, menuItem,
  cards, card, titles, place, oneColumn, clickControl, reload, bookPage, startsOnPage,
  expectBannerSaysWhatToDo,
} from './helpers.js';
import { stored, settled } from './relaunch.js';
import { statSync } from 'node:fs';
import { marks } from './helpers.js';
import { replaceBook, correctedBook, correctedCover, restructuredBook } from './replace-books.js';
import {
  panel, highlightWithNote, highlightLastWithNote, inCollection, fileSizes, replaceWithNewer, addNewerAsNew, coverBytes,
} from './replace-steps.js';

/** Opens the annotations and gives the list's text, closing it again */
async function annotationsText(page) {
  await clickControl(page, 'Annotations');
  await expect(panel(page)).toBeVisible();
  const text = await panel(page).innerText();
  await panel(page).getByRole('button', { name: 'Close' }).click();
  await expect(panel(page)).toBeHidden();
  return text;
}

/** From the first page of the book to a note in each of its three
    chapters, the last of them on the last page of the third (its last
    paragraph that begins there), and back to the second chapter, two
    pages before its end: the place the specs keep */
async function readThreeChapters(page, notes) {
  await oneColumn(page);
  await highlightWithNote(page, notes[0]);
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  await highlightWithNote(page, notes[1]);
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(3);
  await page.keyboard.press('End');
  await highlightLastWithNote(page, notes[2]);
  await page.keyboard.press('Home');
  await page.keyboard.press('ArrowLeft');
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  await page.keyboard.press('ArrowLeft');
  await page.keyboard.press('ArrowLeft');
  const where = await place(page);
  expect(where.ch).toBe(2);
  expect(where.p).toBeGreaterThan(3);
  return where;
}

test('a corrected file of a book in the library replaces it: the place, the notes whose nodes are there, the shelf and the collection are kept, and a note whose text is gone is listed as not found', async ({ page }) => {
  const errors = await start(page);
  const original = epubFile(replaceBook);
  const corrected = epubFile(correctedBook);
  await importFiles(page, [original], 1);
  await openBook(page, 'Replace Me');
  const where = await readThreeChapters(page, ['In chapter one', 'In chapter two', 'Cut with the text']);
  await toLibrary(page);
  await inCollection(page, 'Replace Me', 'To keep');
  await settled(page);
  const before = await stored(page);
  const order = await titles(page);

  await replaceWithNewer(page, corrected);
  await settled(page);
  const after = await stored(page);

  // one book still, in the collection it was in; what changed in storage is the file, its
  // cover, its size in the library's record and the note of which file it is, and the notes
  // and the names of the chapters did not
  await expect(cards(page)).toHaveCount(1);
  expect(await titles(page)).toEqual(order);
  const changed = Object.keys({ ...before, ...after }).filter(key => before[key] !== after[key])
    .map(key => key.replace(/"([a-z])[0-9a-f]{14}"/, '"$1<id>"').replace(/[0-9a-f]{14}/, '<id>')).sort();
  expect(changed, 'the stored records that changed').toEqual(
    ['bats/kv "b<id>"', 'bats/kv "c<id>"', 'bats/kv "v<id>"', 'bats/kv "library/book/<id>"'].sort());
  // one file, the corrected one's size, and its cover is the corrected file's
  expect(Object.values(await fileSizes(page))).toEqual([statSync(corrected).size]);
  const covers = Object.values(await coverBytes(page));
  expect(covers).toHaveLength(1);
  expect(covers[0]).toEqual([...correctedCover]);
  await expect.poll(() => card(page, 'Replace Me').locator('img').evaluate(img => img.naturalWidth)).toBe(8);
  await bookMenu(page, 'Replace Me');
  await menuItem(page, 'Collections').click();
  await expect(dialog(page, 'Collections').getByRole('button', { name: 'To keep', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');

  // it opens where it was, on the corrected text, with the notes whose nodes are there
  await openBook(page, 'Replace Me');
  expect(await place(page)).toEqual(where);
  expect((await startsOnPage(page)).every(text => text.startsWith('Fixed 2.') || text.startsWith('Part 2'))).toBe(true);
  let listed = await annotationsText(page);
  for (const text of ['In chapter one', 'In chapter two', 'Cut with the text']) expect(listed).toContain(text);
  // the chapter 2's highlight is painted on the first page of it, as it was
  await page.keyboard.press('Home');
  await expect.poll(() => marks(page)).toMatchObject({ size: 1 });

  // the third chapter has not the node the last note names: shown, it is listed as not found,
  // with its words and its note, painted nowhere, and nothing is lost or broken
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(3);
  listed = await annotationsText(page);
  expect(listed).toMatch(/not found in this version/i);
  expect(listed.toLowerCase().indexOf('not found in this version')).toBeLessThan(listed.indexOf('Cut with the text'));
  expect(listed).toContain('In chapter one');
  expect(listed).toContain('In chapter two');
  expect((await marks(page)).size).toBe(0);
  // it is kept: after the app is opened again it is still listed so, and the book opens
  await toLibrary(page);
  await settled(page);
  await reload(page);
  await openBook(page, 'Replace Me');
  listed = await annotationsText(page);
  expect(listed).toMatch(/not found in this version/i);
  expect(listed).toContain('Cut with the text');
  expect(errors).toEqual([]);
});

test('Add as new book makes a book of its own and leaves the first book as it was', async ({ page }) => {
  const errors = await start(page);
  const original = epubFile(replaceBook);
  const corrected = epubFile(correctedBook);
  await importFiles(page, [original], 1);
  await openBook(page, 'Replace Me');
  await oneColumn(page);
  await highlightWithNote(page, 'Only the first has this');
  await toLibrary(page);
  await addNewerAsNew(page, corrected);
  await expect(cards(page)).toHaveCount(2);
  await settled(page);
  expect(Object.values(await fileSizes(page)).sort()).toEqual([statSync(original).size, statSync(corrected).size].sort());
  // exactly one of the two books has the note
  const withNote = [];
  for (const index of [0, 1]) {
    await cards(page).nth(index).click();
    await expect(bookPage(page)).toBeVisible();
    withNote.push((await annotationsText(page)).includes('Only the first has this'));
    await toLibrary(page);
  }
  expect(withNote.filter(Boolean)).toHaveLength(1);
  expect(errors).toEqual([]);
});

test('a file that adds, removes and reorders chapters is found by the chapters\' names: the place and the notes follow their chapters, and the note of a removed chapter is listed as not found', async ({ page }) => {
  const errors = await start(page);
  const original = epubFile(replaceBook);
  const restructured = epubFile(restructuredBook);
  await importFiles(page, [original], 1);
  await openBook(page, 'Replace Me');
  const where = await readThreeChapters(page, ['Note of one', 'Note of two', 'Note of three']);
  await toLibrary(page);
  await settled(page);

  await replaceWithNewer(page, restructured);
  await settled(page);
  await expect(cards(page)).toHaveCount(1);

  // the place is in chapter 2 still, on the same page, though chapter 2 is the third chapter now
  await openBook(page, 'Replace Me');
  expect(await place(page)).toEqual(where);
  expect((await startsOnPage(page)).every(text => text.startsWith('Para 2.') || text.startsWith('Part 2'))).toBe(true);
  // the notes of chapters 3 and 2 are under them, in the new order, and chapter 1's is not found
  const listed = await annotationsText(page);
  const at = text => listed.indexOf(text);
  expect(at('Note of three')).toBeGreaterThan(-1);
  expect(at('Note of three')).toBeLessThan(at('Note of two'));
  expect(at('Note of two')).toBeLessThan(listed.toLowerCase().indexOf('not found in this version'));
  expect(listed.toLowerCase().indexOf('not found in this version')).toBeLessThan(at('Note of one'));
  // the note of chapter 2 is painted on its page
  await page.keyboard.press('Home');
  await expect.poll(() => marks(page)).toMatchObject({ size: 1 });
  // going to a note goes to its chapter
  await clickControl(page, 'Annotations');
  await panel(page).getByRole('button', { name: /Note of three/ }).click();
  await expect.poll(async () => (await place(page)).ch).toBe(3);
  expect(errors).toEqual([]);
});

test('a file replaced in another tab is left by the tab reading it, which says so', async ({ page, context }, testInfo) => {
  const errors = await start(page);
  const original = epubFile(replaceBook);
  const corrected = epubFile(correctedBook);
  await importFiles(page, [original], 1);
  await openBook(page, 'Replace Me');
  await oneColumn(page);
  await highlightWithNote(page, 'Made before');
  const other = await context.newPage();
  await other.goto('/');
  await toLibrary(other);
  await expect(cards(other)).toHaveCount(1);
  await replaceWithNewer(other, corrected);
  await settled(other);
  // the first tab is shown again: the book it reads is another file now
  await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
  await expect(page.getByRole('alert')).toContainText('replaced with another file in another tab');
  await expectBannerSaysWhatToDo(page, testInfo);
  await expect(cards(page)).toHaveCount(1);
  await page.getByRole('alert').getByRole('button', { name: 'Reopen Quire' }).click();
  await other.close();
  await expect(cards(page)).toHaveCount(1);
  // what it did before is there, on the new file
  await openBook(page, 'Replace Me');
  expect(await annotationsText(page)).toContain('Made before');
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  expect((await startsOnPage(page)).some(text => text.startsWith('Fixed 2.') || text.startsWith('Part 2'))).toBe(true);
  expect(errors.filter(error => !/Failed to load resource/.test(error))).toEqual([]);
});
