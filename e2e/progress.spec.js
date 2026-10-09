// How far through the book the reader is (#426). The percentage is the
// text read, weighted by the chapters' sizes as the reader's footer and
// scrubber weigh it (Readium's positions and Kobo do the same), ends where
// the book's text ends (the landmarks' back matter weighs nothing), and a
// fixed-layout book counts its spine items as the page indicator does. The
// footer's "% of book", the scrubber, the library card and Book info say
// the same number. The books are in progress-books.js, checked by
// epubcheck.spec.js.

import { test, expect } from './fixtures.js';
import {
  start, readBook, openBook, card, cards, place, toLibrary, bookMenu, menuItem, dialog, showChrome, titles,
  importFiles, epubFile, rawFile, oneColumn, readFixed, fixedPlace, libraryMenu, importInput,
  librarySettings, settingsButton, restoreInput, exportedBackup,
} from './helpers.js';
import { progressBooks } from './progress-books.js';

const show = page => page.getByRole('group', { name: 'Show' });
const ofBook = page => page.locator('[aria-hidden="true"]').getByText(/· (<1|\d+)% of book$/);
const scrubber = page => page.getByRole('slider', { name: 'Place in book', includeHidden: true });

/** The footer's "% of book" (never 0 once begun: "<1" reads as 0) */
async function footerPercent(page) {
  const m = /· (<1|\d+)% of book$/.exec((await ofBook(page).textContent()).trim());
  expect(m, 'the footer says how far into the book').not.toBeNull();
  return m[1] === '<1' ? 0 : +m[1];
}

const scrubberPercent = async page => +(await scrubber(page).getAttribute('aria-valuenow'));

/** The footer's and the scrubber's percentages, which are one number */
async function percent(page) {
  const footer = await footerPercent(page);
  expect(await scrubberPercent(page)).toBe(footer);
  return footer;
}

/** The library card's percentage ("Done" is 100) */
async function cardPercent(page, title) {
  const text = await card(page, title).innerText();
  if (/\bDone\b/.test(text)) return 100;
  const m = /(\d+)%/.exec(text);
  expect(m, `card "${text}" says how far`).not.toBeNull();
  return +m[1];
}

/** Book info's percentage */
async function infoPercent(page, title) {
  await bookMenu(page, title);
  await menuItem(page, 'Book info').click();
  const info = dialog(page, 'Book info');
  await expect(info).toBeVisible();
  const m = /(\d+)%\s*·\s*Ch/.exec(await info.innerText());
  expect(m, 'Book info says how far').not.toBeNull();
  await info.getByRole('button', { name: '← Library' }).click();
  await expect(info).toBeHidden();
  return +m[1];
}

/** On the last page of the chapter shown */
const onLastPage = async page => { const here = await place(page); return here.p === here.t; };

/** The first page of chapter (from 1), by the keys */
async function toChapter(page, chapter) {
  for (;;) {
    const here = await place(page);
    if (here.ch >= chapter) return;
    await page.keyboard.press('End');
    await expect.poll(() => onLastPage(page)).toBe(true);
    await page.keyboard.press('ArrowRight');
    await expect.poll(async () => (await place(page)).ch).toBeGreaterThan(here.ch);
  }
}

/** The last page of chapter (from 1) */
async function toChapterEnd(page, chapter) {
  await toChapter(page, chapter);
  await page.keyboard.press('End');
  await expect.poll(() => onLastPage(page)).toBe(true);
}

/** What the footer, the scrubber, the card and Book info say at the page
    shown, which is back in the reader after: all one number */
async function everywhere(page, title) {
  const shown = await percent(page);
  await toLibrary(page);
  const onCard = await cardPercent(page, title);
  const inInfo = await infoPercent(page, title);
  expect(onCard).toBe(shown);
  expect(inInfo).toBe(shown);
  await openBook(page, title);
  return shown;
}

test('three chapters of one size read about a third, two thirds and all at their ends, and the card, Book info, the footer and the scrubber agree', async ({ page }) => {
  const errors = await start(page);
  const { title } = progressBooks.threeEqual.opts;
  await readBook(page, progressBooks.threeEqual.opts);
  await oneColumn(page);
  await page.keyboard.press('t');
  await toChapterEnd(page, 1);
  const first = await everywhere(page, title);
  expect(first).toBeGreaterThanOrEqual(24);
  expect(first).toBeLessThanOrEqual(34);
  await toChapterEnd(page, 2);
  const second = await everywhere(page, title);
  expect(second).toBeGreaterThanOrEqual(57);
  expect(second).toBeLessThanOrEqual(67);
  // the end of the text is the end: 100% everywhere, and the book is finished
  await toChapterEnd(page, 3);
  expect(await percent(page)).toBe(100);
  await toLibrary(page);
  expect(await cardPercent(page, title)).toBe(100);
  await expect(card(page, title)).toContainText('Done');
  expect(await infoPercent(page, title)).toBe(100);
  expect(errors).toEqual([]);
});

test('back matter after the text weighs nothing: the end of the text reads 100%, and the last page of the index shows no jump', async ({ page }) => {
  const errors = await start(page);
  const { title } = progressBooks.backMatter.opts;
  await readBook(page, progressBooks.backMatter.opts);
  await oneColumn(page);
  await page.keyboard.press('t');
  // three chapters of text and three of back matter: counted by chapters
  // the text would end at 50%
  await toChapter(page, 3);
  const third = await percent(page);
  expect(third).toBeGreaterThanOrEqual(60);
  expect(third).toBeLessThanOrEqual(70);
  await toChapterEnd(page, 3);
  expect(await percent(page)).toBe(100);
  // the page before it is close: the last page is no jump
  await page.keyboard.press('ArrowLeft');
  await expect.poll(() => onLastPage(page)).toBe(false);
  const before = await percent(page);
  expect(before).toBeGreaterThanOrEqual(85);
  expect(before).toBeLessThan(100);
  await page.keyboard.press('ArrowRight');
  await expect.poll(() => onLastPage(page)).toBe(true);
  // into the notes, the index and the colophon: still 100%, to the last page of the last
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(4);
  expect(await percent(page)).toBe(100);
  await toChapterEnd(page, 5);
  expect(await percent(page)).toBe(100);
  await toChapterEnd(page, 6);
  expect(await percent(page)).toBe(100);
  // reaching the end of the text finished the book
  await toLibrary(page);
  await expect(card(page, title)).toContainText('Done');
  await show(page).getByRole('button', { name: 'Finished' }).click();
  await expect.poll(() => titles(page)).toEqual([title]);
  expect(errors).toEqual([]);
});

test('a cover, a title page and a copyright page before chapter 1 do not start the book at a large percentage', async ({ page }) => {
  const errors = await start(page);
  // no landmarks: the book opens at its cover
  await readBook(page, progressBooks.frontMatter.opts);
  await page.keyboard.press('t');
  expect(await percent(page)).toBe(0);
  await toChapter(page, 4);
  const body = await percent(page);
  expect(body).toBeLessThanOrEqual(5);
  await toChapterEnd(page, 4);
  const end = await percent(page);
  expect(end).toBeGreaterThanOrEqual(25);
  expect(end).toBeLessThanOrEqual(37);
  await toLibrary(page);
  // landmarks name where the text starts: the book opens there
  await readBook(page, progressBooks.frontMatterLandmarks.opts);
  await expect.poll(async () => (await place(page)).ch).toBe(4);
  await page.keyboard.press('t');
  expect(await percent(page)).toBeLessThanOrEqual(5);
  expect(errors).toEqual([]);
});

test('chapters of very unequal length give a percentage that moves with the text read', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, progressBooks.unequal.opts);
  await page.keyboard.press('t');
  expect(await percent(page)).toBe(0);
  // the middle of the scrubber is the middle of the long chapter: by
  // chapters it would be the fifth
  await showChrome(page);
  const box = await scrubber(page).boundingBox();
  await page.mouse.move(box.x + box.width * 0.45, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.up();
  await expect.poll(async () => (await place(page)).ch).toBe(1);
  await page.keyboard.press('t');
  await expect.poll(async () => { const p = await percent(page); return p >= 38 && p <= 50; }).toBe(true);
  // the long chapter's end is nearly all of the book; the next chapter starts after it
  await page.keyboard.press('End');
  await expect.poll(() => onLastPage(page)).toBe(true);
  const longEnd = await percent(page);
  expect(longEnd).toBeGreaterThanOrEqual(85);
  expect(longEnd).toBeLessThanOrEqual(92);
  await toChapter(page, 2);
  const next = await percent(page);
  expect(next).toBeGreaterThanOrEqual(longEnd);
  expect(next).toBeLessThanOrEqual(93);
  await toChapterEnd(page, 10);
  expect(await percent(page)).toBe(100);
  expect(errors).toEqual([]);
});

test('a fixed-layout book counts its spine items as the indicator does, and is finished at its last', async ({ page }) => {
  const errors = await start(page);
  const { title } = progressBooks.fixedUnequal.opts;
  await readFixed(page, progressBooks.fixedUnequal.opts);
  await page.keyboard.press('t');
  // the first page carries 30 KB of comment: by bytes the second page would read 90%
  for (const [p, expected] of [[1, 0], [2, 20], [3, 40], [4, 60]]) {
    await expect.poll(async () => (await fixedPlace(page)).p).toBe(p);
    expect(await percent(page)).toBe(expected);
    await page.keyboard.press('ArrowRight');
  }
  await expect.poll(async () => (await fixedPlace(page)).p).toBe(5);
  expect(await percent(page)).toBe(100);
  await toLibrary(page);
  await expect(card(page, title)).toContainText('Done');
  expect(await infoPercent(page, title)).toBe(100);
  await show(page).getByRole('button', { name: 'Finished' }).click();
  await expect.poll(() => titles(page)).toEqual([title]);
  expect(errors).toEqual([]);
});

test('a backup keeps how far into the book the place is, weighted by the chapters, and a restore shows it on the card', async ({ page }) => {
  const errors = await start(page);
  const { title } = progressBooks.unequal.opts;
  const file = epubFile(progressBooks.unequal.opts);
  await importFiles(page, [file], 1);
  await openBook(page, title);
  await page.keyboard.press('t');
  await page.keyboard.press('End');
  await expect.poll(() => onLastPage(page)).toBe(true);
  const read = await percent(page);
  // by chapters it would be 10%
  expect(read).toBeGreaterThanOrEqual(85);
  await toLibrary(page);
  expect(await cardPercent(page, title)).toBe(read);
  await librarySettings(page);
  const backup = JSON.parse(await exportedBackup(page));
  // the thousandth plus one
  expect(backup.books[0].progressWeighted).toBeGreaterThan(read * 10);
  expect(backup.books[0].progressWeighted).toBeLessThanOrEqual(read * 10 + 10);
  await settingsButton(page, 'Done').click();
  await librarySettings(page);
  const path = rawFile('quire-backup.json', JSON.stringify(backup));
  // a reset with its Trash emptied, the book imported again: new, until the backup is restored
  await settingsButton(page, 'Factory reset').click();
  await expect(cards(page)).toHaveCount(0);
  await libraryMenu(page);
  await menuItem(page, 'Empty Trash').click();
  await dialog(page, 'Empty the Trash?').getByRole('button', { name: 'Empty' }).click();
  await expect(importInput(page)).toBeVisible();
  await importFiles(page, [file], 1);
  await expect(card(page, title)).toContainText('New');
  await librarySettings(page);
  await restoreInput(page).setInputFiles([path]);
  await dialog(page, 'Backup restored').getByRole('button', { name: 'OK' }).click();
  await expect.poll(() => cardPercent(page, title)).toBe(read);
  expect(errors).toEqual([]);
});
