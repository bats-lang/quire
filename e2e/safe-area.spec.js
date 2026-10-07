// The system's bars over every screen (#341): Android draws the app
// edge to edge, its status bar, its navigation bar (three buttons: 48
// px) and, in landscape or beside a cutout, a bar or a cutout at a side
// over the page, and gives the page their sizes as the safe area's
// insets. Every screen, sheet, menu, dialog and toast is opened with an
// inset on each side (DevTools set them), and no control or text of it
// may come within the spacing scale's least inset of one: the
// catalogue's Next was under the navigation bar's buttons.

import { test, expect, onAndroid } from './fixtures.js';
import { inSafeArea } from './controls-shown.js';
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
