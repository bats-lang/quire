// Searching the book: every chapter, results listed with their
// chapter, gone to with the match marked, stepped through, and closed
// back to where reading was.

import { test, expect } from '@playwright/test';
import { start, readBook, place, showChrome, selectText, marks, chapters } from './helpers.js';

const rawChapters = [1, 2, 3].map(i => ({
  body: `<h1>Part ${i}</h1>` + Array.from({ length: 20 }, (_, k) =>
    `<p>Para ${i}.${k} ` + 'lorem ipsum dolor sit amet '.repeat(12) + (k === 15 ? ' the Zebra&amp;crossing ' : '') + '</p>').join(''),
}));
const book = { title: 'Searchable', author: 'Search Tests', rawChapters };

test('the book is searched, and the results are gone to and stepped through', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, book);
  await page.keyboard.press('/');
  await expect(page.locator('#qsrp')).toBeVisible();
  await expect(page.locator('#qsri')).toBeFocused();
  // letters in any case, entities decoded
  await page.keyboard.type('zebra&c');
  await expect(page.locator('#qsrm')).toHaveText('3 results');
  const rows = page.locator('#qsrl [id^=qh]:not([id^=qhc]):not([id^=qhs])');
  await expect(rows).toHaveCount(3);
  await expect(rows.nth(1)).toContainText('Chapter 2');
  await expect(rows.nth(1)).toContainText('Zebra&crossing');
  // typing did not turn pages or bookmark
  expect(await place(page)).toMatchObject({ ch: 1, p: 1 });
  await rows.nth(1).click();
  await expect(page.locator('#qsrp')).toBeHidden();
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  await expect.poll(() => marks(page, 2)).toEqual({ size: 1, text: 'Zebra&c' });
  await expect(page.locator('#qsrc')).toHaveText('2 of 3');
  await page.locator('#qsrw').click();
  await expect(page.locator('#qsrc')).toHaveText('3 of 3');
  await expect.poll(async () => (await place(page)).ch).toBe(3);
  await page.locator('#qsrw').click();
  await expect(page.locator('#qsrc')).toHaveText('1 of 3');
  await expect.poll(async () => (await place(page)).ch).toBe(1);
  await page.locator('#qsrv').click();
  await expect(page.locator('#qsrc')).toHaveText('3 of 3');
  // closing goes back to where reading was
  await page.locator('#qsrz').click();
  await expect(page.locator('#qsrn')).toBeHidden();
  await expect.poll(async () => JSON.stringify(await place(page))).toMatch(/"ch":1,"p":1,/);
  await expect.poll(() => marks(page, 2)).toMatchObject({ size: 0 });
  expect(errors).toEqual([]);
});

test('Enter in the search box goes to the next result; Escape closes it', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await showChrome(page);
  await page.locator('#qsch').click();
  await page.locator('#qsri').fill('zebra');
  await expect(page.locator('#qsrm')).toHaveText('3 results');
  await page.locator('#qsri').press('Enter');
  await expect(page.locator('#qsrc')).toHaveText('1 of 3');
  await expect.poll(async () => (await place(page)).p).toBeGreaterThan(1);
  await page.keyboard.press('Escape');
  await expect(page.locator('#qsrn')).toBeHidden();
  await expect.poll(async () => JSON.stringify(await place(page))).toMatch(/"ch":1,"p":1,/);
});

test('a search that finds nothing says so', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Nothing Here', author: 'Search Tests', rawChapters: chapters(2, 5) });
  await page.keyboard.press('/');
  await page.keyboard.type('xylophone');
  await expect(page.locator('#qsrm')).toHaveText('No results');
  await expect(page.locator('#qsrl [id^=qh]')).toHaveCount(0);
});

test('the selection can be searched for', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await selectText(page, '#qcnt p', 0, 4);
  await page.locator('#qsls').click();
  await expect(page.locator('#qsrp')).toBeVisible();
  await expect(page.locator('#qsri')).toHaveValue('Para');
  await expect(page.locator('#qsrm')).toHaveText('60 results');
});
