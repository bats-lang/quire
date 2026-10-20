// Equations as pictures (#408): a PNG, an SVG drawn in the page and an SVG
// file are pictures of text, so they grow and shrink with the reading size
// as the words beside them do, and a picture of black ink on no ground is
// legible in the dark themes.
//
// By research (keyword: equations as pictures).

import { test, expect } from './fixtures.js';
import { start, bookPage, colours } from './helpers.js';
import { block, readMathBook, setSize, sizeRange, chooseTheme, inkIn, turnTo } from './math-helpers.js';

// the page's fake clock is installed before each test's page opens, so the
// bars' and the hint's timers are run on it by inkIn and not waited for (#657)
test.beforeEach(async ({ page }) => {
  await page.clock.install();
});

const luminance = ([r, g, b]) => {
  const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
};
const contrast = (a, b) => { const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x); return (hi + 0.05) / (lo + 0.05); };

/** The pictures inside the paragraphs rows name: each loaded, and its drawn size */
const sizes = (page, rows) => bookPage(page).evaluate((doc, rows) => rows.map(row => {
  const image = window.found(doc, row).querySelector('img');
  const r = image.getBoundingClientRect();
  return { row, loaded: image.complete && image.naturalWidth > 0, width: r.width, height: r.height };
}), rows);

async function scalesWithSize(page, name, rows) {
  await readMathBook(page, name);
  await expect.poll(async () => (await sizes(page, rows)).every(s => s.loaded)).toBe(true);
  const range = await sizeRange(page);
  const bigger = Math.min(range.max, Math.round(range.value * 1.5));
  const smaller = Math.max(range.min, Math.round(range.value * 0.8));
  const first = await sizes(page, rows);
  await setSize(page, bigger);
  await expect.poll(async () => (await sizes(page, rows))[0].height).toBeGreaterThan(first[0].height * 1.2);
  const large = await sizes(page, rows);
  await setSize(page, smaller);
  await expect.poll(async () => (await sizes(page, rows))[0].height).toBeLessThan(first[0].height);
  const small = await sizes(page, rows);
  first.forEach((was, k) => {
    expect(large[k].height / was.height, `${was.row} at ${bigger}px against ${range.value}px`).toBeCloseTo(bigger / range.value, 1);
    expect(small[k].height / was.height, `${was.row} at ${smaller}px against ${range.value}px`).toBeCloseTo(smaller / range.value, 1);
    expect(large[k].width / was.width, `${was.row} width`).toBeCloseTo(bigger / range.value, 1);
  });
  // and the same again at the size it was
  await setSize(page, range.value);
  await expect.poll(async () => (await sizes(page, rows))[0].height).toBeCloseTo(first[0].height, 0);
  const again = await sizes(page, rows);
  again.forEach((now, k) => expect(Math.abs(now.height - first[k].height)).toBeLessThan(0.75));
}

test('PNG equations, in a line and in a paragraph of their own, scale with the reading size', async ({ page }) => {
  const errors = await start(page);
  await scalesWithSize(page, 'png', ['png-inline-row', 'png-block-row']);
  expect(errors).toEqual([]);
});

test('SVG equations, drawn in the page and as a file, scale with the reading size', async ({ page }) => {
  const errors = await start(page);
  await scalesWithSize(page, 'svg', ['svg-inline-row', 'svg-block-row', 'svg-file-inline-row', 'svg-file-block-row']);
  expect(errors).toEqual([]);
});

for (const theme of ['Light', 'Dark', 'Sepia', 'Grey', 'Night']) {
  test(`black ink on no ground is legible in the ${theme} theme`, async ({ page }) => {
    const errors = await start(page);
    await readMathBook(page, 'opaque-and-transparent');
    await chooseTheme(page, theme);
    for (const row of ['transparent-row', 'transparent-svg-row']) {
      const picture = block(page, row).locator('img');
      await expect.poll(() => picture.evaluate(e => e.complete && e.naturalWidth > 0)).toBe(true);
      await turnTo(page, row);
      const box = await picture.boundingBox();
      const ink = await inkIn(page, { x: box.x - 6, y: box.y - 6, width: box.width + 12, height: box.height + 12 }, 6);
      expect(ink, `${row} is drawn`).not.toBeNull();
      // the ink and what is behind it: the ground of the picture, or of the page where it has none
      const ratio = contrast(ink.strongest, ink.background);
      expect(ratio, `${row}: ink ${ink.strongest} on ${ink.background}`).toBeGreaterThanOrEqual(4.5);
    }
    const { bg } = await colours(page);
    expect(bg.length).toBe(3);
    expect(errors).toEqual([]);
  });
}
