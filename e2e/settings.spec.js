// Typography and theme: each control changes the page as it moves, and
// every setting is kept without being saved by hand.

import { test, expect } from '@playwright/test';
import { start, readBook, toLibrary, openBook, chapters, bookPage, dialog, openSettings, colours, reload,
} from './helpers.js';
import { TINY_PNG } from './create-epub.js';

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
  await reload(page);
  await openBook(page, 'Typeset');
  await expect.poll(() => style(page, 'fontSize')).toBe('28px');
  expect(await style(page, 'lineHeight')).toBe(`${28 * 2}px`);
  expect(await style(page, 'paddingLeft')).toBe(wide);
  await openSettings(page);
  await expect(slider(page, 'Size')).toHaveValue('28');
  expect(errors).toEqual([]);
});

test('alignment, hyphenation and the spacings change the page, and are kept', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, { title: 'Spaced', author: 'Settings Tests', rawChapters: chapters(2) });
  const group = name => sheet(page).getByRole('group', { name });
  // ragged and hyphenated to start with (WCAG 1.4.8: not justified)
  expect(await style(page, 'textAlign')).toBe('start');
  expect(await style(page, 'hyphens')).toBe('auto');
  expect(await style(page, 'letterSpacing')).toBe('normal');
  await openSettings(page);
  await expect(group('Alignment').getByRole('button', { name: 'Ragged' })).toHaveAttribute('aria-pressed', 'true');
  await group('Alignment').getByRole('button', { name: 'Justified' }).click();
  await expect.poll(() => style(page, 'textAlign')).toBe('justify');
  await expect(group('Alignment').getByRole('button', { name: 'Justified' })).toHaveAttribute('aria-pressed', 'true');
  await group('Hyphenation').getByRole('button', { name: 'Off' }).click();
  await expect.poll(() => style(page, 'hyphens')).toBe('manual');
  // the spacings reach what WCAG 1.4.12 asks a page to take
  await slider(page, 'Paragraph spacing').fill('20');
  await expect.poll(() => style(page, 'marginBottom')).toBe(`${18 * 2}px`);
  await slider(page, 'Letter spacing').fill('12');
  await expect.poll(async () => parseFloat(await style(page, 'letterSpacing'))).toBeCloseTo(18 * 0.12, 1);
  await slider(page, 'Word spacing').fill('16');
  await expect.poll(async () => parseFloat(await style(page, 'wordSpacing'))).toBeCloseTo(18 * 0.16, 1);
  await expect(sheet(page)).toContainText('0.12');
  await choose(page, 'Close');
  await toLibrary(page);
  await reload(page);
  await openBook(page, 'Spaced');
  await expect.poll(() => style(page, 'textAlign')).toBe('justify');
  expect(await style(page, 'hyphens')).toBe('manual');
  expect(await style(page, 'marginBottom')).toBe(`${18 * 2}px`);
  expect(parseFloat(await style(page, 'letterSpacing'))).toBeCloseTo(18 * 0.12, 1);
  expect(parseFloat(await style(page, 'wordSpacing'))).toBeCloseTo(18 * 0.16, 1);
  // the sheet, taller now, scrolls on a short screen to its last row
  await openSettings(page);
  await sheet(page).getByRole('button', { name: 'Close', exact: true }).scrollIntoViewIfNeeded();
  await expect(sheet(page).getByRole('button', { name: 'Close', exact: true })).toBeInViewport();
  expect(errors).toEqual([]);
});

test('a book\'s images are dimmed in the dark theme, unless that is turned off', async ({ page }) => {
  await start(page);
  await readBook(page, {
    title: 'Dim', author: 'Settings Tests',
    rawChapters: [{ body: '<p><img src="images/a.png" alt="picture"/></p><p>Words.</p>' }],
    extraEntries: [{ name: 'OEBPS/images/a.png', data: TINY_PNG, store: true }],
  });
  const filter = () => bookPage(page).getByRole('img', { name: 'picture' }).evaluate(e => getComputedStyle(e).filter);
  await openSettings(page);
  await choose(page, 'Light');
  await expect.poll(filter).toBe('none');
  await choose(page, 'Dark');
  await expect.poll(filter).toBe('brightness(0.8)');
  // and in the other dark-ground themes
  await choose(page, 'Night');
  await expect.poll(filter).toBe('brightness(0.8)');
  await choose(page, 'Grey');
  await expect.poll(filter).toBe('brightness(0.8)');
  await choose(page, 'Sepia');
  await expect.poll(filter).toBe('none');
  await choose(page, 'Dark');
  const dim = sheet(page).getByRole('group', { name: 'Dim images in the dark themes' });
  await expect(dim.getByRole('button', { name: 'On' })).toHaveAttribute('aria-pressed', 'true');
  await dim.getByRole('button', { name: 'Off' }).click();
  await expect.poll(filter).toBe('none');
  await choose(page, 'Close');
  // a reload comes back to the book, and the setting was kept
  await reload(page);
  await expect(bookPage(page)).toBeVisible();
  await expect.poll(filter).toBe('none');
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

test('Atkinson Hyperlegible can be chosen, and is fetched only then', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Legible', author: 'Settings Tests', rawChapters: chapters(1, 5) });
  const status = () => page.evaluate(() =>
    [...document.fonts].filter(f => f.family.replace(/["']/g, '') === 'Atkinson Hyperlegible').map(f => f.status));
  // declared, not loaded
  expect(await status()).toContain('unloaded');
  expect(await status()).not.toContain('loaded');
  await openSettings(page);
  await choose(page, 'Atkinson');
  await expect(sheet(page).getByRole('button', { name: 'Atkinson', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await expect.poll(() => style(page, 'fontFamily')).toMatch(/^["']?Atkinson Hyperlegible/);
  await expect.poll(status).toContain('loaded');
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
  // kept after a reload, which comes back to the book
  await page.keyboard.press('Escape');
  await reload(page);
  await expect(bookPage(page)).toBeVisible();
  expect(await bg()).toBe(sepia);
  // auto: light, then dark when the system asks for it
  await openSettings(page);
  await choose(page, 'Auto');
  await page.emulateMedia({ colorScheme: 'light' });
  await expect.poll(bg).toBe(light);
  await page.emulateMedia({ colorScheme: 'dark' });
  await expect.poll(bg).toBe(dark.bg.join(','));
});

test('the night theme is warm and dim, the grey one between dark and light, and both are kept', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Evening', author: 'Settings Tests', rawChapters: chapters(1, 5) });
  const lum = ([r, g, b]) => 0.2126 * r + 0.7152 * g + 0.0722 * b;
  await openSettings(page);
  await choose(page, 'Dark');
  const dark = await colours(page);
  await choose(page, 'Night');
  await expect.poll(async () => (await colours(page)).bg.join(',')).not.toBe(dark.bg.join(','));
  const night = await colours(page);
  // a dark ground, not black, and text low in blue and dimmer than the
  // dark theme's
  expect(lum(night.bg)).toBeLessThan(60);
  expect(Math.max(...night.bg)).toBeGreaterThan(17);
  expect(night.fg[0] - night.fg[2]).toBeGreaterThan(30);
  expect(lum(night.fg)).toBeLessThan(lum(dark.fg));
  await choose(page, 'Grey');
  await expect.poll(async () => (await colours(page)).bg.join(',')).not.toBe(night.bg.join(','));
  const grey = await colours(page);
  const [r, g, b] = grey.bg;
  expect(r).toBe(g);
  expect(g).toBe(b);
  expect(lum(grey.bg)).toBeGreaterThan(lum(dark.bg));
  expect(lum(grey.bg)).toBeLessThan(100);
  await expect(sheet(page).getByRole('button', { name: 'Grey', exact: true })).toHaveAttribute('aria-pressed', 'true');
  // kept after a reload, which comes back to the book
  await page.keyboard.press('Escape');
  await reload(page);
  await expect(bookPage(page)).toBeVisible();
  await expect.poll(async () => (await colours(page)).bg.join(',')).toBe(grey.bg.join(','));
});

test('reset puts the defaults back', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Defaults', author: 'Settings Tests', rawChapters: chapters(1, 5) });
  const before = await style(page, 'fontSize');
  await openSettings(page);
  await slider(page, 'Size').fill('30');
  await expect.poll(() => style(page, 'fontSize')).toBe('30px');
  // resetting asks nothing, and can be undone
  await choose(page, 'Reset to defaults');
  await expect.poll(() => style(page, 'fontSize')).toBe(before);
  await page.getByRole('button', { name: 'Undo' }).click();
  await expect.poll(() => style(page, 'fontSize')).toBe('30px');
  await choose(page, 'Justified');
  await expect.poll(() => style(page, 'textAlign')).toBe('justify');
  await choose(page, 'Reset to defaults');
  await expect.poll(() => style(page, 'fontSize')).toBe(before);
  expect(await style(page, 'textAlign')).toBe('start');
  await expect(slider(page, 'Size')).toHaveValue(String(parseInt(before, 10)));
});
