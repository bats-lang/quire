// Reading settings: each control changes the page as it moves, and
// every setting is kept without being saved by hand.

import { test, expect } from './fixtures.js';
import { start, readBook, toLibrary, openBook, chapters, bookPage, dialog, openSettings, colours, reload,
  readingSettings, openReadingSettings,
} from './helpers.js';
import { TINY_PNG } from './create-epub.js';

const para = page => bookPage(page).locator('p').first();
const style = (page, prop) => para(page).evaluate((e, p) => getComputedStyle(e)[p], prop);
const sheet = page => dialog(page, 'Reading settings');
const slider = (page, name) => sheet(page).getByRole('slider', { name });
const choose = (page, name) => sheet(page).getByRole('button', { name, exact: true }).click();
// the sheet as a whole, on whichever tab, and its sliders
const more = page => readingSettings(page);
const moreSlider = (page, name) => more(page).getByRole('slider', { name });

// The sheet's tabs (#288): every reading setting one tap away in the one
// sheet, with nothing opened over it; WAI-ARIA's tabs pattern (one tab
// selected and in the Tab order, the arrow keys, Home and End moving
// the focus and the panel with it)
test('the reading settings are tabs in the one sheet, by tap and by keyboard', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, { title: 'Tabbed Sheet', author: 'Settings Tests', rawChapters: chapters(1) });
  await openSettings(page);
  const tabs = sheet(page).getByRole('tablist', { name: 'Reading settings' });
  const tab = name => tabs.getByRole('tab', { name, exact: true });
  const panel = name => sheet(page).getByRole('tabpanel', { name, exact: true });
  const names = ['Look', 'Page', 'Turning', 'Read aloud'];
  await expect(tabs.getByRole('tab')).toHaveText(names);
  // no control says only "More"
  await expect(sheet(page).getByRole('button', { name: /^More\b/ })).toHaveCount(0);
  const shown = async chosen => {
    for (const name of names) {
      await expect(tab(name)).toHaveAttribute('aria-selected', String(name === chosen));
      await expect(tab(name)).toHaveAttribute('tabindex', name === chosen ? '0' : '-1');
      if (name === chosen) await expect(panel(name)).toBeVisible();
      else await expect(panel(name)).toBeHidden();
    }
    // one modal layer: the sheet, and nothing over it
    await expect(page.locator('[aria-modal="true"]:visible')).toHaveCount(1);
  };
  // the sheet opens on Look
  await shown('Look');
  await expect(panel('Look').getByRole('group', { name: 'Theme', exact: true })).toBeVisible();
  // by tap
  await tab('Turning').click();
  await shown('Turning');
  await expect(panel('Turning').getByRole('group', { name: 'Tap to turn pages' })).toBeVisible();
  await tab('Page').click();
  await shown('Page');
  await expect(panel('Page').getByRole('group', { name: 'Justify text' })).toBeVisible();
  // by keyboard: the arrows move along, round at the ends, and Home and End
  await expect(tab('Page')).toBeFocused();
  await page.keyboard.press('ArrowRight');
  await expect(tab('Turning')).toBeFocused();
  await shown('Turning');
  await page.keyboard.press('ArrowRight');
  await expect(tab('Read aloud')).toBeFocused();
  await shown('Read aloud');
  await expect(panel('Read aloud').getByRole('combobox', { name: 'Reading speed' })).toBeVisible();
  await page.keyboard.press('ArrowRight');
  await expect(tab('Look')).toBeFocused();
  await shown('Look');
  await page.keyboard.press('ArrowLeft');
  await expect(tab('Read aloud')).toBeFocused();
  await page.keyboard.press('Home');
  await expect(tab('Look')).toBeFocused();
  await page.keyboard.press('End');
  await expect(tab('Read aloud')).toBeFocused();
  await shown('Read aloud');
  // Tab leaves the tabs for the panel, not the next tab
  await page.keyboard.press('Tab');
  await expect(panel('Read aloud').getByRole('combobox', { name: 'Reading speed' })).toBeFocused();
  // one Escape closes the sheet, and it opens on Look again
  await page.keyboard.press('Escape');
  await expect(sheet(page)).toBeHidden();
  await openSettings(page);
  await shown('Look');
  expect(errors).toEqual([]);
});

test('size, line spacing and margins change the page, and are kept', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, { title: 'Typeset', author: 'Settings Tests', rawChapters: chapters(2) });
  await openSettings(page);
  await slider(page, 'Size').fill('28');
  await expect.poll(() => style(page, 'fontSize')).toBe('28px');
  await slider(page, 'Line spacing').fill('20');
  await expect.poll(() => style(page, 'lineHeight')).toBe(`${28 * 2}px`);
  const narrow = await style(page, 'paddingLeft');
  await openReadingSettings(page, 'Page');
  await moreSlider(page, 'Margins').fill('4');
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
  const group = name => more(page).getByRole('group', { name });
  // ragged and hyphenated to start with (WCAG 1.4.8: not justified)
  expect(await style(page, 'textAlign')).toBe('start');
  expect(await style(page, 'hyphens')).toBe('auto');
  expect(await style(page, 'letterSpacing')).toBe('normal');
  await openReadingSettings(page, 'Page');
  await expect(group('Justify text').getByRole('button', { name: 'Off' })).toHaveAttribute('aria-pressed', 'true');
  await group('Justify text').getByRole('button', { name: 'On' }).click();
  await expect.poll(() => style(page, 'textAlign')).toBe('justify');
  await expect(group('Justify text').getByRole('button', { name: 'On' })).toHaveAttribute('aria-pressed', 'true');
  await group('Hyphenation').getByRole('button', { name: 'Off' }).click();
  await expect.poll(() => style(page, 'hyphens')).toBe('manual');
  // the spacings reach what WCAG 1.4.12 asks a page to take
  await openReadingSettings(page, 'Look');
  await moreSlider(page, 'Paragraph spacing').fill('20');
  await expect.poll(() => style(page, 'marginBottom')).toBe(`${18 * 2}px`);
  await moreSlider(page, 'Letter spacing').fill('12');
  await expect.poll(async () => parseFloat(await style(page, 'letterSpacing'))).toBeCloseTo(18 * 0.12, 1);
  await moreSlider(page, 'Word spacing').fill('16');
  await expect.poll(async () => parseFloat(await style(page, 'wordSpacing'))).toBeCloseTo(18 * 0.16, 1);
  await expect(more(page)).toContainText('0.12');
  await choose(page, 'Close');
  await toLibrary(page);
  await reload(page);
  await openBook(page, 'Spaced');
  await expect.poll(() => style(page, 'textAlign')).toBe('justify');
  expect(await style(page, 'hyphens')).toBe('manual');
  expect(await style(page, 'marginBottom')).toBe(`${18 * 2}px`);
  expect(parseFloat(await style(page, 'letterSpacing'))).toBeCloseTo(18 * 0.12, 1);
  expect(parseFloat(await style(page, 'wordSpacing'))).toBeCloseTo(18 * 0.16, 1);
  // the sheet scrolls on a short window to its last row
  await openReadingSettings(page, 'Look');
  const reset = more(page).getByRole('button', { name: 'Reset to defaults', exact: true });
  await reset.scrollIntoViewIfNeeded();
  await expect(reset).toBeInViewport();
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
  const dim = more(page).getByRole('group', { name: 'Dim images in the dark themes' });
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
  // midday: at night, auto is the night theme whatever the system asks
  await page.clock.install({ time: new Date('2026-06-01T12:00:00Z') });
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
  await sheet(page).getByRole('group', { name: 'Theme' }).getByRole('button', { name: 'Auto', exact: true }).click();
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
  // resetting (at the end of the sheet, under every tab) asks nothing,
  // and can be undone
  await openReadingSettings(page, 'Page');
  const reset = more(page).getByRole('button', { name: 'Reset to defaults', exact: true });
  await reset.click();
  await expect.poll(() => style(page, 'fontSize')).toBe(before);
  await page.getByRole('button', { name: 'Undo' }).click();
  await expect.poll(() => style(page, 'fontSize')).toBe('30px');
  await more(page).getByRole('group', { name: 'Justify text' }).getByRole('button', { name: 'On', exact: true }).click();
  await expect.poll(() => style(page, 'textAlign')).toBe('justify');
  await reset.click();
  await expect.poll(() => style(page, 'fontSize')).toBe(before);
  expect(await style(page, 'textAlign')).toBe('start');
  await openReadingSettings(page, 'Look');
  await expect(slider(page, 'Size')).toHaveValue(String(parseInt(before, 10)));
});

// Auto by the clock: night by the local time (local_time.bats, from the
// host's clock and time zone), which the theme follows at the next page
// turn
test.describe('auto at night', () => {
  test.use({ timezoneId: 'Europe/Paris', colorScheme: 'light' });
  test('auto turns to Night at 22:00 local time, at the next page turn, and back by morning', async ({ page }) => {
    // 21:58 in Paris (UTC+2 in June)
    await page.clock.install({ time: new Date('2026-06-01T19:58:00Z') });
    await start(page);
    await readBook(page, { title: 'Late', author: 'Settings Tests', rawChapters: chapters(1, 60) });
    const theme = () => page.evaluate(() => document.getElementById('bats-root').className);
    expect(await theme()).toContain('th-light');
    await page.clock.runFor('03:00');
    await page.keyboard.press('ArrowRight');
    await expect.poll(theme).toContain('th-night');
    // chosen, a theme is kept at night
    await openSettings(page);
    await choose(page, 'Sepia');
    await expect.poll(theme).toContain('th-sepia');
    await sheet(page).getByRole('group', { name: 'Theme' }).getByRole('button', { name: 'Auto', exact: true }).click();
    await expect.poll(theme).toContain('th-night');
    await page.keyboard.press('Escape');
    // 07:01
    await page.clock.runFor('09:00:00');
    await page.keyboard.press('ArrowRight');
    await expect.poll(theme).toContain('th-light');
  });
});

test('in the Android app, the screen: full screen, the rotation locked and the brightness', async ({ page }) => {
  await page.addInitScript(() => {
    window.calls = [];
    const call = name => a => { window.calls.push(name + (a ? ' ' + JSON.stringify(a) : '')); return Promise.resolve(); };
    window.Capacitor = { isNativePlatform: () => true, Plugins: {
      StatusBar: { hide: call('hide'), show: call('show') },
      ScreenOrientation: { lock: call('lock'), unlock: call('unlock') },
      ScreenBrightness: { setBrightness: call('brightness') },
    } };
  });
  await start(page);
  await readBook(page, { title: 'Screened', author: 'Settings Tests', rawChapters: chapters(1) });
  await openReadingSettings(page, 'Page');
  const full = more(page).getByRole('button', { name: 'Full screen', exact: true });
  const lock = more(page).getByRole('button', { name: 'Lock rotation', exact: true });
  const brightness = more(page).getByRole('combobox', { name: 'Brightness' });
  await full.click();
  await expect(full).toHaveAttribute('aria-pressed', 'true');
  await lock.click();
  await expect(lock).toHaveAttribute('aria-pressed', 'true');
  await brightness.selectOption({ label: '25%' });
  await expect.poll(() => page.evaluate(() => window.calls.map(c => c.split(' ')[0]))).toEqual(['hide', 'lock', 'brightness']);
});

test('in a browser tab, the screen offers only what it can: no rotation lock or brightness', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Tabbed', author: 'Settings Tests', rawChapters: chapters(1) });
  await openReadingSettings(page, 'Page');
  await expect(more(page).getByRole('button', { name: 'Lock rotation', exact: true })).toBeHidden();
  await expect(more(page).getByRole('combobox', { name: 'Brightness' })).toBeHidden();
});

// The night's edges, exactly, in another zone: New York in June is
// UTC-4, so 21:59 there is 01:59 UTC
test.describe('auto at night, to the minute', () => {
  test.use({ timezoneId: 'America/New_York', colorScheme: 'light' });
  test('night starts at 22:00 and ends at 07:00 local time', async ({ page }) => {
    await page.clock.install({ time: new Date('2026-06-02T01:59:00Z') });
    await start(page);
    await readBook(page, { title: 'Edges', author: 'Settings Tests', rawChapters: chapters(1, 80) });
    const theme = () => page.evaluate(() => document.getElementById('bats-root').className);
    const turn = () => page.keyboard.press('ArrowRight');
    expect(await theme()).toContain('th-light');
    // 21:59:30: still the day
    await page.clock.runFor('00:30');
    await turn();
    await page.waitForTimeout(100);
    expect(await theme()).toContain('th-light');
    // 22:00
    await page.clock.runFor('00:30');
    await turn();
    await expect.poll(theme).toContain('th-night');
    // 06:59
    await page.clock.runFor('08:59:00');
    await turn();
    await page.waitForTimeout(100);
    expect(await theme()).toContain('th-night');
    // 07:00
    await page.clock.runFor('01:00');
    await turn();
    await expect.poll(theme).toContain('th-light');
  });
});

test('in a browser, Full screen goes into full screen and out of it, its button pressed as it is', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Fullscreened', author: 'Settings Tests', rawChapters: chapters(1) });
  await openReadingSettings(page, 'Page');
  const full = more(page).getByRole('button', { name: 'Full screen', exact: true });
  await expect(full).toHaveAttribute('aria-pressed', 'false');
  await full.click();
  await expect.poll(() => page.evaluate(() => !!document.fullscreenElement)).toBe(true);
  await expect(full).toHaveAttribute('aria-pressed', 'true');
  await full.click();
  await expect.poll(() => page.evaluate(() => !!document.fullscreenElement)).toBe(false);
  await expect(full).toHaveAttribute('aria-pressed', 'false');
});

// The Android app's plugins, each call kept; and a speech engine with
// voices (none says anything here)
async function deviceStubs(page) {
  await page.addInitScript(() => {
    window.calls = [];
    const call = name => a => { window.calls.push(name + (a ? ' ' + JSON.stringify(a) : '')); return Promise.resolve(); };
    window.Capacitor = { isNativePlatform: () => true, Plugins: {
      StatusBar: { hide: call('hide'), show: call('show') },
      ScreenOrientation: { lock: call('lock'), unlock: call('unlock') },
      ScreenBrightness: { setBrightness: call('brightness') },
    } };
    window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
    const voices = [
      { name: 'Reader', lang: 'en-US', voiceURI: 'reader-en', default: true },
      { name: 'Narrator', lang: 'en-GB', voiceURI: 'narrator-en', default: false },
    ];
    Object.defineProperty(window, 'speechSynthesis', { value: {
      getVoices: () => voices, speak() {}, cancel() {}, pause() {}, resume() {}, addEventListener() {},
    } });
  });
}

test('reset puts reading aloud\'s speed and voice, the brightness and the rotation lock back too, and Undo returns them', async ({ page }) => {
  await deviceStubs(page);
  await start(page);
  await readBook(page, { title: 'Device Reset', author: 'Settings Tests', rawChapters: chapters(1, 5) });
  await openReadingSettings(page, 'Read aloud');
  const speed = more(page).getByRole('combobox', { name: 'Reading speed' });
  const voice = more(page).getByRole('combobox', { name: 'Voice' });
  const brightness = more(page).getByRole('combobox', { name: 'Brightness' });
  const lock = more(page).getByRole('button', { name: 'Lock rotation', exact: true });
  await speed.selectOption('1.5');
  await voice.selectOption({ label: 'Narrator' });
  await openReadingSettings(page, 'Page');
  await brightness.selectOption({ label: '25%' });
  await lock.click();
  await expect(lock).toHaveAttribute('aria-pressed', 'true');
  await more(page).getByRole('button', { name: 'Reset to defaults', exact: true }).click();
  await expect(brightness).toHaveValue('system');
  await expect(lock).toHaveAttribute('aria-pressed', 'false');
  await openReadingSettings(page, 'Read aloud');
  await expect(speed).toHaveValue('1');
  await expect(voice.locator('option:checked')).toHaveText('Automatic');
  await expect.poll(() => page.evaluate(() => window.calls.slice(-2))).toEqual(['brightness {"brightness":-1}', 'unlock']);
  await page.getByRole('button', { name: 'Undo' }).click();
  await expect(speed).toHaveValue('1.5');
  await expect(voice.locator('option:checked')).toHaveText('Narrator');
  await openReadingSettings(page, 'Page');
  await expect(brightness).toHaveValue('25');
  await expect(lock).toHaveAttribute('aria-pressed', 'true');
  await expect.poll(() => page.evaluate(() => window.calls.slice(-2).map(c => c.split(' ')[0]))).toEqual(['brightness', 'lock']);
  expect(await page.evaluate(() => window.calls.slice(-2)[0])).toBe('brightness {"brightness":0.25}');
});

// Auto by the clock, without a page turned: night is checked each
// minute while a book is open
test.describe('auto at night, while the page stays', () => {
  test.use({ timezoneId: 'Europe/Paris', colorScheme: 'light' });
  test('auto turns to Night at 22:00 and back at 07:00 with no page turned', async ({ page }) => {
    // 21:58 in Paris (UTC+2 in June)
    await page.clock.install({ time: new Date('2026-06-01T19:58:00Z') });
    await start(page);
    await readBook(page, { title: 'Still', author: 'Settings Tests', rawChapters: chapters(1, 5) });
    const theme = () => page.evaluate(() => document.getElementById('bats-root').className);
    expect(await theme()).toContain('th-light');
    await page.clock.runFor('03:00');
    await expect.poll(theme).toContain('th-night');
    // 07:01
    await page.clock.runFor('09:00:00');
    await expect.poll(theme).toContain('th-light');
  });
});
