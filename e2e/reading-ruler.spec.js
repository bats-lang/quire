// The reading ruler (#566): a band over the text that holds the eye to one line, in the styles of
// Niklaus et al., Digital Reading Rulers (CHI 2023): an underline, a grey bar under the text, a
// shade over what was read and a lightbox dimming all but the lines. Off to begin with; kept with
// the device's settings. What is checked is the page as drawn: where the band lies against the
// text's own line boxes (Range.getClientRects), and the colours as the browser computes them.

import { test, expect } from './fixtures.js';
import { readFileSync } from 'node:fs';
import {
  start, readBook, bookPage, place, showChrome, topBar, control, readingSettings, openReadingSettings,
  rawMouse, exportedBackup, toLibrary, openBook, reload, oneColumn, rawFile, dialog,
  librarySettings, settingsButton, restoreInput, clockNow,
} from './helpers.js';

const sentences = k => `Sentence ${k} one is said here. Then comes a second one, which is a little longer than the first. Last of the three ends.`;
// the first paragraph is long, so its lines are alike: a ruler of five lines lies inside it
const paragraphs = `<p>${sentences(0)} ${'lorem ipsum dolor sit amet '.repeat(60)}</p>`
  + Array.from({ length: 60 }, (_, k) => `<p>${sentences(k + 1)} ${'lorem ipsum dolor sit amet '.repeat(6)}</p>`).join('');
const book = title => ({ title, author: 'Ruler Tests', rawChapters: [{ body: paragraphs }, { body: paragraphs }] });

// reading ruler: the retry ruler_retry arms (src/reading_ruler.bats, timer_set) for a ruler that could not be placed under the sheet
const RULER_RETRY_MS = 50;

// the page's clock is the fake one (#657), installed before the page opens, so the retry is run to, never waited for
test.beforeEach(async ({ page }) => {
  await page.clock.install();
});

/** Sets the reading ruler's style (and the lines it holds) from the reading settings' Look tab */
async function choose(page, style, lines) {
  await openReadingSettings(page, 'Look');
  const sheet = readingSettings(page);
  await sheet.getByRole('group', { name: 'Reading ruler', exact: true }).getByRole('button', { name: style, exact: true }).click();
  if (lines) await sheet.getByRole('group', { name: 'Ruler height', exact: true })
    .getByRole('button', { name: lines === 1 ? '1 line' : `${lines} lines`, exact: true }).click();
  await page.keyboard.press('Escape');
  await expect(sheet).toBeHidden();
  await page.clock.runFor(RULER_RETRY_MS);
}

/** The text area, the band and the two veils as drawn (null for one not shown), in viewport px */
const drawn = page => page.evaluate(() => {
  const box = id => {
    const e = document.getElementById(id);
    if (!e || getComputedStyle(e).display === 'none') return null;
    const r = e.getBoundingClientRect();
    return { top: r.top, bottom: r.bottom, left: r.left, right: r.right };
  };
  const area = document.getElementById('ruler');
  const r = area.getBoundingClientRect();
  const band = box('ruler-band'), before = box('ruler-before'), after = box('ruler-after');
  // the lines held bright: the band when it is drawn, else what the veils leave (Shade: from where the
  // veil over what was read ends)
  const held = band || (before ? { top: before.bottom, bottom: after ? after.top : r.bottom } : null);
  return {
    kind: area.className, shown: getComputedStyle(area).display !== 'none',
    area: { top: r.top, bottom: r.bottom, left: r.left, right: r.right },
    band, before, after, held,
    placed: document.getElementById('style-ruler').textContent.includes('left'),
  };
});

/** The lines of text in the area, as the browser lays them out (a line's glyph boxes joined), top to bottom
    for a horizontal page, right to left for a vertical one */
const lineBoxes = page => page.evaluate(() => {
  const area = document.getElementById('ruler').getBoundingClientRect();
  const vertical = /vertical/.test(getComputedStyle(document.getElementById('page')).writingMode);
  const walker = document.createTreeWalker(document.getElementById('page'), NodeFilter.SHOW_TEXT);
  const found = [];
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    if (!node.textContent.trim()) continue;
    const range = document.createRange();
    range.selectNodeContents(node);
    for (const r of range.getClientRects()) {
      if (r.width < 2 || r.height < 2) continue;
      if (r.top < area.top - 1 || r.bottom > area.bottom + 1 || r.left < area.left - 1 || r.right > area.right + 1) continue;
      found.push({ top: r.top, bottom: r.bottom, left: r.left, right: r.right });
    }
  }
  const lines = [];
  for (const r of found.sort((a, b) => vertical ? b.right - a.right : a.top - b.top)) {
    const last = lines[lines.length - 1];
    const same = last && (vertical ? Math.abs(last.right - r.right) < 4 : Math.abs(last.top - r.top) < 4);
    if (same) { last.left = Math.min(last.left, r.left); last.right = Math.max(last.right, r.right); last.top = Math.min(last.top, r.top); last.bottom = Math.max(last.bottom, r.bottom); }
    else lines.push({ ...r });
  }
  return lines;
});

/** The text's line height in px */
const lineHeight = page => bookPage(page).evaluate(e => parseFloat(getComputedStyle(e).lineHeight));

const mid = (a, b) => (a + b) / 2;
/** The middle of a line box along the lines' stacking */
const across = line => mid(line.top, line.bottom);
/** The band's middle of the first line it holds: its top plus half a line */
const bandFirst = (band, height) => band.top + height / 2;

const STYLES = [['Underline', 'ruler-underline'], ['Grey bar', 'ruler-grey'], ['Shade', 'ruler-shade'], ['Lightbox', 'ruler-lightbox']];

test('the ruler is off to begin with, and nothing of it is drawn', async ({ page }) => {
  await start(page);
  await readBook(page, book('Unruled'));
  const state = await drawn(page);
  expect(state.shown).toBe(false);
  expect(state.band).toBeNull();
  await openReadingSettings(page, 'Look');
  const group = readingSettings(page).getByRole('group', { name: 'Reading ruler', exact: true });
  await expect(group.getByRole('button', { name: 'Off', exact: true })).toHaveAttribute('aria-pressed', 'true');
  // the height is a choice of the styles that have one
  await expect(readingSettings(page).getByRole('group', { name: 'Ruler height', exact: true })).toBeHidden();
});

test('a ruler chosen under the settings sheet is placed by the retry after the sheet closes, not before', async ({ page }) => {
  await start(page);
  await readBook(page, book('Retry'));
  // the clock stands still from here: the retry's moment comes only when the test runs it
  await page.clock.pauseAt((await clockNow(page)) + 1000);
  await openReadingSettings(page, 'Look');
  const sheet = readingSettings(page);
  await sheet.getByRole('group', { name: 'Reading ruler', exact: true }).getByRole('button', { name: 'Grey bar', exact: true }).click();
  await page.keyboard.press('Escape');
  await expect(sheet).toBeHidden();
  expect((await drawn(page)).placed).toBe(false);
  await page.clock.runFor(RULER_RETRY_MS);
  await expect.poll(async () => (await drawn(page)).placed).toBe(true);
});

for (const [style, kind] of STYLES) {
  const heights = style === 'Grey bar' || style === 'Lightbox' ? [1, 3, 5] : [0];
  for (const lines of heights) {
    test(`${style} is drawn on the first line of the page${lines ? `, holding ${lines} line${lines > 1 ? 's' : ''}` : ''}`, async ({ page }) => {
      await start(page);
      await readBook(page, book(`Ruled ${style} ${lines}`));
      await choose(page, style, lines || undefined);
      await expect.poll(async () => (await drawn(page)).placed).toBe(true);
      const state = await drawn(page);
      expect(state.kind).toContain(kind);
      const height = await lineHeight(page);
      const text = await lineBoxes(page);
      const count = lines || 1;
      const band = state.held;
      if (style === 'Shade') {
        // only what was read is dimmed; the band is not drawn
        expect(state.before).not.toBeNull();
        expect(state.after).toBeNull();
        expect(state.before.top).toBeCloseTo(state.area.top, 0);
        // the line the ruler is on is the first: nothing of it is under the veil
        expect(state.before.bottom).toBeLessThanOrEqual(text[0].top + 1);
        expect(state.before.bottom).toBeGreaterThan(text[0].top - height);
        return;
      }
      expect(band, 'the band').not.toBeNull();
      // the lines it holds are inside it, and the line after them is not
      for (let k = 0; k < count; k++) {
        expect(across(text[k]), `line ${k} is in the band`).toBeGreaterThan(band.top);
        expect(across(text[k]), `line ${k} is in the band`).toBeLessThan(band.bottom);
      }
      expect(across(text[count]), 'the next line is out of it').toBeGreaterThan(band.bottom);
      // (the veils' edges are whole px)
      expect(Math.abs(band.bottom - band.top - count * height)).toBeLessThan(4);
      // it starts at the first line: its middle is near the first line's
      expect(Math.abs(bandFirst(band, height) - across(text[0]))).toBeLessThan(5);
      if (style === 'Underline') {
        // a line along the foot of the band, in the text's own colour
        const shadow = await page.locator('#ruler-band').evaluate(e => getComputedStyle(e).boxShadow);
        const text_colour = await page.locator('#page').evaluate(e => getComputedStyle(e).color);
        expect(shadow).toContain(text_colour);
        expect(state.before).toBeNull();
        expect(state.after).toBeNull();
      }
      if (style === 'Grey bar') {
        // under the text, not over it
        expect(await page.locator('#ruler-band').evaluate(e => getComputedStyle(e).zIndex)).toBe('-1');
        expect(state.before).toBeNull();
        expect(state.after).toBeNull();
      }
      if (style === 'Lightbox') {
        expect(state.before.bottom).toBeCloseTo(band.top, 0);
        expect(state.after.top).toBeCloseTo(band.bottom, 0);
        expect(state.before.top).toBeCloseTo(state.area.top, 0);
        expect(state.after.bottom).toBeCloseTo(state.area.bottom, 0);
      }
    });
  }
}

test('a page turn puts the ruler on the first line of the page turned to', async ({ page }) => {
  await start(page);
  await readBook(page, book('Turned'));
  await choose(page, 'Grey bar', 3);
  const first = await place(page);
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => JSON.stringify(await place(page))).not.toBe(JSON.stringify(first));
  const height = await lineHeight(page);
  await expect.poll(async () => {
    const state = await drawn(page);
    const text = await lineBoxes(page);
    return state.held && text.length ? Math.abs(bandFirst(state.held, height) - across(text[0])) < 5 : false;
  }).toBe(true);
});

test('a tap between the sides on another line moves the ruler there, and a tap on its own line brings up the bars', async ({ page }) => {
  await start(page);
  await readBook(page, book('Tapped'));
  await oneColumn(page);
  await choose(page, 'Underline');
  await expect.poll(async () => (await drawn(page)).placed).toBe(true);
  const height = await lineHeight(page);
  const text = await lineBoxes(page);
  const x = mid(text[4].left, text[4].right);
  // no timer hides the bars (#560): the reader puts them away, by the key (a tap would move the ruler)
  if (await topBar(page).isVisible()) await page.keyboard.press('t');
  await expect(topBar(page)).toBeHidden();
  await rawMouse(page, 'click', x, across(text[4]));
  await expect.poll(async () => {
    const { band } = await drawn(page);
    return band ? Math.abs(bandFirst(band, height) - across(text[4])) < 5 : false;
  }).toBe(true);
  // the bars stay away: the tap moved the ruler and did no more
  await expect(topBar(page)).toBeHidden();
  // on its own line, the tap is the page's: the bars come up
  await rawMouse(page, 'click', x, across(text[4]));
  await expect(topBar(page)).toBeVisible();
});

// pointer events of one finger on the page, as the reader's listener gets them
const finger = (page, x, ys, id) =>
  bookPage(page).evaluate(async (el, [x, ys, id]) => {
    const event = (type, y) => el.dispatchEvent(new PointerEvent(type, {
      bubbles: true, pointerId: id, pointerType: 'touch', isPrimary: true, clientX: x, clientY: y,
    }));
    const wait = t => new Promise(r => setTimeout(r, t));
    event('pointerdown', ys[0]);
    for (const y of ys.slice(1)) { await wait(16); event('pointermove', y); }
    await wait(16);
    event('pointerup', ys[ys.length - 1]);
  }, [x, ys, id]);

test('a finger on the band drags it from line to line, and the page does not turn', async ({ page }) => {
  await start(page);
  test.skip(!(await page.evaluate(() => navigator.maxTouchPoints > 0)), 'a drag by touch or pen: a mouse drag selects text, and moves the ruler by a tap');
  await readBook(page, book('Dragged'));
  await oneColumn(page);
  await choose(page, 'Grey bar', 1);
  await expect.poll(async () => (await drawn(page)).placed).toBe(true);
  const height = await lineHeight(page);
  const text = await lineBoxes(page);
  const { band } = await drawn(page);
  const where = await place(page);
  const x = mid(text[0].left, text[0].right);
  const target = across(text[4]);
  const from = mid(band.top, band.bottom);
  await finger(page, x, [0, 1, 2, 3, 4].map(k => from + (target - from) * k / 4), 41);
  await expect.poll(async () => Math.abs(bandFirst((await drawn(page)).band, height) - target) < 5).toBe(true);
  expect(await place(page)).toEqual(where);
});

test('the ruler follows the sentence read aloud', async ({ page }) => {
  await page.addInitScript(() => {
    window.spoken = [];
    window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
    const synth = {
      current: null,
      getVoices: () => [{ name: 'Reader', lang: 'en-US', voiceURI: 'reader-en', default: true }],
      speak(u) { window.spoken.push({ text: u.text }); this.current = u; },
      cancel() { const u = this.current; this.current = null; if (u && u.onerror) u.onerror({ error: 'interrupted' }); },
      addEventListener() {},
    };
    Object.defineProperty(window, 'speechSynthesis', { value: synth });
    window.sentenceSpoken = () => { const u = synth.current; synth.current = null; if (u && u.onend) u.onend({}); };
  });
  await start(page);
  await readBook(page, book('Followed'));
  await choose(page, 'Grey bar', 1);
  const height = await lineHeight(page);
  await showChrome(page);
  await control(page, 'Read aloud').click();
  let moved = 0;
  for (let k = 0; k < 6; k++) {
    await expect.poll(async () => (await page.evaluate(() => window.spoken.length))).toBe(k + 1);
    // the first line of the sentence said
    const sentence = await page.evaluate(() => {
      const [range] = [...CSS.highlights.get('bats-mark-5')];
      const r = range.getClientRects()[0];
      return { top: r.top, bottom: r.bottom };
    });
    const { band } = await drawn(page);
    expect(band, `the band at sentence ${k}`).not.toBeNull();
    expect(Math.abs(bandFirst(band, height) - across(sentence)), `sentence ${k} is on the band's line`).toBeLessThan(5);
    if (k > 0 && Math.abs(band.top - moved) > 1) moved = band.top;
    else if (k === 0) moved = band.top;
    await page.evaluate(() => window.sentenceSpoken());
  }
  expect(moved, 'the band moved down the page as the sentences went on').toBeGreaterThan(0);
});

test('scrolled, the ruler keeps its height and the text moves under it', async ({ page }) => {
  await start(page);
  await readBook(page, book('Scrolled'));
  await openReadingSettings(page, 'Page');
  await readingSettings(page).getByRole('group', { name: 'Layout', exact: true }).getByRole('button', { name: 'Scroll', exact: true }).click();
  await page.keyboard.press('Escape');
  await choose(page, 'Lightbox', 1);
  await expect.poll(async () => (await drawn(page)).placed).toBe(true);
  const height = await lineHeight(page);
  const before = await drawn(page);
  const top = await bookPage(page).evaluate(e => e.scrollTop);
  await page.keyboard.press('ArrowRight');
  await expect.poll(() => bookPage(page).evaluate(e => e.scrollTop)).toBeGreaterThan(top);
  const after = await drawn(page);
  // at the same height, to a line
  expect(Math.abs(after.held.top - before.held.top)).toBeLessThanOrEqual(height);
  // and on a line of the text now shown
  await expect.poll(async () => {
    const [text, now] = [await lineBoxes(page), await drawn(page)];
    const centre = bandFirst(now.held, height);
    return text.some(line => Math.abs(across(line) - centre) < 5);
  }).toBe(true);
});

// paragraphs only: the first columns are alike
const verticalBody = Array.from({ length: 30 }, () => `<p>${'吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。'.repeat(8)}</p>`).join('');

test('set vertically, the ruler lies along a column of the page', async ({ page }) => {
  await start(page);
  await readBook(page, { title: '縦書きの定規', author: 'Ruler Tests', language: 'ja', rtl: true, rawChapters: [{ body: verticalBody }, { body: verticalBody }] });
  await choose(page, 'Grey bar', 3);
  await expect.poll(async () => (await drawn(page)).placed).toBe(true);
  const state = await drawn(page);
  const height = await lineHeight(page);
  const text = await lineBoxes(page);
  const { band } = state;
  expect(state.kind).toContain('ruler-down');
  // the band is as tall as the area and as wide as three columns
  expect(band.top).toBeCloseTo(state.area.top, 0);
  expect(band.bottom).toBeCloseTo(state.area.bottom, 0);
  expect(Math.abs(band.right - band.left - 3 * height)).toBeLessThan(2);
  // the first column, at the right, is in it; the fourth is not
  for (let k = 0; k < 3; k++) {
    const centre = mid(text[k].left, text[k].right);
    expect(centre).toBeGreaterThan(band.left);
    expect(centre).toBeLessThan(band.right);
  }
  expect(mid(text[3].left, text[3].right)).toBeLessThan(band.left);
});

// the colours as computed: the underline's, the grey bar's, the veil's, in the five themes
const THEMES = ['Light', 'Sepia', 'Dark', 'Night', 'Grey'];

test('the ruler keeps the stated contrast in every theme: the underline 3:1, the grey bar 7:1 for the text and 4.5:1 for a link, the dimmed lines 4.5:1, 3:1 and 3:1', async ({ page }) => {
  await start(page);
  await readBook(page, book('Contrast'));
  const measured = {};
  // from the open sheet: the colours are computed whether or not the band is placed under the sheet
  await openReadingSettings(page, 'Look');
  const sheet = readingSettings(page);
  for (const theme of THEMES) {
    await sheet.getByRole('group', { name: 'Theme', exact: true }).getByRole('button', { name: theme, exact: true }).click();
    for (const [style] of STYLES) {
      await sheet.getByRole('group', { name: 'Reading ruler', exact: true }).getByRole('button', { name: style, exact: true }).click();
      await expect.poll(async () => (await drawn(page)).kind).toContain(STYLES.find(([name]) => name === style)[1]);
      measured[`${theme} ${style}`] = await page.evaluate(() => {
        const parse = value => {
          const numbers = value.match(/-?[\d.]+(?:e-?\d+)?/g).map(Number);
          if (/^color\(srgb/.test(value)) return { channels: numbers.slice(0, 3).map(v => v * 255), alpha: numbers.length > 3 ? numbers[3] : 1 };
          return { channels: numbers.slice(0, 3), alpha: numbers.length > 3 ? numbers[3] : 1 };
        };
        const role = name => {
          const probe = document.createElement('i');
          probe.style.color = `var(--${name})`;
          document.querySelector('.app').append(probe);
          const colour = parse(getComputedStyle(probe).color);
          probe.remove();
          return colour.channels.map(Math.round);
        };
        const band = document.getElementById('ruler-band');
        const veil = document.getElementById('ruler-before');
        return {
          fg: role('fg'), bg: role('bg'), accent: role('accent'), ruler: role('ruler'), hl: role('hl'),
          shadow: getComputedStyle(band).boxShadow,
          bandBackground: parse(getComputedStyle(band).backgroundColor),
          veilBackground: parse(getComputedStyle(veil).backgroundColor),
        };
      });
    }
  }
  await page.keyboard.press('Escape');
  const linear = v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
  const luminance = c => 0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2]);
  const contrast = (a, b) => { const [x, y] = [luminance(a), luminance(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
  const over = (c, ground, alpha) => c.map((v, i) => Math.round(v * (1 - alpha) + ground[i] * alpha));
  const report = {};
  for (const [name, m] of Object.entries(measured)) {
    if (name.endsWith('Underline')) {
      const rgb = m.shadow.match(/rgb\((\d+), (\d+), (\d+)\)/).slice(1).map(Number);
      expect(rgb, name).toEqual(m.fg);
      report[name] = contrast(rgb, m.bg);
      expect(report[name], name).toBeGreaterThanOrEqual(3);
    } else if (name.endsWith('Grey bar')) {
      expect(m.bandBackground.channels.map(Math.round), name).toEqual(m.ruler);
      report[`${name} text`] = contrast(m.fg, m.ruler);
      report[`${name} link`] = contrast(m.accent, m.ruler);
      expect(report[`${name} text`], name).toBeGreaterThanOrEqual(7);
      expect(report[`${name} link`], name).toBeGreaterThanOrEqual(4.5);
    } else if (name.endsWith('Shade') || name.endsWith('Lightbox')) {
      const alpha = m.veilBackground.alpha;
      const veil = m.veilBackground.channels.map(Math.round);
      expect(veil, `${name}: the veil is the page's ground`).toEqual(m.bg);
      const dim = c => over(c, m.bg, alpha);
      report[`${name} text`] = contrast(dim(m.fg), m.bg);
      report[`${name} link`] = contrast(dim(m.accent), m.bg);
      report[`${name} highlight`] = contrast(dim(m.fg), dim(m.hl));
      expect(report[`${name} text`], name).toBeGreaterThanOrEqual(4.5);
      expect(report[`${name} link`], name).toBeGreaterThanOrEqual(3);
      expect(report[`${name} highlight`], name).toBeGreaterThanOrEqual(3);
    }
  }
  console.log(JSON.stringify(report, null, 1));
});

test('the ruler is a device setting: kept across a relaunch, in the backup, reset with the settings and brought back by Undo', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, book('Kept'));
  await choose(page, 'Lightbox', 3);
  await reload(page);
  await expect(bookPage(page)).toBeVisible();
  await expect.poll(async () => (await drawn(page)).kind).toContain('ruler-lightbox');
  const pressed = async (group, name) => readingSettings(page).getByRole('group', { name: group, exact: true }).getByRole('button', { name, exact: true });
  await openReadingSettings(page, 'Look');
  await expect(await pressed('Reading ruler', 'Lightbox')).toHaveAttribute('aria-pressed', 'true');
  await expect(await pressed('Ruler height', '3 lines')).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');
  // in the backup
  await toLibrary(page);
  await librarySettings(page);
  const backup = await exportedBackup(page);
  expect(JSON.parse(backup).settings.readingRuler).toBe(4);
  expect(JSON.parse(backup).settings.readingRulerLines).toBe(1);
  const path = rawFile('quire-backup.json', backup);
  await settingsButton(page, 'Back').click();
  // reset with the settings, and brought back by Undo
  await openBook(page, 'Kept');
  await openReadingSettings(page, 'Look');
  await readingSettings(page).getByRole('button', { name: 'Reset reading settings', exact: true }).click();
  await expect(await pressed('Reading ruler', 'Off')).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');
  await expect.poll(async () => (await drawn(page)).shown).toBe(false);
  await page.getByRole('button', { name: 'Undo' }).click();
  await expect.poll(async () => (await drawn(page)).kind).toContain('ruler-lightbox');
  // turned off by hand, then restored from the backup
  await choose(page, 'Off');
  await expect.poll(async () => (await drawn(page)).shown).toBe(false);
  await toLibrary(page);
  await librarySettings(page);
  await restoreInput(page).setInputFiles([path]);
  await expect(dialog(page, 'Backup restored')).toBeVisible();
  await dialog(page, 'Backup restored').getByRole('button', { name: 'Done' }).click();
  await openBook(page, 'Kept');
  await expect.poll(async () => (await drawn(page)).kind).toContain('ruler-lightbox');
  expect(JSON.parse(readFileSync(path, 'utf8')).settings.readingRuler).toBe(4);
  expect(errors).toEqual([]);
});

test('with the ruler on, a change of the layout leaves the paragraph the reader was at on the page shown', async ({ page }) => {
  await start(page);
  await readBook(page, book('Stable ruler'));
  await choose(page, 'Lightbox', 3);
  for (let k = 0; k < 3; k++) {
    const before = await place(page);
    await page.keyboard.press('ArrowRight');
    await expect.poll(async () => JSON.stringify(await place(page))).not.toBe(JSON.stringify(before));
  }
  const first = async () => bookPage(page).evaluate(doc => {
    const c = doc.getBoundingClientRect();
    for (const e of doc.querySelectorAll('p')) {
      const r = e.getClientRects()[0];
      if (r && r.left >= c.left - 2 && r.right <= c.right + 2 && r.top >= c.top - 2 && r.bottom <= c.bottom + 2) return e.textContent.slice(0, 14);
    }
    return null;
  });
  const paragraph = await first();
  expect(paragraph).toBeTruthy();
  await openReadingSettings(page, 'Look');
  await readingSettings(page).getByRole('group', { name: 'Theme', exact: true }).getByRole('button', { name: 'Dark', exact: true }).click();
  await readingSettings(page).getByRole('slider', { name: 'Size' }).fill('26');
  await page.keyboard.press('Escape');
  await expect.poll(() => bookPage(page).evaluate((doc, text) => {
    const c = doc.getBoundingClientRect();
    return [...doc.querySelectorAll('p')].some(e => e.textContent.startsWith(text) &&
      [...e.getClientRects()].some(r => r.right > c.left && r.left < c.right && r.bottom > c.top && r.top < c.bottom));
  }, paragraph)).toBe(true);
  // and the band is on a line of the page now shown
  await expect.poll(async () => (await drawn(page)).placed).toBe(true);
  const state = await drawn(page);
  const text = await lineBoxes(page);
  const height = await lineHeight(page);
  expect(state.held).not.toBeNull();
  expect(text.some(line => Math.abs(across(line) - bandFirst(state.held, height)) < 5)).toBe(true);
});
