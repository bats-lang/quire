// The cards' titles are read in one evaluation, so a library drawn again
// while they are read never gives a detached card's text (#575: the CI red
// of library-records QLB4, whose cards were replaced between a locator's
// find and its read; helpers.js `titles`).

import { test, expect } from './fixtures.js';
import { legacyLibrary, put, forgetRecords, syncEnded, reloadSettled } from './legacy-library.js';
import { start, cards, titles } from './helpers.js';

const books = [
  { idHigh: 0x1234567, idLow: 0x0abcdef, title: 'Alpha Tales', author: 'Ann Writer' },
  { idHigh: 0x3456789, idLow: 0x2cdef01, title: 'Gamma Days', author: 'Cy Penn' },
];

test('the titles are the cards\' first lines while the cards are replaced every millisecond', async ({ page }) => {
  await start(page);
  await syncEnded(page);
  await forgetRecords(page);
  await put(page, 'lib', [...legacyLibrary(6, [], books)]);
  await reloadSettled(page);
  await expect(cards(page)).toHaveCount(2);
  // the list's cards are replaced by copies, as a redraw does
  await page.evaluate(() => {
    const list = document.getElementById('book-list');
    globalThis.__redraw = setInterval(() => list.replaceChildren(...[...list.children].map(child => child.cloneNode(true))), 1);
  });
  for (let i = 0; i < 40; i++) expect(await titles(page)).toEqual(['Alpha Tales', 'Gamma Days']);
  await page.evaluate(() => clearInterval(globalThis.__redraw));
  // the read this replaces: the same redraw, and the locator's two calls
  await page.evaluate(() => {
    const list = document.getElementById('book-list');
    globalThis.__redraw = setInterval(() => list.replaceChildren(...[...list.children].map(child => child.cloneNode(true))), 1);
  });
  let detached = 0;
  for (let i = 0; i < 40; i++) {
    const texts = await cards(page).allInnerTexts();
    if (texts.some(text => !text.includes('\n'))) detached++;
  }
  await page.evaluate(() => clearInterval(globalThis.__redraw));
  test.info().annotations.push({ type: 'detached reads', description: `${detached} of 40 allInnerTexts reads gave a detached card's text` });
  expect(detached, 'allInnerTexts read detached cards').toBeGreaterThan(0);
});
