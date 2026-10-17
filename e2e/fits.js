// What every screen of the app must show at any window size or scale: nothing cut off,
// no toggle that looks the same on and off, no control under the banner and so on
// (layout.spec.js, display-size.spec.js)

import { expect } from './fixtures.js';
import { strayGrounds, cutOff, statesUnseen, insetsShort, peekAbove, sheetReach, offScale, rowIsTarget, looksActionable, toastClear, coveredByBanner, onOffPairs, textContrastShort, stateCueShort, labelsShown, labelInName, targetsShort } from './controls-shown.js';

/** Expects nothing cut off on the screen shown (controls-shown.js), no
    toggle whose state shows only in aria-pressed, no control nearer its
    container's edge than the spacing scale allows (#331), and nothing
    wider than the window, naming the screen when something is */
export async function fits(page, screen) {
  expect(await cutOff(page), `cut off on ${screen}`).toEqual([]);
  expect(await statesUnseen(page), `toggles on ${screen} that look the same on and off`).toEqual([]);
  expect(await coveredByBanner(page), `controls under the error banner on ${screen}`).toEqual([]);
  expect(await textContrastShort(page), `placeholders under 4.5:1 on ${screen}`).toEqual([]);
  expect(await stateCueShort(page), `a chosen tab told apart by a tint alone on ${screen}`).toEqual([]);
  expect(await onOffPairs(page), `two-state settings on ${screen} that are not switches`).toEqual([]);
  expect(await labelsShown(page), `fields without a visible label on ${screen}`).toEqual([]);
  expect(await labelInName(page), `buttons whose name is not their words on ${screen}`).toEqual([]);
  expect(await strayGrounds(page), `text on a ground other than the one behind it on ${screen}`).toEqual([]);
  expect(await targetsShort(page), `touch targets under 48 px on ${screen}`).toEqual([]);
  expect(await looksActionable(page), `chevron rows not drawn as controls on ${screen}`).toEqual([]);
  expect(await rowIsTarget(page), `rows that open a screen whose button is not the whole row on ${screen}`).toEqual([]);
  expect(await toastClear(page), `controls under a toast on ${screen}`).toEqual([]);
  expect(await peekAbove(page), `sheets covering more than 60% of the window on ${screen}`).toEqual([]);
  expect(await sheetReach(page), `controls of a sheet that cannot be scrolled into reach on ${screen}`).toEqual([]);
  expect(await offScale(page), `gaps and tab paddings off the spacing scale on ${screen}`).toEqual([]);
  expect(await insetsShort(page), `controls nearer their container's edge than the spacing scale's least inset on ${screen}`).toEqual([]);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${screen} is wider than the window`).toBe(true);
}

