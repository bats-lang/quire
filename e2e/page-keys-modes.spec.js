// The page keys in every reading mode (#412, Bluetooth page turners and key
// input): the arrows, Page Up and Down, Space (Shift for back) and the media
// keys turn the page by one page in a paged book, in two columns, scrolled,
// in a vertical book and in a fixed-layout book, one press each, a burst of
// presses none lost, and a key held (its repeats) one page per repeat. Enter
// is not a page key (keys.spec.js: it follows the focused link), so it turns
// nothing with no link focused.
//
// The keys are the browser's own (`page.keyboard`, trusted events), so a
// key the browser also acts on (an arrow scrolls a focused scroller, Space
// pages it) is tested as the browser does it, not as a synthetic event would.
//
// Books in a vertical reading (Japanese, right to left) turn forward to the
// left, as the reader's own rule says (`_left`, `_right`): ArrowLeft and Space
// forward, ArrowRight back.

import { test, expect } from './fixtures.js';
import {
  start, readBook, place, fixedPlace, readFixed, fixedLayoutBook, japaneseChapters, chapters, bookPage,
  openReadingSettings, readingSettings, oneColumn, framesPassed,
} from './helpers.js';

const book = { title: 'Keyed Modes', author: 'Keys', rawChapters: chapters(1, 300) };
const vertical = { title: '縦 Modes', author: 'Keys', language: 'ja', rtl: true, rawChapters: japaneseChapters(1, 120) };

const reading = {
  forward: ['PageDown', ' ', 'ArrowRight', 'MediaTrackNext'],
  back: ['PageUp', 'Shift+ ', 'ArrowLeft', 'MediaTrackPrevious'],
};
const verticalReading = {
  forward: ['PageDown', ' ', 'ArrowLeft', 'MediaTrackNext'],
  back: ['PageUp', 'Shift+ ', 'ArrowRight', 'MediaTrackPrevious'],
};

/** The media keys have no name in Playwright's keyboard, so they are the
    keydown the browser sends the page, as keys.spec.js sends them */
const isMedia = key => key.startsWith('Media') || key.startsWith('AudioVolume');
const keydown = (page, key, init = {}) => page.evaluate(([k, i]) => {
  document.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true, ...i }));
}, [key, init]);

/** Presses one key, once: the Shift chord of Space is Shift held */
async function tap(page, key) {
  if (isMedia(key)) return keydown(page, key);
  if (key.startsWith('Shift+')) {
    await page.keyboard.down('Shift');
    await page.keyboard.press(key.slice('Shift+'.length));
    await page.keyboard.up('Shift');
  } else {
    await page.keyboard.press(key);
  }
}

/** Holds one key down through presses keydowns: the first, then the repeats
    the browser sends while it is held */
async function hold(page, key, presses) {
  if (isMedia(key)) {
    for (let k = 0; k < presses; k++) await keydown(page, key, { repeat: k > 0 });
    return;
  }
  for (let k = 0; k < presses; k++) await page.keyboard.down(key);
  await page.keyboard.up(key);
}

/** The scroll position of a scrolled book, in pages: its top over the
    distance a turn scrolls (measured by the first turn, below) */
const scrollTop = page => bookPage(page).evaluate(doc => doc.scrollTop);

/** Where the reader is, in pages: a paged book's page indicator (a
    spread counts as a screen), a fixed page, or a scrolled book's top
    over the distance one turn scrolls */
function positionOf(page, mode, unit) {
  if (mode.fixed) return fixedPlace(page).then(f => f.p);
  if (mode.scroll) return scrollTop(page).then(top => top / unit.px);
  return place(page).then(p => p.p);
}

const modes = [
  {
    name: 'paged, one column',
    keys: reading,
    open: async page => { await readBook(page, book); await oneColumn(page); },
  },
  {
    name: 'paged, two columns',
    keys: reading,
    open: async page => {
      await readBook(page, book);
      await openReadingSettings(page, 'Page');
      await readingSettings(page).getByRole('group', { name: 'Pages on screen' }).getByRole('button', { name: 'Two', exact: true }).click();
      await page.keyboard.press('Escape');
      await expect(readingSettings(page)).toBeHidden();
    },
  },
  {
    name: 'scrolled',
    scroll: true,
    keys: reading,
    open: async page => {
      await readBook(page, book);
      await openReadingSettings(page, 'Page');
      await readingSettings(page).getByRole('group', { name: 'Layout' }).getByRole('button', { name: 'Scroll', exact: true }).click();
      await page.keyboard.press('Escape');
      await expect(readingSettings(page)).toBeHidden();
    },
  },
  {
    name: 'vertical',
    keys: verticalReading,
    open: async page => { await readBook(page, vertical); },
  },
  {
    name: 'fixed-layout',
    fixed: true,
    keys: reading,
    open: async page => { await readFixed(page, fixedLayoutBook('Fixed Modes', 10)); await oneColumn(page); },
  },
];

for (const mode of modes) {
  // a scrolled book's unit is the scroll one turn makes, measured here
  const unit = { px: 1 };
  const where = page => positionOf(page, mode, unit);
  const measure = async page => {
    if (!mode.scroll) return;
    const before = await scrollTop(page);
    await tap(page, mode.keys.forward[0]);
    await expect.poll(() => scrollTop(page)).toBeGreaterThan(before);
    unit.px = (await scrollTop(page)) - before;
    await tap(page, mode.keys.back[0]);
    await expect.poll(() => scrollTop(page)).toBe(before);
  };

  test(`${mode.name}: each page key turns one page forward or back`, async ({ page }) => {
    const errors = await start(page);
    await mode.open(page);
    await measure(page);
    const first = await where(page);
    // each key moves the place by one page: forward, then back the same way
    for (const key of mode.keys.forward) {
      const before = await where(page);
      await tap(page, key);
      await expect.poll(() => where(page), key).toBeCloseTo(before + 1, 1);
    }
    for (const key of mode.keys.back) {
      const before = await where(page);
      await tap(page, key);
      await expect.poll(() => where(page), key).toBeCloseTo(before - 1, 1);
    }
    expect(await where(page)).toBeCloseTo(first, 1);
    expect(errors).toEqual([]);
  });

  test(`${mode.name}: a burst of presses turns one page for each, none lost`, async ({ page }) => {
    await start(page);
    await mode.open(page);
    await measure(page);
    const first = await where(page);
    // no wait between presses: each turn is still animating when the next comes
    for (let k = 0; k < 4; k++) await tap(page, mode.keys.forward[0]);
    await expect.poll(() => where(page)).toBeCloseTo(first + 4, 1);
    for (let k = 0; k < 3; k++) await tap(page, mode.keys.back[0]);
    await expect.poll(() => where(page)).toBeCloseTo(first + 1, 1);
  });

  test(`${mode.name}: a key held turns one page for each repeat, none skipped`, async ({ page }) => {
    await start(page);
    await mode.open(page);
    await measure(page);
    const first = await where(page);
    await hold(page, 'PageDown', 4);
    await expect.poll(() => where(page)).toBeCloseTo(first + 4, 1);
    await hold(page, mode.keys.back[3], 3);
    await expect.poll(() => where(page)).toBeCloseTo(first + 1, 1);
  });
}

test('Enter turns no page, with no link focused, in a paged book', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await oneColumn(page);
  const first = await place(page);
  await page.keyboard.press('Enter');
  await framesPassed(page);
  expect(await place(page)).toEqual(first);
});
