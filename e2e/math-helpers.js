// Shared steps of the math specs (#408): the books of math-books.js read,
// the reading size and theme set, and equations measured on the page as
// they are drawn (the pixels of a screenshot, not only the boxes).

import { expect } from '@playwright/test';
import { createEpub } from './create-epub.js';
import { mathBooks } from './math-books.js';
import {
  importFiles, openBook, bookPage, rawFile, cards, openReadingSettings, readingSettings, place, placeChanged,
  bareReader,
} from './helpers.js';

export const MATHML_NAMESPACE = 'http://www.w3.org/1998/Math/MathML';

/** Imports the math book named name and opens it */
export async function readMathBook(page, name) {
  const book = mathBooks[name];
  const before = await cards(page).count();
  // a page turn is instant: nothing is laid over the page while it is measured and drawn
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await importFiles(page, [rawFile(`${name}.epub`, createEpub({ storeChapters: true, ...book.opts }))], before + 1);
  await openBook(page, book.opts.title);
  // the page keeps no id of the book's: a block is found by the label its text begins with
  await page.evaluate(() => {
    const named = {
      'display-quadratic': doc => doc.querySelector('math[display=block]'),
      'display-explicit-inline': doc => window.found(doc, 'display-inline').querySelector('math'),
      'wide-equation': doc => doc.querySelector('math'),
      'hebrew-math': doc => window.found(doc, 'hebrew-inline').querySelector('math'),
      'hebrew-display': doc => doc.querySelectorAll('math[display=block]')[0],
      'hebrew-rtl': doc => doc.querySelectorAll('math[display=block]')[1],
    };
    window.found = (doc, name) => named[name] ? named[name](doc)
      : [...doc.querySelectorAll('p, h1')].find(e => e.textContent.startsWith(name + ' '));
  });
}

/** The Size slider of the reading settings, which opens on Look */
const sizeSlider = page => readingSettings(page).getByRole('slider', { name: 'Size' });

/** Sets the reading size (px) and waits until the page has it */
export async function setSize(page, px) {
  await openReadingSettings(page, 'Look');
  await sizeSlider(page).fill(String(px));
  await expect.poll(() => bookPage(page).evaluate(e => getComputedStyle(e).fontSize)).toBe(`${px}px`);
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
}

/** The range of the Size slider: the least and the most size (px) the reader offers */
export async function sizeRange(page) {
  await openReadingSettings(page, 'Look');
  const range = await sizeSlider(page).evaluate(e => ({ min: +e.min, max: +e.max, value: +e.value }));
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
  return range;
}

/** Chooses a theme (Light, Dark, Sepia, Grey, Night) in the reading settings and waits until the page is in it */
export async function chooseTheme(page, name) {
  await openReadingSettings(page, 'Look');
  await readingSettings(page).getByRole('group', { name: 'Theme', exact: true }).getByRole('button', { name, exact: true }).click();
  await expect(readingSettings(page).getByRole('button', { name, exact: true })).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
}

/** The picture of a region of the window (rect in CSS px, viewport coordinates), as pixels:
    { width, height, scale, at(x, y) -> [r, g, b, a] } where x and y are in CSS px of the region */
async function pixelsOf(page, rect) {
  const clip = {
    x: Math.max(0, Math.floor(rect.x)), y: Math.max(0, Math.floor(rect.y)),
    width: Math.max(1, Math.ceil(rect.width)), height: Math.max(1, Math.ceil(rect.height)),
  };
  const png = await page.screenshot({ clip });
  return { clip, base64: png.toString('base64') };
}

/** The ink in a region of the window: the box of the pixels that differ from the region's ground
    (its most common colour) by more than 48 in some channel, in viewport CSS px, and the pixel
    that differs most. null for a region with no ink */
export async function inkIn(page, rect, threshold = 48) {
  // reader acts: the bars and the hint lie over the page until taken away
  await bareReader(page);
  const { clip, base64 } = await pixelsOf(page, rect);
  const found = await page.evaluate(async ({ base64, clip, threshold }) => {
    const image = new Image();
    image.src = 'data:image/png;base64,' + base64;
    await image.decode();
    const canvas = document.createElement('canvas');
    canvas.width = image.width;
    canvas.height = image.height;
    const context = canvas.getContext('2d');
    context.drawImage(image, 0, 0);
    const { data, width, height } = context.getImageData(0, 0, image.width, image.height);
    const scale = width / clip.width;
    const counts = new Map();
    for (let i = 0; i < data.length; i += 4) {
      const key = (data[i] << 16) | (data[i + 1] << 8) | data[i + 2];
      counts.set(key, (counts.get(key) || 0) + 1);
    }
    let ground = 0, most = 0;
    for (const [key, n] of counts) if (n > most) { most = n; ground = key; }
    const background = [(ground >> 16) & 255, (ground >> 8) & 255, ground & 255];
    let left = Infinity, right = -Infinity, top = Infinity, bottom = -Infinity, strongest = null, strength = 0;
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const i = 4 * (y * width + x);
        const away = Math.max(Math.abs(data[i] - background[0]), Math.abs(data[i + 1] - background[1]), Math.abs(data[i + 2] - background[2]));
        if (away <= threshold) continue;
        left = Math.min(left, x); right = Math.max(right, x + 1); top = Math.min(top, y); bottom = Math.max(bottom, y + 1);
        if (away > strength) { strength = away; strongest = [data[i], data[i + 1], data[i + 2]]; }
      }
    }
    if (strongest === null) return null;
    return {
      left: clip.x + left / scale, right: clip.x + right / scale, top: clip.y + top / scale, bottom: clip.y + bottom / scale,
      strongest, background,
    };
  }, { base64, clip, threshold });
  return found;
}

/** The locator of the paragraph that begins with the label (the page keeps no id of the book's) */
export const block = (page, label) => bookPage(page).locator('p', { hasText: new RegExp('^' + label + ' ') });

/** Turns pages until the element the page finds by name (window.found) starts on the page shown */
export async function turnTo(page, name) {
  for (let turns = 0; turns < 60; turns++) {
    const where = await bookPage(page).evaluate((doc, name) => {
      const r = window.found(doc, name).getBoundingClientRect();
      const view = doc.getBoundingClientRect();
      return r.left >= view.right - 1 ? 1 : r.left < view.left - 1 ? -1 : 0;
    }, name);
    if (where === 0) return;
    const before = await place(page);
    await page.keyboard.press(where > 0 ? 'ArrowRight' : 'ArrowLeft');
    await placeChanged(page, before);
  }
  throw new Error(`no page shows the start of ${name}`);
}
