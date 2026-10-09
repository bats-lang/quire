// A window whose size is not a whole number of CSS pixels: a Pixel 9's
// screen is 1080 by 2424 device pixels at 2.625 a CSS pixel, 411.43 by
// 923.43 CSS pixels. The bridge reports the page's size rounded (411 by
// 923), so when a chapter's pages were counted and scrolled to by that
// size each page was 0.43 px out more than the one before it: a chapter
// of 19 pages or more was counted one page too many, and that last page,
// past the end of what can be scrolled, showed what the page before it
// did (the last page of every chapter, doubled), while the pages before
// it each began a little before their first column (the previous page's
// last letters at the edge).
//
// Playwright's viewport takes whole CSS pixels, so the reader view is
// given the Pixel 9's size as the window has it. Every way the reader
// pages is walked a page at a time through two chapters: across, across
// right to left, a spread of two columns, down (a vertical book) and
// scrolled.

import { test, expect } from './fixtures.js';
import {
  start, readBook, place, placeChanged, bookPage, indicator, chapters, japaneseChapters,
  readingSettings, openReadingSettings,
} from './helpers.js';

const PIXEL_9_WIDTH = 1080 / 2.625;
const PIXEL_9_HEIGHT = 2424 / 2.625;

const phone = { width: 412, height: 923 };

// The reader view given a size a fraction of a pixel wide or high
async function fractional(page, { width = false, height = false } = {}) {
  const rules = [];
  if (width) rules.push('right:auto!important', `width:${PIXEL_9_WIDTH}px!important`);
  if (height) rules.push('bottom:auto!important', `height:${PIXEL_9_HEIGHT}px!important`);
  await page.addStyleTag({ content: `.rv{${rules.join(';')}}` });
}

// Where the page is scrolled to along its axis, how long a page is along
// it (the layout's, not the rounded size the app is told), and how many
// screens the layout holds
const geometry = (page, axis) => bookPage(page).evaluate((doc, axis) => {
  const box = doc.getBoundingClientRect();
  return axis === 'down'
    ? { at: doc.scrollTop, size: box.height, screens: Math.round(doc.scrollHeight / box.height) }
    : { at: Math.abs(doc.scrollLeft), size: box.width, screens: Math.round(doc.scrollWidth / box.width) };
}, axis);

// Turns through each chapter in turn, the page indicator and the layout
// read at every page; the pages seen of each
async function walk(page, advance, axis, chapterCount = 2) {
  const chapters = [];
  // the chapter is counted again as it is laid out
  await expect.poll(async () => (await place(page)).t).toBeGreaterThan(1);
  for (let chapter = 1; chapter <= chapterCount; chapter++) {
    const seen = [];
    for (;;) {
      const here = await place(page);
      expect(here.ch).toBe(chapter);
      seen.push({ ...(await geometry(page, axis)), indicated: here });
      if (here.p === here.t) break;
      await advance();
      await placeChanged(page, here);
    }
    chapters.push(seen);
    if (chapter < chapterCount) {
      // on from the last page is the next chapter's first
      await advance();
      await expect.poll(async () => (await place(page)).ch).toBe(chapter + 1);
      expect((await place(page)).p).toBe(1);
    }
  }
  return chapters;
}

// Each page is scrolled to the start of its own screen, so none begins
// in the page before it; the pages are the screens the layout holds, and
// the last is not the one before it again
function expectWhole(chapters) {
  chapters.forEach((seen, c) => {
    const last = seen[seen.length - 1];
    // enough pages for the size's error to have grown past the counting's slack
    expect(last.indicated.t, `chapter ${c + 1}`).toBeGreaterThanOrEqual(19);
    expect(last.indicated.t, `chapter ${c + 1}`).toBe(last.screens);
    seen.forEach((shown, k) => expect(shown.at, `page ${k + 1} of chapter ${c + 1}`).toBeCloseTo(k * shown.size, 0));
    for (let k = 1; k < seen.length; k++) {
      expect(seen[k].at - seen[k - 1].at, `page ${k + 1} of chapter ${c + 1}`).toBeGreaterThan(seen[k].size - 1);
    }
  });
}

test.describe('in a window a fraction of a pixel wide', () => {
  test.use({ viewport: phone });

  test('every page of a chapter is a screen of its own, the last too', async ({ page }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await start(page);
    await fractional(page, { width: true });
    await readBook(page, { title: 'Fractional Window', author: 'Pixel Nine', rawChapters: chapters(2, 100) });
    // the window is a fraction wide, the page a whole number of pixels
    const view = await bookPage(page).evaluate(doc => doc.parentElement.getBoundingClientRect().width);
    expect(view).toBeCloseTo(PIXEL_9_WIDTH, 1);
    expect(Number.isInteger((await geometry(page, 'across')).size)).toBe(true);
    expectWhole(await walk(page, () => page.keyboard.press('ArrowRight'), 'across'));
  });

  test('read right to left, the pages go on to the left and the last is not the one before it', async ({ page }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await start(page);
    await fractional(page, { width: true });
    await readBook(page, { title: 'Fractional Hebrew', author: 'Pixel Nine', rtl: true, rawChapters: chapters(2, 100) });
    expectWhole(await walk(page, () => page.keyboard.press('ArrowLeft'), 'across'));
  });
});

test.describe('in a window a fraction of a pixel high', () => {
  test.use({ viewport: phone });

  test('a vertical book\'s pages, a page height down each, are each a screen of their own, the last too', async ({ page }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await start(page);
    await fractional(page, { height: true });
    await readBook(page, {
      title: 'Fractional Vertical', author: 'Pixel Nine', language: 'ja', rtl: true, rawChapters: japaneseChapters(2, 70),
    });
    const view = await bookPage(page).evaluate(doc => doc.parentElement.getBoundingClientRect().height);
    expect(view).toBeCloseTo(PIXEL_9_HEIGHT, 1);
    expect(Number.isInteger((await geometry(page, 'down')).size)).toBe(true);
    expectWhole(await walk(page, () => page.keyboard.press('ArrowLeft'), 'down'));
  });

  test('scrolled, each turn goes down a screenful until the last, which is the chapter\'s end', async ({ page }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await start(page);
    await fractional(page, { height: true });
    await readBook(page, { title: 'Fractional Scroll', author: 'Pixel Nine', rawChapters: chapters(2, 100) });
    await openReadingSettings(page, 'Page');
    await readingSettings(page).getByRole('group', { name: 'Layout' }).getByRole('button', { name: 'Scroll' }).click();
    await page.keyboard.press('Escape');
    await expect.poll(() => bookPage(page).evaluate(e => getComputedStyle(e).overflowY)).toBe('auto');
    const tops = [];
    for (;;) {
      const top = await bookPage(page).evaluate(e => e.scrollTop);
      const end = await bookPage(page).evaluate(e => e.scrollHeight - e.clientHeight);
      tops.push({ top, end });
      if (top >= end - 2) break;
      await page.keyboard.press('ArrowRight');
      await expect.poll(() => bookPage(page).evaluate(e => e.scrollTop)).toBeGreaterThan(top);
    }
    // a turn is a screenful less a line, so the last is nearer the one before it
    // than a whole screenful, but never the one before it again
    const step = tops[1].top - tops[0].top;
    for (let k = 2; k < tops.length - 1; k++) expect(tops[k].top - tops[k - 1].top).toBeCloseTo(step, 0);
    expect(tops[tops.length - 1].top - tops[tops.length - 2].top).toBeGreaterThan(2);
    expect(tops[tops.length - 1].top - tops[tops.length - 2].top).toBeLessThanOrEqual(step + 1);
  });
});

test.describe('in a wide window a fraction of a pixel wide', () => {
  test.use({ viewport: { width: 1024, height: 768 } });

  test('a spread of two columns is a screen of whole pixels, each screen scrolled to exactly', async ({ page }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await start(page);
    await page.addStyleTag({ content: '.rv{right:auto!important;width:1000.43px!important}' });
    await readBook(page, { title: 'Fractional Spread', author: 'Pixel Nine', rawChapters: chapters(2, 300) });
    expect(await indicator(page).textContent(), 'a spread of two columns').toMatch(/pages \d+–\d+ of/);
    expect(Number.isInteger((await geometry(page, 'across')).size)).toBe(true);
    const chapters_seen = await walk(page, () => page.keyboard.press('ArrowRight'), 'across');
    chapters_seen.forEach((seen, c) => {
      const last = seen[seen.length - 1];
      expect(last.indicated.t, `chapter ${c + 1}`).toBeGreaterThanOrEqual(19);
      expect(last.indicated.t, `chapter ${c + 1}`).toBe(last.screens);
      // a spread's last screen can hold one column, half a screen, which is
      // as far as the page scrolls
      seen.slice(0, -1).forEach((shown, k) => expect(shown.at, `screen ${k + 1} of chapter ${c + 1}`).toBeCloseTo(k * shown.size, 0));
      expect(last.at - seen[seen.length - 2].at).toBeGreaterThan(last.size / 2 - 1);
    });
  });
});
