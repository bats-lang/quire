// A search over a book of many chapters keeps the page answering (quire#849): the chapters are
// read, inflated and walked one task each, so an input made while the search goes on is
// handled between two chapters and not after the last one. The book is made by code
// (e2e/pathological-books.js): sixty chapters of about 400 KB, none holding the searched word,
// so the search has to walk them all.

import { test, expect } from './fixtures.js';
import { start, readBook, dialog } from './helpers.js';
import { book, plainChapter } from './pathological-books.js';

const CHAPTERS = 60;
const PARAGRAPHS = 1200;

const manyChaptersBook = () =>
  book('Many Chapters', Array.from({ length: CHAPTERS }, (_, k) => plainChapter(PARAGRAPHS, `Part${k + 1}`, false)));

const panel = page => dialog(page, 'Search in book');
const box = page => panel(page).getByRole('searchbox', { name: 'Search in book' });
const summary = page => panel(page).getByRole('status');

test('a click during the search of a book of many chapters is handled before the search ends', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, manyChaptersBook());
  await page.keyboard.press('/');
  await expect(box(page)).toBeFocused();
  // the page notes when a click is handled and when the search says it is done
  await page.evaluate(() => {
    const times = { click: null, done: null };
    window.searchTimes = times;
    document.addEventListener('click', () => { times.click ??= performance.now(); }, true);
    const status = document.getElementById('search-status');
    new MutationObserver(() => {
      if (status.textContent === 'No results') times.done ??= performance.now();
    }).observe(status, { childList: true, characterData: true, subtree: true });
  });
  await box(page).fill('Wordnoparagraphhas');
  await expect(summary(page)).toHaveText('Searching…');
  // an input made while it goes on
  await box(page).click();
  await expect(summary(page)).toHaveText('No results', { timeout: 120000 });
  const times = await page.evaluate(() => window.searchTimes);
  expect(times.click).not.toBeNull();
  expect(times.done).not.toBeNull();
  expect(times.click).toBeLessThan(times.done);
  expect(errors).toEqual([]);
});
