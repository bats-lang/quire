// Typography and theme: each control changes the page as it moves, and
// every setting is kept without being saved by hand.

import { test, expect } from '@playwright/test';
import { start, readBook, toLibrary, openBook, chapters, bookPage, dialog, openSettings, colours } from './helpers.js';

const para = page => bookPage(page).locator('p').first();
const style = (page, prop) => para(page).evaluate((e, p) => getComputedStyle(e)[p], prop);
const sheet = page => dialog(page, 'Typography and theme');
const slider = (page, name) => sheet(page).getByRole('slider', { name });
const choose = (page, name) => sheet(page).getByRole('button', { name, exact: true }).click();

test('size, line spacing and margins change the page, and are kept', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, { title: 'Typeset', author: 'Settings Tests', rawChapters: chapters(2) });
  await openSettings(page);
  await slider(page, 'Size').fill('28');
  await expect.poll(() => style(page, 'fontSize')).toBe('28px');
  await slider(page, 'Line spacing').fill('20');
  await expect.poll(() => style(page, 'lineHeight')).toBe(`${28 * 2}px`);
  const narrow = await style(page, 'paddingLeft');
  await slider(page, 'Margins').fill('4');
  await expect.poll(() => style(page, 'paddingLeft')).not.toBe(narrow);
  const wide = await style(page, 'paddingLeft');
  await choose(page, 'Close');
  await expect(sheet(page)).toBeHidden();
  await toLibrary(page);
  await page.reload();
  await openBook(page, 'Typeset');
  await expect.poll(() => style(page, 'fontSize')).toBe('28px');
  expect(await style(page, 'lineHeight')).toBe(`${28 * 2}px`);
  expect(await style(page, 'paddingLeft')).toBe(wide);
  await openSettings(page);
  await expect(slider(page, 'Size')).toHaveValue('28');
  expect(errors).toEqual([]);
});

test('the fonts can be chosen', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Faces', author: 'Settings Tests', rawChapters: chapters(1, 5) });
  await openSettings(page);
  await choose(page, 'Inter');
  await expect.poll(() => style(page, 'fontFamily')).toMatch(/^Inter/);
  await choose(page, 'Literata');
  await expect.poll(() => style(page, 'fontFamily')).toMatch(/^Literata/);
  // the page's text is set in the bundled font, upright
  await expect.poll(() => page.evaluate(() => document.fonts.check('18px Literata'))).toBe(true);
  expect(await style(page, 'fontStyle')).toBe('normal');
});

test('the themes change the colours, the choice is kept, and auto follows the system', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Colours', author: 'Settings Tests', rawChapters: chapters(1, 5) });
  const bg = async () => (await colours(page)).bg.join(',');
  const lum = ([r, g, b]) => 0.2126 * r + 0.7152 * g + 0.0722 * b;
  await openSettings(page);
  await choose(page, 'Light');
  const light = await bg();
  expect(lum(light.split(',').map(Number))).toBeGreaterThan(200);
  await choose(page, 'Dark');
  await expect.poll(bg).not.toBe(light);
  const dark = await colours(page);
  expect(lum(dark.bg)).toBeLessThan(60);
  expect(lum(dark.fg)).toBeGreaterThan(160);
  await choose(page, 'Sepia');
  await expect.poll(bg).not.toBe(dark.bg.join(','));
  const sepia = await bg();
  expect(sepia).not.toBe(light);
  const [r, , b] = sepia.split(',').map(Number);
  expect(r - b).toBeGreaterThan(20);
  // kept in the library and after a reload
  await page.keyboard.press('Escape');
  await page.reload();
  expect(await bg()).toBe(sepia);
  // auto: light, then dark when the system asks for it
  await openBook(page, 'Colours');
  await openSettings(page);
  await choose(page, 'Auto');
  await page.emulateMedia({ colorScheme: 'light' });
  await expect.poll(bg).toBe(light);
  await page.emulateMedia({ colorScheme: 'dark' });
  await expect.poll(bg).toBe(dark.bg.join(','));
});

test('reset puts the defaults back', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Defaults', author: 'Settings Tests', rawChapters: chapters(1, 5) });
  const before = await style(page, 'fontSize');
  await openSettings(page);
  await slider(page, 'Size').fill('30');
  await expect.poll(() => style(page, 'fontSize')).toBe('30px');
  await choose(page, 'Reset to defaults');
  // resetting asks first; cancelling keeps the settings
  await dialog(page, 'Reset to defaults?').getByRole('button', { name: 'Cancel' }).click();
  await expect.poll(() => style(page, 'fontSize')).toBe('30px');
  // the sheet is still open
  await choose(page, 'Reset to defaults');
  await dialog(page, 'Reset to defaults?').getByRole('button', { name: 'Reset' }).click();
  await expect.poll(() => style(page, 'fontSize')).toBe(before);
  await expect(slider(page, 'Size')).toHaveValue(String(parseInt(before, 10)));
});
