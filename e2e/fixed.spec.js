// Fixed layout (EPUB 3.3 §8.2, rendition:layout pre-paginated): each
// spine item is one page of its own size (its viewport meta), scaled to
// fit the reader view whole, letter-boxed and centred, as Thorium's Fit
// does; a page without a viewport takes the last one's (EPUB RS 3.3
// §8.1.2). A fixed page is not restyled: only the theme and what the
// reader does (taps, keys, reading aloud, the screen) are offered.

import { test, expect } from './fixtures.js';
import {
  start, importFiles, epubFile, card, bookPage, indicator, dialog, openSettings, toLibrary, chapters,
  fixedLayoutBook, imagePage, fixedPlace, readFixed, fixedBoxes as boxes,
  readingSettings, openReadingSettings,
} from './helpers.js';
import { solidPng } from './create-epub.js';

/** A fixed-layout book shown a page at a time (its rendition:spread none) */
const fixedBook = (title, count = 3, bare = []) => fixedLayoutBook(title, count, { bare, spread: 'none' });

/** The page fits the view whole: the viewport's shape (0.75), as large
    as the view allows (one side within 2 px of the view's), centred */
function expectFitted({ page, view }, ratio = 0.75) {
  expect(Math.abs(page.w / page.h - ratio)).toBeLessThan(0.01);
  expect(page.w).toBeLessThanOrEqual(view.w + 1);
  expect(page.h).toBeLessThanOrEqual(view.h + 1);
  expect(Math.min(view.w - page.w, view.h - page.h)).toBeLessThan(2);
  expect(Math.abs((page.x - view.x) - (view.x + view.w - page.x - page.w))).toBeLessThan(2);
  expect(Math.abs((page.y - view.y) - (view.y + view.h - page.y - page.h))).toBeLessThan(2);
}

test('a fixed-layout page is its viewport\'s shape, fitted whole and centred, its image filling it', async ({ page }) => {
  const errors = await start(page);
  await readFixed(page, fixedBook('Picture Book'));
  expect(await fixedPlace(page)).toEqual({ p: 1, t: 3 });
  await expect.poll(async () => (await boxes(page)).loaded).toBe(true);
  const shown = await boxes(page);
  expectFitted(shown);
  // the image (1200 by 1600, as a page's image is drawn for a sharp
  // screen) is the page's shape, so it fills the page
  expect(Math.abs(shown.image.w - shown.page.w)).toBeLessThan(2);
  expect(Math.abs(shown.image.h - shown.page.h)).toBeLessThan(2);
  // laid out as 600 by 800 CSS pixels, scaled to fit
  expect((await boxes(page)).page.laidOut).toEqual({ w: 600, h: 800 });
  // the whole reader view is the page: no paddings, the bars over it
  expect(shown.view.h).toBe(page.viewportSize().height);
  // one page a spine item, never in columns or scrolled
  expect(await bookPage(page).evaluate(e => ({ columns: getComputedStyle(e).columnWidth, overflow: getComputedStyle(e).overflow })))
    .toEqual({ columns: 'auto', overflow: 'hidden' });
  expect(errors).toEqual([]);
});

test('a turn goes to the next spine item, each a page, and back', async ({ page }) => {
  await start(page);
  await readFixed(page, fixedBook('Turned Pages'));
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await fixedPlace(page)).p).toBe(2);
  await expect(bookPage(page).getByRole('img', { name: 'Page 2' })).toBeVisible();
  expectFitted(await boxes(page));
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await fixedPlace(page)).p).toBe(3);
  await expect(bookPage(page).getByRole('img', { name: 'Page 3' })).toBeVisible();
  await page.keyboard.press('ArrowLeft');
  await expect.poll(async () => (await fixedPlace(page)).p).toBe(2);
  await expect(bookPage(page).getByRole('img', { name: 'Page 2' })).toBeVisible();
  // a tap at the view's sides, beside the page where it is letter-boxed,
  // turns it as on a reflowed page
  const view = await bookPage(page).boundingBox();
  await page.mouse.click(view.x + view.width - 4, view.y + view.height / 2);
  await expect.poll(async () => (await fixedPlace(page)).p).toBe(3);
  await page.mouse.click(view.x + 4, view.y + view.height / 2);
  await expect.poll(async () => (await fixedPlace(page)).p).toBe(2);
});

test('a fixed page with no viewport takes the last page\'s size', async ({ page }) => {
  await start(page);
  await readFixed(page, fixedBook('Bare Pages', 3, [2]));
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await fixedPlace(page)).p).toBe(2);
  expect((await boxes(page)).page.laidOut).toEqual({ w: 600, h: 800 });
  expectFitted(await boxes(page));
});

test('a fixed page is fitted again when the window changes size', async ({ page }) => {
  await start(page);
  await readFixed(page, fixedBook('Resized Pages'));
  const size = page.viewportSize();
  await page.setViewportSize({ width: size.height, height: size.width });
  await expect.poll(async () => {
    const { page: box, view } = await boxes(page);
    return Math.abs(view.w - size.height) < 2 && box.w <= view.w + 1 && box.h <= view.h + 1
      && Math.min(view.w - box.w, view.h - box.h) < 2;
  }).toBe(true);
  expectFitted(await boxes(page));
});

test('a fixed-layout book is offered only the theme, its spreads and how the reader turns its pages', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile(fixedBook('Not Restyled')), epubFile({ title: 'Reflowed', author: 'Fixed Tests', rawChapters: chapters(1) })], 2);
  await card(page, 'Not Restyled').click();
  await expect(indicator(page)).toContainText('in book');
  await openSettings(page);
  const sheet = dialog(page, 'Reading settings');
  const more = readingSettings(page);
  await expect(sheet.getByRole('group', { name: 'Theme', exact: true })).toBeVisible();
  await expect(sheet.getByRole('button', { name: 'Literata', exact: true })).toBeHidden();
  await expect(sheet.getByRole('slider', { name: 'Size' })).toBeHidden();
  await openReadingSettings(page, 'Page');
  await expect(more.getByRole('group', { name: 'Layout' })).toBeHidden();
  await expect(more.getByRole('slider', { name: 'Margins' })).toBeHidden();
  // its pages on screen are its spreads (spreads.spec.js)
  await expect(more.getByRole('group', { name: 'Pages on screen' })).toBeVisible();
  await expect(more.getByRole('button', { name: 'Justify text', exact: true })).toBeHidden();
  await openReadingSettings(page, 'Turning');
  await expect(more.getByRole('group', { name: 'Tap to turn pages' })).toBeVisible();
  await page.keyboard.press('Escape');
  await toLibrary(page);
  // a reflowed book after it is offered them all, and is not a fixed page
  await card(page, 'Reflowed').click();
  await expect(indicator(page)).toContainText('in chapter');
  await openSettings(page);
  await expect(sheet.getByRole('button', { name: 'Literata', exact: true })).toBeVisible();
  await openReadingSettings(page, 'Page');
  await expect(more.getByRole('group', { name: 'Layout' })).toBeVisible();
  await expect(more.getByRole('slider', { name: 'Margins' })).toBeVisible();
  await page.keyboard.press('Escape');
  expect(await bookPage(page).evaluate(e => getComputedStyle(e).columnWidth)).not.toBe('auto');
  expect(await bookPage(page).evaluate(e => [...e.querySelectorAll('[style]')].length)).toBe(0);
});

test('an itemref\'s own layout outranks the book\'s: one fixed page in a reflowed book', async ({ page }) => {
  await start(page);
  const reflowed = chapters(3, 4);
  reflowed[1] = { ...imagePage(2), itemref: 'rendition:layout-pre-paginated' };
  await importFiles(page, [epubFile({
    title: 'Mixed Book', author: 'Fixed Tests', chapters: 3, rawChapters: reflowed,
    metadata: '<meta property="rendition:spread">none</meta>\n',
    extraImages: [{ name: 'images/page2.png', data: solidPng(1200, 1600) }],
  })], 1);
  await card(page, 'Mixed Book').click();
  await expect(indicator(page)).toContainText('in chapter');
  // the second spine item is a fixed page
  const turnToChapter = async n => {
    for (let i = 0; i < 40; i++) {
      const text = await indicator(page).textContent();
      if (new RegExp(`^Chapter ${n}\\b`).test(text.trim())) return;
      await page.keyboard.press('ArrowRight');
      await expect.poll(async () => (await indicator(page).textContent())).not.toBe(text);
    }
  };
  await turnToChapter(2);
  await expect(indicator(page)).toContainText('page 2 of 3 in book');
  expectFitted(await boxes(page));
  // and the third is reflowed again: columns, no inline style
  await page.keyboard.press('ArrowRight');
  await expect(indicator(page)).toContainText('in chapter');
  expect(await bookPage(page).evaluate(e => getComputedStyle(e).columnWidth)).not.toBe('auto');
  expect(await bookPage(page).evaluate(e => [...e.querySelectorAll('[style]')].length)).toBe(0);
});
