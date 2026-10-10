// Headings and relative sizes keep their hierarchy under the text size
// setting (#422): Thorium's long-standing complaint is that with the
// reader's font settings every size is regularised to 1em and the
// headings flatten. Quire drops the book's CSS and sets one size on the
// page, so the elements' own relative sizes (the browser's default sheet
// and the rules of the stylesheet) must scale with it. The books are in
// heading-books.js, checked by epubcheck.spec.js.

import { test, expect } from './fixtures.js';
import { start, readBook, bookPage, openReadingSettings, readingSettings } from './helpers.js';
import { cutOff } from './controls-shown.js';
import { headingBooks } from './heading-books.js';

const SIZES = [12, 18, 32];

const px = (page, selector, text) => bookPage(page).locator(selector, text ? { hasText: text } : undefined).first()
  .evaluate(e => parseFloat(getComputedStyle(e).fontSize));
const slider = (page, name) => readingSettings(page).getByRole('slider', { name });

async function setSize(page, size) {
  await openReadingSettings(page, 'Look');
  await slider(page, 'Size').fill(String(size));
  await page.keyboard.press('Escape');
  await expect.poll(async () => px(page, 'p')).toBe(size);
}

test('h1 > h2 > h3 > h4 > text at every size, the same ratios at the smallest and the largest', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, headingBooks.hierarchy.opts);
  const ratios = [];
  for (const size of SIZES) {
    await setSize(page, size);
    const h = [];
    for (const tag of ['h1', 'h2', 'h3', 'h4']) h.push(await px(page, tag));
    const text = await px(page, 'p', 'Body text');
    expect(h[0], `h1 at ${size}`).toBeGreaterThan(h[1]);
    expect(h[1], `h2 at ${size}`).toBeGreaterThan(h[2]);
    expect(h[2], `h3 at ${size}`).toBeGreaterThan(h[3]);
    expect(h[3], `h4 at ${size}`).toBeGreaterThanOrEqual(text);
    expect(h[2], `h3 at ${size}`).toBeGreaterThan(text);
    ratios.push(h.map(v => +(v / text).toFixed(2)));
  }
  // sizes scale: the ratios do not change with the size
  expect(ratios[1]).toEqual(ratios[0]);
  expect(ratios[2]).toEqual(ratios[0]);
  expect(errors).toEqual([]);
});

test('small, sub, sup, a caption and a footnote are smaller than the text and scale with it', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, headingBooks.hierarchy.opts);
  for (const size of SIZES) {
    await setSize(page, size);
    const text = await px(page, 'p', 'Body text');
    const sizes = {
      small: await px(page, 'small'),
      sub: await px(page, 'sub'),
      sup: await px(page, 'sup'),
      caption: await px(page, 'figcaption'),
      note: await px(page, 'aside, div', "A footnote's text."),
    };
    for (const [name, value] of Object.entries(sizes)) expect(value, `${name} at ${size}`).toBeLessThan(text);
  }
  expect(errors).toEqual([]);
});

test('headings keep their hierarchy when the book gives them sizes of its own', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, headingBooks.inlineSizes.opts);
  const h1 = await px(page, 'h1'), h2 = await px(page, 'h2'), h3 = await px(page, 'h3');
  const text = await px(page, 'p', 'Body text');
  expect(h1).toBeGreaterThan(h2);
  expect(h2).toBeGreaterThan(h3);
  expect(h3).toBeGreaterThan(text);
  // and the body's own 30px is not applied
  expect(text).toBeLessThan(30);
  expect(errors).toEqual([]);
});

test('a heading is never cut or wider than the page at the largest size, and apart from the text', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, headingBooks.longHeading.opts);
  await setSize(page, 32);
  const area = await bookPage(page).boundingBox();
  for (const tag of ['h1', 'h2']) {
    const rects = await bookPage(page).locator(tag).first().evaluate(e => [...e.getClientRects()].map(r => ({ width: r.width })));
    for (const r of rects) {
      // a rect may lie in a later column, so its width is what is bounded
      expect(r.width, `${tag} width`).toBeLessThanOrEqual(area.width + 1);
    }
  }
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  // a heading's margins keep it apart from the text after it, at every size
  for (const size of SIZES) {
    await setSize(page, size);
    const gap = await bookPage(page).evaluate(doc => {
      const h = doc.querySelector('h2'), p = doc.querySelector('p');
      const a = h.getClientRects(), b = p.getClientRects();
      return b[0].top - a[a.length - 1].bottom;
    });
    expect(gap, `gap after the heading at ${size}`).toBeGreaterThan(0);
  }
  expect(await cutOff(page)).toEqual([]);
  expect(errors).toEqual([]);
});

test('line height and paragraph spacing scale with the size, as the settings say', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, headingBooks.hierarchy.opts);
  const metrics = async () => bookPage(page).locator('p', { hasText: 'Body text' }).first()
    .evaluate(e => { const cs = getComputedStyle(e); return { size: parseFloat(cs.fontSize), line: parseFloat(cs.lineHeight), margin: parseFloat(cs.marginBlockEnd) }; });
  await setSize(page, 16);
  const a = await metrics();
  await setSize(page, 32);
  const b = await metrics();
  expect(b.line / b.size).toBeCloseTo(a.line / a.size, 1);
  expect(b.margin).toBeGreaterThan(a.margin);
  expect(errors).toEqual([]);
});
