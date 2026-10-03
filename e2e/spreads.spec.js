// Spreads (EPUB 3.3 §8.2.2, EPUB RS 3.3 §8.1): a fixed-layout book is
// shown two pages at a time as its rendition:spread and the Columns
// setting say, its pages paired as Apple Books pairs them: the first
// page alone on the right (on the left read right to left), each later
// one on the side after the one before it unless its itemref asks for
// one, a centred page alone; the two meet in the middle with no gap.

import { test, expect } from './fixtures.js';
import {
  start, bookPage, dialog, openSettings, fixedLayoutBook, fixedPlace, readFixed, fixedBoxes,
} from './helpers.js';

const LANDSCAPE = { width: 1024, height: 768 };
const PORTRAIT = { width: 375, height: 667 };

/** The names of the images shown, left to right ('' for a blank side) */
async function sidesShown(page) {
  const { sides } = await fixedBoxes(page);
  return sides.map(side => side.image ? side.image.name : '');
}

/** Waits until the images shown, left to right, are names, all loaded */
async function expectSides(page, names) {
  await expect.poll(async () => {
    const { sides } = await fixedBoxes(page);
    const loaded = sides.every(side => !side.image || side.image.loaded);
    return loaded ? sides.map(side => side.image ? side.image.name : '') : 'loading';
  }).toEqual(names);
}

/** The spread fits the view whole and is centred, its two sides the
    same size, meeting with no gap */
async function expectSpread(page) {
  const { view, sides } = await fixedBoxes(page);
  expect(sides).toHaveLength(2);
  const [left, right] = sides;
  expect(Math.abs(left.x + left.w - right.x)).toBeLessThan(1.5);
  expect(Math.abs(left.w - right.w)).toBeLessThan(1);
  expect(Math.abs(left.h - right.h)).toBeLessThan(1);
  expect(left.w + right.w).toBeLessThanOrEqual(view.w + 1);
  expect(left.h).toBeLessThanOrEqual(view.h + 1);
  // as large as the view allows, centred: the middle is the view's
  expect(Math.min(view.w - 2 * left.w, view.h - left.h)).toBeLessThan(2);
  expect(Math.abs(right.x - (view.x + view.w / 2))).toBeLessThan(1.5);
}

test('in landscape, the first page is alone on the right, then the pages go in pairs with no gap between them', async ({ page }) => {
  await page.setViewportSize(LANDSCAPE);
  const errors = await start(page);
  await readFixed(page, fixedLayoutBook('Paired Pages', 5, { spread: 'auto' }));
  await expectSides(page, ['', 'Page 1']);
  expect(await fixedPlace(page)).toEqual({ p: 1, t: 5 });
  await expectSpread(page);
  await page.keyboard.press('ArrowRight');
  await expectSides(page, ['Page 2', 'Page 3']);
  expect(await fixedPlace(page)).toEqual({ p: 2, last: 3, t: 5 });
  await expectSpread(page);
  await page.keyboard.press('ArrowRight');
  await expectSides(page, ['Page 4', 'Page 5']);
  // and back, a spread at a time, to the first page alone
  await page.keyboard.press('ArrowLeft');
  await expectSides(page, ['Page 2', 'Page 3']);
  await page.keyboard.press('ArrowLeft');
  await expectSides(page, ['', 'Page 1']);
  // the facing page is shown, not selected: what is marked is the page's
  expect(await bookPage(page).evaluate(doc => [...doc.children].map(side => getComputedStyle(side).userSelect)))
    .toContain('none');
  expect(errors).toEqual([]);
});

test('read right to left, the first page is alone on the left, and the pairs go right to left', async ({ page }) => {
  await page.setViewportSize(LANDSCAPE);
  await start(page);
  await readFixed(page, fixedLayoutBook('Manga', 3, { rtl: true }));
  await expectSides(page, ['Page 1', '']);
  await page.keyboard.press('ArrowLeft');
  await expectSides(page, ['Page 3', 'Page 2']);
  await expectSpread(page);
});

test('an itemref\'s page-spread outranks the pairing, a side left blank; a centred page is alone', async ({ page }) => {
  await page.setViewportSize(LANDSCAPE);
  await start(page);
  // page 2 asks for the right, so it does not pair with page 1 (on the
  // right too) nor with page 3; page 3 is centred; page 4 then starts a
  // spread on the left, with page 5 on its right
  await readFixed(page, fixedLayoutBook('Sides Asked', 5, {
    itemrefs: [undefined, 'rendition:page-spread-right', 'rendition:page-spread-center', undefined, 'page-spread-right'],
  }));
  await expectSides(page, ['', 'Page 1']);
  await page.keyboard.press('ArrowRight');
  await expectSides(page, ['', 'Page 2']);
  await page.keyboard.press('ArrowRight');
  await expectSides(page, ['Page 3']);
  await page.keyboard.press('ArrowRight');
  await expectSides(page, ['Page 4', 'Page 5']);
});

test('a book whose spread is none is never shown in pairs', async ({ page }) => {
  await page.setViewportSize(LANDSCAPE);
  await start(page);
  await readFixed(page, fixedLayoutBook('No Spreads', 3, { spread: 'none' }));
  await expectSides(page, ['Page 1']);
  await page.keyboard.press('ArrowRight');
  await expectSides(page, ['Page 2']);
});

test('in portrait, a landscape book\'s pages are shown one at a time', async ({ page }) => {
  await page.setViewportSize(PORTRAIT);
  await start(page);
  await readFixed(page, fixedLayoutBook('Portrait Pages', 3, { spread: 'landscape' }));
  await expectSides(page, ['Page 1']);
  await page.keyboard.press('ArrowRight');
  await expectSides(page, ['Page 2']);
});

test('the Columns setting overrides: One shows single pages, Two pairs them in portrait too', async ({ page }) => {
  await page.setViewportSize(LANDSCAPE);
  await start(page);
  await readFixed(page, fixedLayoutBook('Columns Chosen', 3));
  await expectSides(page, ['', 'Page 1']);
  const columns = name => dialog(page, 'Typography and theme').getByRole('group', { name: 'Columns' })
    .getByRole('button', { name, exact: true });
  await openSettings(page);
  await columns('One').click();
  await page.keyboard.press('Escape');
  await expectSides(page, ['Page 1']);
  await page.setViewportSize(PORTRAIT);
  await openSettings(page);
  await columns('Two').click();
  await page.keyboard.press('Escape');
  await expectSides(page, ['', 'Page 1']);
  await page.keyboard.press('ArrowRight');
  await expectSides(page, ['Page 2', 'Page 3']);
  await expectSpread(page);
});

test('turned from landscape to portrait, a spread becomes its page alone, and back', async ({ page }) => {
  await page.setViewportSize(LANDSCAPE);
  await start(page);
  await readFixed(page, fixedLayoutBook('Turned Device', 3));
  await page.keyboard.press('ArrowRight');
  await expectSides(page, ['Page 2', 'Page 3']);
  await page.setViewportSize(PORTRAIT);
  await expectSides(page, ['Page 2']);
  await page.setViewportSize(LANDSCAPE);
  await expectSides(page, ['Page 2', 'Page 3']);
});
