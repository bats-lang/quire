// Typography and theme: each control changes the page as it moves, and
// every setting is kept without being saved by hand.

import { test, expect } from '@playwright/test';
import { start, readBook, showChrome, toLibrary, openBook, chapters } from './helpers.js';

const para = page => page.locator('#qcnt p').first();
const style = (page, prop) => para(page).evaluate((e, p) => getComputedStyle(e)[p], prop);

async function openSettings(page) {
  await showChrome(page);
  await page.locator('#qset').click();
  await expect(page.locator('#qspn')).toBeVisible();
}

test('size, line spacing and margins change the page, and are kept', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, { title: 'Typeset', author: 'Settings Tests', rawChapters: chapters(2) });
  await openSettings(page);
  await page.locator('#qfsr').fill('28');
  await expect.poll(() => style(page, 'fontSize')).toBe('28px');
  await page.locator('#qlhr').fill('20');
  await expect.poll(() => style(page, 'lineHeight')).toBe(`${28 * 2}px`);
  const narrow = await style(page, 'paddingLeft');
  await page.locator('#qmgr').fill('4');
  await expect.poll(() => style(page, 'paddingLeft')).not.toBe(narrow);
  const wide = await style(page, 'paddingLeft');
  await page.locator('#qscl').click();
  await expect(page.locator('#qspn')).toBeHidden();
  await toLibrary(page);
  await page.reload();
  await openBook(page, 'Typeset');
  await expect.poll(() => style(page, 'fontSize')).toBe('28px');
  expect(await style(page, 'lineHeight')).toBe(`${28 * 2}px`);
  expect(await style(page, 'paddingLeft')).toBe(wide);
  await openSettings(page);
  await expect(page.locator('#qfsr')).toHaveValue('28');
  expect(errors).toEqual([]);
});

test('the fonts can be chosen', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Faces', author: 'Settings Tests', rawChapters: chapters(1, 5) });
  await openSettings(page);
  await page.locator('#qff1').click();
  await expect.poll(() => style(page, 'fontFamily')).toMatch(/^Inter/);
  await page.locator('#qff0').click();
  await expect.poll(() => style(page, 'fontFamily')).toMatch(/^Literata/);
  // the page's text is set in the bundled font, upright
  await expect.poll(() => page.evaluate(() => document.fonts.check('18px Literata'))).toBe(true);
  expect(await style(page, 'fontStyle')).toBe('normal');
});

test('the themes change the colours, the choice is kept, and auto follows the system', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Colours', author: 'Settings Tests', rawChapters: chapters(1, 5) });
  const root = page.locator('#bats-root');
  await openSettings(page);
  await page.locator('#qth3').click();
  await expect(root).toHaveClass(/th-dark/);
  await page.locator('#qth2').click();
  await expect(root).toHaveClass(/th-sepia/);
  await page.reload();
  await expect(root).toHaveClass(/th-sepia/);
  // auto: light, then dark when the system asks for it
  await openBook(page, 'Colours');
  await openSettings(page);
  await page.locator('#qth0').click();
  await page.emulateMedia({ colorScheme: 'light' });
  await expect(root).toHaveClass(/th-light/);
  await page.emulateMedia({ colorScheme: 'dark' });
  await expect(root).toHaveClass(/th-dark/);
});

test('reset puts the defaults back', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Defaults', author: 'Settings Tests', rawChapters: chapters(1, 5) });
  const before = await style(page, 'fontSize');
  await openSettings(page);
  await page.locator('#qfsr').fill('30');
  await expect.poll(() => style(page, 'fontSize')).toBe('30px');
  await page.locator('#qsrs').click();
  await expect.poll(() => style(page, 'fontSize')).toBe(before);
  await expect(page.locator('#qfsr')).toHaveValue(String(parseInt(before, 10)));
});
