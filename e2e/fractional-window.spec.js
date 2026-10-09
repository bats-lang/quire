// A window whose width is not a whole number of CSS pixels: a
// Pixel 9's screen is 1080 device pixels at 2.625 a CSS pixel, 411.43
// CSS pixels wide. The bridge reports the page's width rounded (411), so
// when the chapter's pages were counted and scrolled to by that width,
// each page was 0.43 px out: a chapter of 19 pages or more was counted
// one page too many, and that last page, past the end of what can be
// scrolled, showed what the page before it did (the last page of every
// chapter, doubled), while the pages before it each began a little
// before their first column (the previous page's last letters at the
// edge).
//
// Playwright's viewport takes whole CSS pixels, so the reader view is
// given the Pixel 9's width as the window has it.

import { test, expect } from './fixtures.js';
import { start, readBook, place, placeChanged, bookPage, chapters } from './helpers.js';

const PIXEL_9_WIDTH = 1080 / 2.625;

test.use({ viewport: { width: 412, height: 923 } });

// Where the page is scrolled to, and how wide it really is (the layout's,
// not the rounded width the app is told), and how many screens it holds
const geometry = page => bookPage(page).evaluate(doc => ({
  left: doc.scrollLeft,
  width: doc.getBoundingClientRect().width,
  screens: Math.round(doc.scrollWidth / doc.getBoundingClientRect().width),
}));

test('every page of a chapter is a screen of its own in a window of a fractional width, the last too', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await start(page);
  await page.addStyleTag({ content: `.rv{right:auto!important;width:${PIXEL_9_WIDTH}px!important}` });
  await readBook(page, { title: 'Fractional Window', author: 'Pixel Nine', rawChapters: chapters(2, 100) });
  // the window is a fraction wide, the page a whole number of pixels
  const view = await bookPage(page).evaluate(doc => doc.parentElement.getBoundingClientRect().width);
  expect(view).toBeCloseTo(PIXEL_9_WIDTH, 1);
  expect(Number.isInteger((await geometry(page)).width)).toBe(true);

  for (const chapter of [1, 2]) {
    const seen = [];
    for (;;) {
      const here = await place(page);
      expect(here.ch).toBe(chapter);
      seen.push({ ...(await geometry(page)), indicated: here });
      if (here.p === here.t) break;
      await page.keyboard.press('ArrowRight');
      await placeChanged(page, here);
    }
    const last = seen[seen.length - 1];
    // enough pages for the width's error to have grown past the counting's slack
    expect(last.indicated.t).toBeGreaterThanOrEqual(19);
    // the chapter's pages are the screens the layout holds
    expect(last.indicated.t).toBe(last.screens);
    // each page is scrolled to the start of its own screen, so none begins
    // in the page before it, and the last is not the one before it again
    seen.forEach((shown, k) => expect(shown.left, `page ${k + 1} of chapter ${chapter}`).toBeCloseTo(k * shown.width, 0));
    for (let k = 1; k < seen.length; k++) {
      expect(seen[k].left - seen[k - 1].left, `page ${k + 1} of chapter ${chapter}`).toBeGreaterThan(seen[k].width - 1);
    }
    // on from the last page is the next chapter's first, or the book's end
    if (chapter === 1) {
      await page.keyboard.press('ArrowRight');
      await expect.poll(async () => (await place(page)).ch).toBe(2);
      expect((await place(page)).p).toBe(1);
    }
  }
});
