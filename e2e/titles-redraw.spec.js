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

const redraw = `setInterval(() => {
  const list = document.querySelector('[role=region][aria-label="Books"]');
  list.replaceChildren(...[...list.children].map(child => child.cloneNode(true)));
}, 1)`;

test('the titles are the cards\' first lines while the cards are replaced every millisecond', async ({ page }) => {
  await start(page);
  await syncEnded(page);
  await forgetRecords(page);
  await put(page, 'lib', [...legacyLibrary(6, [], books)]);
  await reloadSettled(page);
  await expect(cards(page)).toHaveCount(2);
  // the list's cards are replaced by copies, as a redraw does
  await page.evaluate(`globalThis.__redraw = ${redraw}`);
  for (let i = 0; i < 40; i++) expect(await titles(page)).toEqual(['Alpha Tales', 'Gamma Days']);
  await page.evaluate(() => clearInterval(globalThis.__redraw));
});

// The control, with no timing in it: a card found before the list is drawn again is detached when it is read, and a detached
// element's innerText has no line break, so the whole card was the "title". This is what a read in two calls (find, then read) gives.
test('a card found before the list is drawn again reads as its whole text', async ({ page }) => {
  await start(page);
  await syncEnded(page);
  await forgetRecords(page);
  await put(page, 'lib', [...legacyLibrary(6, [], books)]);
  await reloadSettled(page);
  await expect(cards(page)).toHaveCount(2);
  const found = await cards(page).first().elementHandle();
  await page.evaluate(() => {
    const list = document.querySelector('[role=region][aria-label="Books"]');
    list.replaceChildren(...[...list.children].map(child => child.cloneNode(true)));
  });
  const read = await found.evaluate(element => ({ connected: element.isConnected, hasLineBreak: element.innerText.includes('\n') }));
  expect(read).toEqual({ connected: false, hasLineBreak: false });
  expect(await titles(page)).toEqual(['Alpha Tales', 'Gamma Days']);
});
