// Searching the book: every chapter, results listed with their
// chapter, gone to with the match marked, stepped through, and closed
// back to where reading was.

import { test, expect } from '@playwright/test';
import {
  start, readBook, place, showChrome, selectText, marks, chapters, dialog, selectionButton,
} from './helpers.js';

const panel = page => dialog(page, 'Search in book');
const box = page => panel(page).getByRole('searchbox', { name: 'Search in book' });
const summary = page => panel(page).getByRole('status');
const results = page => panel(page).getByRole('region', { name: 'Results' }).getByRole('button');
const bar = page => page.getByRole('toolbar', { name: 'Search results' });
const barButton = (page, name) => bar(page).getByRole('button', { name });

const rawChapters = [1, 2, 3].map(i => ({
  body: `<h1>Part ${i}</h1>` + Array.from({ length: 20 }, (_, k) =>
    `<p>Para ${i}.${k} ` + 'lorem ipsum dolor sit amet '.repeat(12) + (k === 15 ? ' the Zebra&amp;crossing ' : '') + '</p>').join(''),
}));
const book = { title: 'Searchable', author: 'Search Tests', rawChapters };

test('the book is searched, and the results are gone to and stepped through', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, book);
  await page.keyboard.press('/');
  await expect(panel(page)).toBeVisible();
  await expect(box(page)).toBeFocused();
  // letters in any case, entities decoded
  await page.keyboard.type('zebra&c');
  await expect(summary(page)).toHaveText('3 results');
  const rows = results(page);
  await expect(rows).toHaveCount(3);
  await expect(rows.nth(1)).toContainText('Chapter 2');
  await expect(rows.nth(1)).toContainText('Zebra&crossing');
  // typing did not turn pages or bookmark
  expect(await place(page)).toMatchObject({ ch: 1, p: 1 });
  await rows.nth(1).click();
  await expect(panel(page)).toBeHidden();
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'Zebra&c' });
  await expect(bar(page)).toContainText('2 of 3');
  await barButton(page, 'Next result').click();
  await expect(bar(page)).toContainText('3 of 3');
  await expect.poll(async () => (await place(page)).ch).toBe(3);
  await barButton(page, 'Next result').click();
  await expect(bar(page)).toContainText('1 of 3');
  await expect.poll(async () => (await place(page)).ch).toBe(1);
  await barButton(page, 'Previous result').click();
  await expect(bar(page)).toContainText('3 of 3');
  // closing goes back to where reading was
  await barButton(page, 'Close search').click();
  await expect(bar(page)).toBeHidden();
  await expect.poll(async () => JSON.stringify(await place(page))).toMatch(/"ch":1,"p":1,/);
  await expect.poll(() => marks(page)).toMatchObject({ size: 0 });
  expect(errors).toEqual([]);
});

test('Enter in the search box goes to the next result; Escape closes it', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await showChrome(page);
  await page.getByRole('button', { name: 'Search in book' }).click();
  await box(page).fill('zebra');
  await expect(summary(page)).toHaveText('3 results');
  await box(page).press('Enter');
  await expect(bar(page)).toContainText('1 of 3');
  await expect.poll(async () => (await place(page)).p).toBeGreaterThan(1);
  await page.keyboard.press('Escape');
  await expect(bar(page)).toBeHidden();
  await expect.poll(async () => JSON.stringify(await place(page))).toMatch(/"ch":1,"p":1,/);
});

test('a search that finds nothing says so', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Nothing Here', author: 'Search Tests', rawChapters: chapters(2, 5) });
  await page.keyboard.press('/');
  await page.keyboard.type('xylophone');
  await expect(summary(page)).toHaveText('No results');
  await expect(results(page)).toHaveCount(0);
});

test('the selection can be searched for', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await selectText(page, 0, 4);
  await selectionButton(page, 'Search').click();
  await expect(panel(page)).toBeVisible();
  await expect(box(page)).toHaveValue('Para');
  await expect(summary(page)).toHaveText('60 results');
});
