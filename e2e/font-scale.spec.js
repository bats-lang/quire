// Android's system font scale at 130% and 200% (#412). A WebView
// multiplies every text size of the page by the scale (Chromium's
// AwSettings keeps the system font scale as the text size percent until
// the embedder calls setTextZoom, which Capacitor's shell does not), and
// leaves the boxes as the page made them: a button 48 px high stays 48 px
// high with text twice the size.
//
// Played with Chromium's own CSS property `text-size-adjust: <percentage>`
// on the root element, which multiplies the computed font size of all
// text and nothing else (the same effect, in the same engine; not the
// text autosizer that `--blink-settings=accessibilityFontScaleFactor`
// goes through, which skips Quire's boxes). The first test checks the
// engine really does it, so a Chromium that stopped would fail here and
// not pass for nothing. The app's own stylesheet and
// code are untouched; Quire sets no text-size-adjust of its own.
//
// What this does not show: the real WebView on a device, that is that
// its text zoom is unset in the Capacitor shell so the system scale
// reaches the page. That is the emulator job's (pwa's android.yml).
//
// The property scales text in a mobile viewport only, so the spec runs in
// the projects that have one (the android project among them).
//
// Android recreates the activity when the font scale changes, so the
// place across a change is a relaunch, not a live change.

import { test, expect } from './fixtures.js';
import {
  start, readBook, place, bookPage, chapters, openReadingSettings, readingSettings,
} from './helpers.js';
import { walkEveryScreen, appPlayed } from './walk.js';
import { fits } from './fits.js';
import { launch, relaunch, rested } from './relaunch.js';

const SCALES = [130, 200];

/** The voices a device that speaks has, so the Read aloud tab is built
    (it is only where the platform speaks) and walked at every scale */
function voicesPlayed() {
  window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
  const voices = [
    { name: 'Reader', lang: 'en-US', voiceURI: 'reader-en', default: true },
    { name: 'Narrator', lang: 'en-GB', voiceURI: 'narrator-en', default: false },
  ];
  Object.defineProperty(window, 'speechSynthesis', { value: {
    getVoices: () => voices, speak() {}, cancel() {}, pause() {}, resume() {}, addEventListener() {},
  } });
}

/** The script that makes every text size of the page scale percent of
    itself, before the app starts */
function scaledBy(percent) {
  // (a constructable style sheet: the app's content security policy
  // refuses a <style> element made by a script, not the CSSOM)
  return `(() => { const sheet = new CSSStyleSheet(); sheet.replaceSync('html { text-size-adjust: ${percent}%; -webkit-text-size-adjust: ${percent}%; }'); document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet]; })();`;
}

/** The size of the text of a chapter's first paragraph, in pixels */
function textSize(page) {
  return bookPage(page).evaluate(doc => parseFloat(getComputedStyle(doc.querySelector('p')).fontSize));
}

/** The first words of the first paragraph that begins on the page shown */
async function topParagraph(page) {
  return bookPage(page).evaluate(doc => {
    const c = doc.getBoundingClientRect();
    for (const e of doc.querySelectorAll('p')) {
      const r = e.getClientRects()[0];
      if (r && r.left >= c.left - 2 && r.right <= c.right + 2 && r.top >= c.top - 2 && r.bottom <= c.bottom + 2) return e.textContent.slice(0, 14);
    }
    return null;
  });
}

function onScreen(page, text) {
  return bookPage(page).evaluate((doc, text) => {
    const c = doc.getBoundingClientRect();
    return [...doc.querySelectorAll('p')].some(e => e.textContent.startsWith(text) &&
      [...e.getClientRects()].some(r => r.right > c.left && r.left < c.right && r.bottom > c.top && r.top < c.bottom));
  }, text);
}

test.skip(({ isMobile }) => !isMobile, 'text-size-adjust scales text in a mobile viewport only (the Android project)');

test('the engine multiplies a text size and leaves a box as it is', async ({ page }) => {
  await page.addInitScript(scaledBy(200));
  await page.goto('/');
  const measured = await page.evaluate(() => {
    const holder = document.createElement('div');
    holder.innerHTML = '<p id="engine-text" style="font-size:16px">Text</p><button id="engine-box" style="height:48px;font-size:16px">Box</button>';
    document.body.appendChild(holder);
    return [parseFloat(getComputedStyle(holder.children[0]).fontSize), holder.children[1].getBoundingClientRect().height];
  });
  expect(measured).toEqual([32, 48]);
});

for (const percent of SCALES) {
  test(`at a font scale of ${percent}% every screen fits`, async ({ page }) => {
    await page.addInitScript(appPlayed);
    await page.addInitScript(voicesPlayed);
    await page.addInitScript(scaledBy(percent));
    await page.goto('/');
    expect(await page.evaluate(() => parseFloat(getComputedStyle(document.body).fontSize)), 'the scale reached the app').toBeGreaterThan(16 * percent / 100 - 1);
    await walkEveryScreen(page, {
      look: screen => fits(page, `${screen} at ${percent}%`),
      back: () => page.keyboard.press('Escape'),
    });
  });
}

for (const percent of [100, ...SCALES]) {
  test(`at a font scale of ${percent}% the book's text is the Size setting once, not twice`, async ({ page }) => {
    await page.addInitScript(scaledBy(percent));
    await start(page);
    await readBook(page, { title: 'Scaled', author: 'Scale', rawChapters: chapters(1, 40) });
    for (const size of [18, 24]) {
      await openReadingSettings(page, 'Look');
      await readingSettings(page).getByRole('slider', { name: 'Size' }).fill(String(size));
      await page.keyboard.press('Escape');
      await expect.poll(() => textSize(page), `Size ${size} at ${percent}%`).toBeCloseTo(size * percent / 100, 1);
    }
  });
}

test('a book opens at the same paragraph after the font scale changes', async ({ context, page }) => {
  await launch(context, page);
  await readBook(page, { title: 'Rescaled', author: 'Scale', rawChapters: chapters(1, 90) });
  for (let k = 0; k < 7; k++) {
    const before = await place(page);
    await page.keyboard.press('ArrowRight');
    await expect.poll(async () => JSON.stringify(await place(page))).not.toBe(JSON.stringify(before));
  }
  let top = await topParagraph(page);
  expect(top).toBeTruthy();
  let current = page;
  for (const percent of [200, 130]) {
    await rested(current);
    // Android recreates the activity when the scale changes
    await context.addInitScript(scaledBy(percent));
    current = await relaunch(current, 'quit');
    await expect(bookPage(current)).toBeVisible();
    expect(await current.evaluate(() => parseFloat(getComputedStyle(document.body).fontSize))).toBeGreaterThan(16 * percent / 100 - 1);
    await expect.poll(() => onScreen(current, top), `at ${percent}%`).toBe(true);
    top = await topParagraph(current);
  }
});
