// The android job's probes (scripts/android/smoke-*.js) played in Chromium (keyword: android lock)

import { readFileSync } from 'node:fs';
import { test, expect } from './fixtures.js';
import { start, readBook, bookPage, rawMouse } from './helpers.js';
import { selectionBooks } from './selection-books.js';
import { scaledBy } from './font-scale.js';

const probe = name => readFileSync(new URL(`../scripts/android/${name}`, import.meta.url), 'utf8');
const toolbar = page => page.getByRole('toolbar', { name: 'Selection' });

/** The book open, a word selected where smoke-select-point.js says (the point in device pixels,
    read back as the page's coordinates), and the toolbar up */
async function selectedWord(page) {
  await start(page);
  await readBook(page, selectionBooks.prose.opts);
  await expect.poll(() => page.evaluate(probe('smoke-ready.js'))).toBe('true');
  const [x, y] = (await page.evaluate(probe('smoke-select-point.js'))).split(' ').map(Number);
  const word = await page.evaluate(({ px, py }) => {
    const at = document.caretRangeFromPoint(px / devicePixelRatio, py / devicePixelRatio);
    if (!at || at.startContainer.nodeType !== Node.TEXT_NODE) return null;
    const data = at.startContainer.data;
    let start = at.startOffset, end = at.startOffset;
    while (start > 0 && /\S/.test(data[start - 1])) start -= 1;
    while (end < data.length && /\S/.test(data[end])) end += 1;
    const range = document.createRange();
    range.setStart(at.startContainer, start);
    range.setEnd(at.startContainer, end);
    getSelection().removeAllRanges();
    getSelection().addRange(range);
    return data.slice(start, end);
  }, { px: x, py: y });
  expect(word, 'smoke-select-point.js answered a point on a word').toMatch(/^\S{4,}$/);
  await expect(toolbar(page)).toBeVisible();
}

/** The lines <name> <x> <y> of smoke-tap-points.js */
async function tapPoints(page) {
  const answer = await page.evaluate(probe('smoke-tap-points.js'));
  return answer.split('\n').map(l => l.split(' ')).map(([name, x, y]) => ({ name, x: Number(x), y: Number(y) }));
}

test('the probes long press a word and tap every toolbar button, and the result is true', async ({ page }) => {
  await selectedWord(page);
  const dpr = await page.evaluate(() => devicePixelRatio);
  const points = await tapPoints(page);
  const names = points.map(p => p.name);
  expect(names).toEqual(expect.arrayContaining(['selection-highlight', 'selection-note', 'selection-copy', 'selection-more']));
  for (const p of points) {
    expect(Number.isFinite(p.x) && Number.isFinite(p.y), `${p.name} has a point`).toBe(true);
    await rawMouse(page, 'click', p.x / dpr, p.y / dpr);
  }
  await expect(toolbar(page)).toBeVisible();
  const result = await page.evaluate(probe('smoke-tap-result.js'));
  // the row behind More is tapped when it was measured, and said when it was not
  if (names.includes('selection-yellow')) expect(result).toBe('true');
  else expect(result).toBe('the-row-behind-More');
  await expect(bookPage(page)).toBeVisible();
});

test('the result names a button that saw no click, and none that did', async ({ page }) => {
  await selectedWord(page);
  const dpr = await page.evaluate(() => devicePixelRatio);
  const points = (await tapPoints(page)).filter(p => p.name !== 'selection-note');
  for (const p of points) await rawMouse(page, 'click', p.x / dpr, p.y / dpr);
  const missed = (await page.evaluate(probe('smoke-tap-result.js'))).split(' ');
  expect(missed).toContain('selection-note');
  expect(missed).not.toContain('selection-copy');
  expect(missed).not.toContain('selection-highlight');
});

test('a tap that lands off the button is the one the result names', async ({ page }) => {
  await selectedWord(page);
  const dpr = await page.evaluate(() => devicePixelRatio);
  const points = await tapPoints(page);
  const copy = points.find(p => p.name === 'selection-copy');
  for (const p of points.filter(q => q !== copy)) await rawMouse(page, 'click', p.x / dpr, p.y / dpr);
  // Copy's tap goes to the page's top-left corner instead of its centre
  await rawMouse(page, 'click', 1, 1);
  const missed = (await page.evaluate(probe('smoke-tap-result.js'))).split(' ');
  expect(missed).toContain('selection-copy');
});

test('the taps still land when each tap ends the selection, as the real WebView does', async ({ page }) => {
  await selectedWord(page);
  const dpr = await page.evaluate(() => devicePixelRatio);
  const points = await tapPoints(page);
  for (const p of points) {
    await rawMouse(page, 'click', p.x / dpr, p.y / dpr);
    // Chromium's tap gesture collapses the selection (android job, quire#1083)
    await page.evaluate(() => getSelection().removeAllRanges());
    await expect(toolbar(page)).toBeVisible();
    await expect.poll(() => page.evaluate(() => getSelection().toString())).not.toBe('');
  }
  const result = await page.evaluate(probe('smoke-tap-result.js'));
  expect(['true', 'the-row-behind-More']).toContain(result);
});

test('a library with no book open gives the long press no point', async ({ page }) => {
  await start(page);
  expect(await page.evaluate(probe('smoke-select-point.js'))).toMatch(/^(no page|no word)$/);
});

test.describe('at the font scale 2.0', () => {
  test.use({ isMobile: true });

  test('a word is found though the text is a narrow column, and the point is on it', async ({ page }) => {
    await page.addInitScript(scaledBy(200));
    await selectedWord(page);
    await expect(toolbar(page)).toBeVisible();
  });
});
