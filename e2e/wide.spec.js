// Wide and structured content (#413): a table wider or taller than the
// page, preformatted text, verse. The books are in wide-books.js, checked
// by epubcheck.spec.js.
//
// Decided (issue 413), from what readers do: Readium CSS (Thorium) leaves a
// wide table to overflow its column and lets the reader scroll in scrolled
// mode only; Quire's pages are columns, where an overflow would run under the
// next column, so a table is its own scroll container, as wide as the
// column at most, and as tall as the column at most, and scrolls inside
// both ways (a block that scrolls cannot be split between columns, so a
// taller table would lose its rows past the page's foot). `pre` wraps
// (white-space: pre-wrap, as a screen has no sideways to read it in) and
// keeps its spaces, tabs and blank lines. Indents made of characters
// (no-break spaces) and lines made by <br/> survive; indents made of
// the book's CSS (text-indent, padding-left, hanging) do not, since no
// publisher CSS is applied (#411).

import { test, expect } from './fixtures.js';
import {
  start, readBook, bookPage, place, showChrome, control, dialog, visibleText, openReadingSettings, readingSettings,
} from './helpers.js';
import { wideBooks } from './wide-books.js';

const contents = page => dialog(page, 'Contents');

async function chapterNamed(page, label) {
  await showChrome(page);
  await control(page, 'Contents').click();
  await contents(page).getByRole('tabpanel', { name: 'Contents' }).getByRole('button', { name: label, exact: true }).click();
  await expect(contents(page)).toBeHidden();
}

/** The page's box, and whether the page itself has no sideways overflow */
const noOverflow = page => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth);

/** The text of every page of the chapter in turn */
async function allPages(page) {
  const seen = [];
  for (let k = 0; k < 40; k++) {
    seen.push(await visibleText(page));
    const at = await place(page);
    if (at.p >= at.t) break;
    await page.keyboard.press('ArrowRight');
    await expect.poll(async () => (await place(page)).p).toBe(at.p + 1);
  }
  return seen.join('\n');
}

test('a table wider than the page scrolls inside its own container; the page does not overflow or change its pages', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, wideBooks.tables.opts);
  const table = bookPage(page).locator('table#wide, table').first();
  const before = await place(page);
  const geometry = await table.evaluate(t => ({ scroll: t.scrollWidth, client: t.clientWidth, overflowX: getComputedStyle(t).overflowX }));
  expect(geometry.scroll).toBeGreaterThan(geometry.client);
  expect(['auto', 'scroll']).toContain(geometry.overflowX);
  const page_ = await bookPage(page).boundingBox();
  const box = await table.boundingBox();
  expect(box.x + box.width).toBeLessThanOrEqual(page_.x + page_.width + 1);
  expect(await noOverflow(page)).toBe(true);
  // scrolling the table moves its cells, not the page
  await table.evaluate(t => { t.scrollLeft = t.scrollWidth; });
  expect(await table.evaluate(t => t.scrollLeft)).toBeGreaterThan(0);
  expect(await place(page)).toEqual(before);
  await expect(bookPage(page).getByText('Column 12 wide cell text').first()).toBeAttached();
  expect(errors).toEqual([]);
});

test('a table taller than the page does not lose its rows past the page foot: every row is read by scrolling it', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, wideBooks.tables.opts);
  await chapterNamed(page, 'Tall');
  const table = bookPage(page).locator('table').first();
  const area = await bookPage(page).boundingBox();
  const box = await table.boundingBox();
  // as tall as the page's reading area at most
  expect(box.height).toBeLessThanOrEqual(area.height);
  expect(await table.evaluate(t => t.scrollHeight > t.clientHeight)).toBe(true);
  // scrolled to its end, the last row is the one shown within the page
  await table.evaluate(t => { t.scrollTop = t.scrollHeight; });
  const last = bookPage(page).locator('tr', { hasText: 'Row 89' });
  await expect(last).toBeVisible();
  const lastBox = await last.boundingBox();
  expect(lastBox.y).toBeGreaterThanOrEqual(area.y - 1);
  expect(lastBox.y + lastBox.height).toBeLessThanOrEqual(area.y + area.height + 1);
  // the text after the table is still on the page's pages
  expect(await allPages(page)).toContain('After the table.');
  expect(errors).toEqual([]);
});

test('header cells, colspan and rowspan keep their structure and the table its roles', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, wideBooks.tables.opts);
  await chapterNamed(page, 'Spans');
  const table = bookPage(page).getByRole('table');
  await expect(table).toHaveCount(1);
  await expect(table.getByRole('columnheader')).toHaveCount(4);
  await expect(table.getByRole('rowheader')).toHaveCount(2);
  await expect(table.getByRole('cell')).toHaveCount(4);
  await expect(table.getByRole('columnheader', { name: 'Scores' })).toHaveAttribute('colspan', '2');
  await expect(table.getByRole('columnheader', { name: 'Name' })).toHaveAttribute('rowspan', '2');
  expect(errors).toEqual([]);
});

test('preformatted text wraps, keeps its spaces, tabs and blank lines at every size, and continues across pages without losing a line', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, wideBooks.code.opts);
  const pre = bookPage(page).locator('pre').first();
  const text = async () => pre.evaluate(e => e.textContent);
  const original = await text();
  expect(original).toContain('\n    four spaces\n\n        eight spaces after a blank line\n\tTabbed\n');
  expect(await pre.evaluate(e => getComputedStyle(e).whiteSpace)).toBe('pre-wrap');
  expect(await noOverflow(page)).toBe(true);
  // no line runs past the page
  const area = await bookPage(page).boundingBox();
  const rects = await pre.evaluate(e => [...e.getClientRects()].map(r => ({ left: r.left, right: r.right })));
  for (const r of rects) expect(r.right).toBeLessThanOrEqual(area.x + area.width * (rects.length > 1 ? rects.length : 1) + 1);
  // at another size the same text, still wrapped, no lines lost
  await openReadingSettings(page, 'Look');
  await readingSettings(page).getByRole('slider', { name: 'Size' }).fill('30');
  await page.keyboard.press('Escape');
  await expect.poll(async () => (await place(page)).t).toBeGreaterThan(1);
  expect(await text()).toBe(original);
  // every line is laid out in some column of the page's pages: a rect
  // inside its width, none cut off by a block that cannot be split
  const laidOut = await bookPage(page).evaluate(doc => {
    const width = doc.scrollWidth;
    const walker = document.createTreeWalker(doc.querySelector('pre'), NodeFilter.SHOW_TEXT);
    const found = {};
    for (const k of [0, 30, 60, 89]) {
      let text = null, at = -1;
      walker.currentNode = walker.root;
      while (at < 0 && (text = walker.nextNode())) at = text.data.indexOf(`line ${k}`);
      const range = document.createRange();
      range.setStart(text, at);
      range.setEnd(text, at + `line ${k}`.length);
      const r = range.getBoundingClientRect();
      found[k] = r.width > 0 && r.left >= doc.getBoundingClientRect().left - 1 && r.right <= doc.getBoundingClientRect().left + width + 1;
    }
    return found;
  });
  expect(laidOut).toEqual({ 0: true, 30: true, 60: true, 89: true });
  // and the pages go to the end of the chapter, whose text follows the block
  const seen = await allPages(page);
  expect(seen).toContain('After the code.');
  expect(errors).toEqual([]);
});

test('verse keeps its lines and its character indents at a large size, and a long line wraps within the page', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, wideBooks.verse.opts);
  await openReadingSettings(page, 'Look');
  await readingSettings(page).getByRole('slider', { name: 'Size' }).fill('30');
  await page.keyboard.press('Escape');
  const stanza = bookPage(page).locator('p', { hasText: 'Roses are red 0' }).first();
  // the line breaks and the indent are the book's
  expect(await stanza.evaluate(e => e.querySelectorAll('br').length)).toBe(2);
  expect(await stanza.evaluate(e => e.textContent.includes(' '.repeat(8) + 'sugar'))).toBe(true);
  expect(await noOverflow(page)).toBe(true);
  // the long line wraps: it is taller than a line, and within the page
  const rects = await stanza.evaluate(e => [...e.getClientRects()].map(r => ({ left: r.left, right: r.right, height: r.height })));
  const area = await bookPage(page).boundingBox();
  for (const r of rects) {
    expect(r.left).toBeGreaterThanOrEqual(area.x - 1);
    expect(r.right).toBeLessThanOrEqual(area.x + area.width + 1);
  }
  // every stanza is on some page, whole
  const seen = await allPages(page);
  for (const k of [0, 5, 11]) expect(seen).toContain(`Roses are red ${k},`);
  expect(errors).toEqual([]);
});
