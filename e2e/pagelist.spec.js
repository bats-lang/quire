// The print edition's page list and page breaks, in the cases a real
// book has (#415): duplicate, out-of-order and odd labels, targets that
// are missing, a very long list, breaks without a list and a list without
// breaks. The numeric, in-order list is in navigation.spec.js. The books
// are in pagelist-books.js, checked by epubcheck.spec.js.

import { test, expect } from './fixtures.js';
import { start, readBook, place, showChrome, control, dialog } from './helpers.js';
import { cutOff } from './controls-shown.js';
import { pagelistBooks } from './pagelist-books.js';

const contents = page => dialog(page, 'Contents');
const footer = page => page.getByText(/^ · page .+ in print$/);

/** Opens the Pages tab; its rows */
async function pagesRows(page) {
  await showChrome(page);
  await control(page, 'Contents').click();
  await contents(page).getByRole('tab', { name: 'Pages' }).click();
  return contents(page).getByRole('tabpanel', { name: 'Pages' }).getByRole('button');
}

/** Goes to the row's page; the panel closes when it leads somewhere */
async function goTo(page, rows, index) {
  await rows.nth(index).click();
  await expect(contents(page)).toBeHidden();
}

/** What the footer says of the page shown (shown with the t key) */
async function footerText(page) {
  await page.keyboard.press('t');
  await page.waitForTimeout(150);
  return (await footer(page).count()) ? (await footer(page).textContent()) : null;
}

test('entries with the same label each go to their own target, and the footer names the page the page is on', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagelistBooks.duplicates.opts);
  let rows = await pagesRows(page);
  await expect(rows).toHaveText(['12', '12']);
  await goTo(page, rows, 1);
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  expect(await footerText(page)).toBe(' · page 12 in print');
  rows = await pagesRows(page);
  await goTo(page, rows, 0);
  await expect.poll(async () => (await place(page)).ch).toBe(1);
  expect(errors).toEqual([]);
});

test('roman front matter and then arabic pages are listed as the book gives them, and named by the footer', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagelistBooks.romanThenArabic.opts);
  const rows = await pagesRows(page);
  await expect(rows).toHaveText(['i', 'ii', '1', '2']);
  await goTo(page, rows, 1);
  expect(await footerText(page)).toBe(' · page ii in print');
  const again = await pagesRows(page);
  await goTo(page, again, 3);
  expect(await footerText(page)).toBe(' · page 2 in print');
  expect(errors).toEqual([]);
});

test('an entry whose target is missing is listed and does nothing; the others go on working', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagelistBooks.missingTargets.opts);
  const rows = await pagesRows(page);
  await expect(rows).toHaveText(['1', '2', '3', '4']);
  // a chapter the book lacks: nothing moves, the panel stays, no banner
  await rows.nth(1).click();
  await expect(contents(page)).toBeVisible();
  await expect(page.getByRole('alert')).toBeHidden();
  // a fragment the chapter lacks: its chapter, from the top
  await goTo(page, rows, 2);
  await expect.poll(async () => (await place(page)).ch).toBe(1);
  const again = await pagesRows(page);
  await goTo(page, again, 3);
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  expect(await footerText(page)).toBe(' · page 3 in print');
  await expect(page.getByRole('alert')).toBeHidden();
  expect(errors).toEqual([]);
});

test('an entry with no fragment goes to its chapter, and names no print page where the text has no break', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagelistBooks.wholeChapter.opts);
  const rows = await pagesRows(page);
  await expect(rows).toHaveText(['1', '9']);
  await goTo(page, rows, 1);
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  expect(await footerText(page)).toBeNull();
  expect(errors).toEqual([]);
});

test('a page list out of reading order is listed as the book gives it, the footer follows the reading position', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagelistBooks.outOfOrder.opts);
  const rows = await pagesRows(page);
  await expect(rows).toHaveText(['6', '1', '5']);
  await goTo(page, rows, 1);
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  expect(await footerText(page)).toBe(' · page 1 in print');
  const again = await pagesRows(page);
  await goTo(page, again, 2);
  expect(await footerText(page)).toBe(' · page 5 in print');
  expect(errors).toEqual([]);
});

test('a list of several hundred pages lists, and goes to the last one', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagelistBooks.long.opts);
  const rows = await pagesRows(page);
  await expect(rows).toHaveCount(600);
  await rows.nth(599).scrollIntoViewIfNeeded();
  await goTo(page, rows, 599);
  expect(await footerText(page)).toBe(' · page 600 in print');
  expect(errors).toEqual([]);
});

test('an empty page list shows no Pages tab', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagelistBooks.emptyList.opts);
  await showChrome(page);
  await control(page, 'Contents').click();
  await expect(contents(page).getByRole('tab', { name: 'Contents' })).toBeVisible();
  await expect(contents(page).getByRole('tab', { name: 'Pages' })).toBeHidden();
  expect(errors).toEqual([]);
});

test('odd labels (a Devanagari numeral, an empty one, a long one, character references) are shown whole and not cut', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagelistBooks.oddLabels.opts);
  const rows = await pagesRows(page);
  await expect(rows).toHaveCount(5);
  await expect(rows.nth(0)).toHaveText('\u0967');
  // a label of only a no-break space is an entry with no label
  await expect(rows.nth(1)).toHaveText('Untitled');
  const long = pagelistBooks.oddLabels.opts.pageList[2].label;
  await expect(rows.nth(2)).toHaveText(long);
  // numeric and named character references are the characters they name
  await expect(rows.nth(3)).toHaveText('Caf\u00e9 \u2019s & co');
  // a label over the most bytes is cut at a whole character
  const cut = (await rows.nth(4).textContent()).trim();
  expect(cut).toMatch(/^\u65e5+$/);
  expect(cut.length).toBeGreaterThan(40);
  expect(cut.length).toBeLessThan(80);
  expect(await cutOff(page)).toEqual([]);
  expect(errors).toEqual([]);
});

test('role doc-pagebreak markers name the page as epub:type ones do, with no page list', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagelistBooks.roleOnly.opts);
  expect(await footerText(page)).toBe(' · page 7 in print');
  await showChrome(page);
  await control(page, 'Contents').click();
  await expect(contents(page).getByRole('tab', { name: 'Pages' })).toBeHidden();
  expect(errors).toEqual([]);
});

test('a page list whose targets are not page breaks goes to them, and the footer names no page', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagelistBooks.noBreaks.opts);
  const rows = await pagesRows(page);
  await expect(rows).toHaveText(['1', '2']);
  await goTo(page, rows, 1);
  expect(await footerText(page)).toBeNull();
  expect(errors).toEqual([]);
});

// Decided (issue 415): the footer names the latest page the screen
// reaches, the one at its foot, where a printed folio would have turned
// over by then (no reading system documents a rule for two breaks on one
// screen; Readium's navigator takes the first visible position for the
// current locator, so the other choice is the first). A break at the very
// start of a chapter names its page on the first screen, and one at its
// very end on the last.
test('breaks at the start and end of a chapter and several on one screen name the latest page the screen reaches', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagelistBooks.twoOnScreen.opts);
  expect(await footerText(page)).toBe(' · page 3 in print');
  // a jump to either of the two in the paragraph lands on its own
  for (const row of [1, 2]) {
    const rows = await pagesRows(page);
    await goTo(page, rows, row);
    await expect.poll(async () => (await place(page)).p).toBe(1);
  }
  const rows = await pagesRows(page);
  await goTo(page, rows, 3);
  expect(await footerText(page)).toBe(' · page 4 in print');
  expect(errors).toEqual([]);
});
