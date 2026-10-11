// The system's bars over every screen (#341): Android draws the app
// edge to edge, its status bar, its navigation bar (three buttons: 48
// px) and, in landscape or beside a cutout, a bar or a cutout at a side
// over the page, and gives the page their sizes as the safe area's
// insets. Every screen, sheet, menu, dialog and toast is opened with an
// inset on each side (DevTools set them), and no control or text of it
// may come within the spacing scale's least inset of one: the
// catalogue's Next was under the navigation bar's buttons.

import { test, expect, onAndroid } from './fixtures.js';
import { inSafeArea, coveredByBanner } from './controls-shown.js';
import { failLibrary, healReads, stubReads } from './storage-stub.js';
import { start, epubFile, importFiles } from './helpers.js';
import { walkEveryScreen } from './walk.js';

const INSETS = { top: 45, left: 32, right: 40, bottom: 48 };

test('every screen keeps its controls and text clear of the system bars on every side', async ({ page }, testInfo) => {
  test.skip(!onAndroid(testInfo), 'the system bars are drawn over the page in the Android app');
  test.setTimeout(180000);
  const devtools = await page.context().newCDPSession(page);
  await devtools.send('Emulation.setSafeAreaInsetsOverride', { insets: INSETS });
  await walkEveryScreen(page, {
    look: async screen => expect.soft(await inSafeArea(page, INSETS), `under or next to a system bar on ${screen}`).toEqual([]),
    back: () => page.keyboard.press('Escape'),
  });
});

// #508: the error banner is part of the page above the library's header,
// or fixed at the top of the reader; either way its text keeps clear of
// the status bar (the inset and the spacing scale's least inset), however
// long its message, and the library's header is still on the screen
test('the error banner keeps clear of the status bar over the library', async ({ page }, testInfo) => {
  test.skip(!onAndroid(testInfo), 'the system bars are drawn over the page in the Android app');
  const devtools = await page.context().newCDPSession(page);
  await devtools.send('Emulation.setSafeAreaInsetsOverride', { insets: INSETS });
  await stubReads(page);
  await start(page);
  await importFiles(page, [epubFile({ title: 'Kept Safe', author: 'Safe Area Tests' })], 1);
  await failLibrary(page, 'WeirdBrowserError');
  await page.reload();
  const banner = page.getByRole('alert');
  await expect(banner).toBeVisible();
  const least = await page.evaluate(() => parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--space-inset')));
  const box = await banner.boundingBox();
  expect(box.y, 'the banner starts below the status bar and the least inset').toBeGreaterThanOrEqual(INSETS.top + least - 0.5);
  expect(await inSafeArea(page, INSETS), 'under or next to a system bar with the banner up over the library').toEqual([]);
  expect(await coveredByBanner(page)).toEqual([]);
  await healReads(page);
});
