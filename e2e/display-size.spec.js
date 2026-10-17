// Android's display size at its largest (#412). Settings clamps the
// smallest width Android lets a display have to 320 dp (AOSP's
// DensityPreference; the compatibility definition's normal screen is at
// least 480 x 320 dp), so a 1080 x 2400 Pixel at the largest size is
// 320 x 711 CSS px at 3.375 device pixels a CSS px (1080 / 320), where
// its default is 412 x 915 at 2.625. A smaller window and a larger ratio:
// every screen fits (the narrow project is 320 wide at a ratio of 1, and
// does not see a device pixel that is more than a quarter of a CSS pixel),
// and a chapter's pages are each a screen of their own.
//
// Not covered here: the system font scale (130%, 200%). The WebView
// applies it to every px size, which desktop Chromium cannot play (see
// the comment on #412).

import { test, expect } from './fixtures.js';
import {
  start, readBook, place, placeChanged, bookPage, chapters, showChrome,
} from './helpers.js';
import { walkEveryScreen, appPlayed } from './walk.js';
import { fits } from './fits.js';

test.use({ viewport: { width: 320, height: 711 }, deviceScaleFactor: 3.375, isMobile: true, hasTouch: true });

test('at the largest display size every screen fits', async ({ page }) => {
  await page.addInitScript(appPlayed);
  // (the window is the one asked for, so the walk is not of another size)
  await page.goto('/');
  expect(await page.evaluate(() => [innerWidth, innerHeight, devicePixelRatio])).toEqual([320, 711, 3.375]);
  await walkEveryScreen(page, {
    look: screen => fits(page, screen),
    back: () => page.keyboard.press('Escape'),
  });
});

test('at the largest display size every page of a chapter is a screen of its own, the last too', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await start(page);
  await readBook(page, { title: 'Largest Display', author: 'Pixel', rawChapters: chapters(1, 100) });
  await expect.poll(async () => (await place(page)).t).toBeGreaterThan(19);
  const geometry = () => bookPage(page).evaluate(doc => {
    const box = doc.getBoundingClientRect();
    return { at: Math.abs(doc.scrollLeft), size: box.width, screens: Math.round(doc.scrollWidth / box.width) };
  });
  expect(Number.isInteger((await geometry()).size)).toBe(true);
  for (;;) {
    const here = await place(page);
    const shown = await geometry();
    expect(shown.at, `page ${here.p}`).toBeCloseTo((here.p - 1) * shown.size, 0);
    expect(here.t).toBe(shown.screens);
    if (here.p === here.t) break;
    await page.keyboard.press('ArrowRight');
    await placeChanged(page, here);
  }
  await showChrome(page);
  await fits(page, 'the last page, with the bars');
});
