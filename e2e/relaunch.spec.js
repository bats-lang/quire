// Quitting Quire and opening it again changes nothing (#302): in each
// state a reader leaves it in, the app is captured whole (relaunch.js:
// the screen's pixels, what is open, the book and its place, the
// library's view, every stored record), closed and opened again in the
// same browser (its storage kept), captured again once every launch step
// (a sync included) has ended, and the two captures must be the same.

import { test, expect } from './fixtures.js';
import { launch, chapterShown, nextChapter, previousChapter, pagesOn, unchanged } from './relaunch.js';
import {
  epubFile, importFiles, openBook, toLibrary, librarySearch, cards, chapters, japaneseChapters, dialog, openReadingSettings, readingSettings, selectText, selectionButton, fixedLayoutBook, readFixed, indicator,
} from './helpers.js';

const book = { title: 'Kept Book', author: 'Relaunch Tests', chapters: 4, rawChapters: chapters(4, 40) };

// ---- the library ----

test('the library, in a view, a filter, a sort and a search, is as it was', async ({ context, page }) => {
  await launch(context, page);
  await importFiles(page, [
    epubFile({ title: 'Alpha', author: 'Zed', rawChapters: chapters(2, 20) }),
    epubFile({ title: 'Mid', author: 'Young', rawChapters: chapters(2, 20) }),
    epubFile({ title: 'Zulu', author: 'Ann', rawChapters: chapters(2, 20) }),
  ], 3);
  await openBook(page, 'Mid');
  await pagesOn(page, 2);
  await toLibrary(page);
  page = await unchanged(page);
  // a grid, by title
  await page.getByRole('group', { name: 'View' }).getByRole('button', { name: 'Grid' }).click();
  const sort = page => page.getByRole('button', { name: /^Sort:/ });
  await sort(page).click();
  await expect(sort(page)).toHaveText('Sort: Title');
  page = await unchanged(page);
  // the books being read, by author
  await page.getByRole('group', { name: 'Show' }).getByRole('button', { name: 'Reading' }).click();
  await sort(page).click();
  await expect(sort(page)).toHaveText('Sort: Author');
  page = await unchanged(page, 'killed');
  // all of them, searched
  await page.getByRole('group', { name: 'Show' }).getByRole('button', { name: 'All' }).click();
  await librarySearch(page).fill('lu');
  await expect(cards(page)).toHaveCount(1);
  await unchanged(page);
});

// ---- reading, in each layout ----

/** The book opened, read to the middle of its second chapter */
async function midChapter(page) {
  await importFiles(page, [epubFile(book)], 1);
  await openBook(page, 'Kept Book');
  await nextChapter(page);
  await pagesOn(page, 2);
}

/** A choice of the reading settings' Page tab */
async function pageChoice(page, group, name) {
  await openReadingSettings(page, 'Page');
  await readingSettings(page).getByRole('group', { name: group }).getByRole('button', { name, exact: true }).click();
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
}

for (const how of ['quit', 'killed']) {
  test(`paged, in the middle of a chapter, the book opens where it was (${how})`, async ({ context, page }) => {
    await launch(context, page);
    await midChapter(page);
    await unchanged(page, how);
  });
}

test('scrolled, in the middle of a chapter, the book opens where it was', async ({ context, page }) => {
  await launch(context, page);
  await importFiles(page, [epubFile(book)], 1);
  await openBook(page, 'Kept Book');
  await pageChoice(page, 'Layout', 'Scroll');
  await nextChapter(page);
  await page.keyboard.press('PageDown');
  await page.keyboard.press('PageDown');
  await unchanged(page);
});

test('in two columns, in the middle of a chapter, the book opens where it was', async ({ context, page }) => {
  await launch(context, page);
  await importFiles(page, [epubFile(book)], 1);
  await openBook(page, 'Kept Book');
  await pageChoice(page, 'Pages on screen', 'Two');
  await nextChapter(page);
  await pagesOn(page, 2);
  await unchanged(page);
});

test('set vertically, in the middle of a chapter, the book opens where it was', async ({ context, page }) => {
  await launch(context, page);
  await importFiles(page, [epubFile({ title: '縦の頁', author: 'Relaunch Tests', language: 'ja', rtl: true, rawChapters: japaneseChapters(2, 40) })], 1);
  await openBook(page, '縦の頁');
  for (let k = 0; k < 3; k++) {
    const before = await indicator(page).textContent();
    await page.keyboard.press('ArrowLeft');
    await expect(indicator(page)).not.toHaveText(before);
  }
  await unchanged(page);
});

test('a fixed-layout book opens on the page it was on, alone or in a spread', async ({ context, page }) => {
  await launch(context, page);
  await readFixed(page, fixedLayoutBook('Fixed Pages', 6, { spread: 'auto' }));
  await page.keyboard.press('ArrowRight');
  await page.keyboard.press('ArrowRight');
  page = await unchanged(page);
  // in spreads, whatever the window (the bars brought up by their key: a
  // tap on a fixed page is a tap on its picture)
  await page.keyboard.press('t');
  await openReadingSettings(page, 'Page');
  await readingSettings(page).getByRole('group', { name: 'Pages on screen' }).getByRole('button', { name: 'Two', exact: true }).click();
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
  await unchanged(page);
});

// ---- after going back in a book ----

test('after going back in a book, it opens where the reader went back to, and offers nothing', async ({ context, page }) => {
  await launch(context, page);
  await importFiles(page, [epubFile(book)], 1);
  await openBook(page, 'Kept Book');
  await nextChapter(page);
  await nextChapter(page);
  await previousChapter(page);
  await previousChapter(page);
  expect(await chapterShown(page)).toBe(1);
  page = await unchanged(page);
  expect(await chapterShown(page)).toBe(1);
  // from the library too
  await toLibrary(page);
  page = await unchanged(page);
  await openBook(page, 'Kept Book');
  expect(await chapterShown(page)).toBe(1);
});

// ---- settings, annotations and a search ----

test('with settings changed, annotations made and a search done, all is as it was', async ({ context, page }) => {
  await launch(context, page);
  await importFiles(page, [epubFile(book)], 1);
  await openBook(page, 'Kept Book');
  await openReadingSettings(page, 'Look');
  await readingSettings(page).getByRole('group', { name: 'Theme' }).getByRole('button', { name: 'Sepia', exact: true }).click();
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
  await selectText(page, 0, 8);
  await selectionButton(page, 'Highlight').click();
  await page.evaluate(() => getSelection().removeAllRanges());
  // a search, gone to and closed
  await page.keyboard.press('/');
  const search = dialog(page, 'Search in book');
  await expect(search).toBeVisible();
  await page.keyboard.type('Para');
  await search.getByRole('region', { name: 'Results' }).getByRole('button').nth(3).click();
  const bar = page.getByRole('toolbar', { name: 'Search results' });
  await expect(bar).toBeVisible();
  await bar.getByRole('button', { name: 'Close search' }).click();
  await expect(bar).toBeHidden();
  await unchanged(page);
});
