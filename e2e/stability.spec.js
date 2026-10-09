// The place is a content node, not a page (#412): whatever changes how
// the chapter is laid out (the theme, the font, the margins, the columns,
// the spacings, the window) leaves the paragraph the reader was at on
// the page shown, in every reading mode, several changes in a row end on
// the same paragraph, and an app killed after each opens at it.

import { test, expect } from './fixtures.js';
import {
  epubFile, importFiles, openBook, toLibrary, reload, bookPage, place, chapters, openReadingSettings, readingSettings, fixedLayoutBook, readFixed, fixedPlace, japaneseChapters,
} from './helpers.js';
import { launch, relaunch, chapterShown, nextChapter } from './relaunch.js';
import { legacyLibrary, store, put, forgetRecords } from './legacy-library.js';

const paged = { title: 'Stable', author: 'Stability', rawChapters: chapters(1, 90) };
const vertical = { title: '縦書き', author: 'Stability', language: 'ja', rtl: true, rawChapters: japaneseChapters(1, 60) };

/** The first words of the first paragraph that begins on the page
    shown (its first line inside it), whichever way its pages go: the one
    the place is kept by */
async function middleParagraph(page) {
  return bookPage(page).evaluate(doc => {
    const c = doc.getBoundingClientRect();
    for (const e of doc.querySelectorAll('p')) {
      const r = e.getClientRects()[0];
      if (r && r.left >= c.left - 2 && r.right <= c.right + 2 && r.top >= c.top - 2 && r.bottom <= c.bottom + 2) return e.textContent.slice(0, 14);
    }
    return null;
  });
}

/** Whether a paragraph beginning with text has a line on the page shown */
function onScreen(page, text) {
  return bookPage(page).evaluate((doc, text) => {
    const c = doc.getBoundingClientRect();
    return [...doc.querySelectorAll('p')].some(e => e.textContent.startsWith(text) &&
      [...e.getClientRects()].some(r => r.right > c.left && r.left < c.right && r.bottom > c.top && r.top < c.bottom));
  }, text);
}

/** Opens the reading settings on a tab, runs change, closes the sheet */
async function change(page, tab, how) {
  await openReadingSettings(page, tab);
  await how(readingSettings(page));
  await page.keyboard.press('Escape');
}

const group = (sheet, name, button) => sheet.getByRole('group', { name }).getByRole('button', { name: button, exact: true }).click();
const row = (sheet, label, button) => sheet.locator('.srow', { hasText: label }).getByRole('button', { name: button, exact: true }).click();
const slider = (sheet, name, value) => sheet.getByRole('slider', { name }).fill(String(value));

const changes = {
  theme: sheet => group(sheet, 'Theme', 'Dark'),
  font: sheet => row(sheet, 'Font', 'Inter'),
  size: sheet => slider(sheet, 'Size', 26),
  lines: sheet => slider(sheet, 'Line spacing', 22),
  paragraphs: sheet => slider(sheet, 'Paragraph spacing', 20),
  margins: sheet => slider(sheet, 'Margins', 4),
  columns: sheet => group(sheet, 'Pages on screen', 'Two'),
};
const tabOf = { theme: 'Look', font: 'Look', size: 'Look', lines: 'Look', paragraphs: 'Look', margins: 'Page', columns: 'Page' };

async function readFar(page, opts) {
  await importFiles(page, [epubFile(opts)], 1);
  await openBook(page, opts.title);
  // right to left (the vertical book) turns forward to the left
  const forward = opts.rtl ? 'ArrowLeft' : 'ArrowRight';
  for (let k = 0; k < 7; k++) {
    const before = await place(page);
    await page.keyboard.press(forward);
    await expect.poll(async () => JSON.stringify(await place(page))).not.toBe(JSON.stringify(before));
  }
}

for (const [name, apply] of Object.entries(changes)) {
  test(`changing the ${name} keeps the paragraph on the page shown`, async ({ page }) => {
    await page.goto('/');
    await readFar(page, paged);
    const top = await middleParagraph(page);
    expect(top).toBeTruthy();
    await change(page, tabOf[name], apply);
    await expect.poll(() => onScreen(page, top)).toBe(true);
  });
}

test('several changes in a row, a rotation among them, end on the same paragraph', async ({ page }) => {
  await page.goto('/');
  await readFar(page, paged);
  const top = await middleParagraph(page);
  const size = page.viewportSize();
  await change(page, 'Look', changes.size);
  await expect.poll(() => onScreen(page, top)).toBe(true);
  await page.setViewportSize({ width: size.height, height: size.width });
  await expect.poll(() => onScreen(page, top)).toBe(true);
  await change(page, 'Look', changes.theme);
  await expect.poll(() => onScreen(page, top)).toBe(true);
  await change(page, 'Look', sheet => slider(sheet, 'Size', 16));
  await page.setViewportSize(size);
  await expect.poll(() => onScreen(page, top)).toBe(true);
});

test('a window swap keeps the paragraph when scrolled, in two columns, and vertically', async ({ page }) => {
  await page.goto('/');
  const size = page.viewportSize();
  // two columns
  await readFar(page, paged);
  await change(page, 'Page', changes.columns);
  let top = await middleParagraph(page);
  await page.setViewportSize({ width: size.height, height: size.width });
  await expect.poll(() => onScreen(page, top)).toBe(true);
  await page.setViewportSize(size);
  await expect.poll(() => onScreen(page, top)).toBe(true);
  // scrolled
  await change(page, 'Page', sheet => group(sheet, 'Layout', 'Scroll'));
  await bookPage(page).evaluate(doc => { doc.scrollTop = doc.scrollHeight / 3; });
  top = await middleParagraph(page);
  await page.setViewportSize({ width: size.height, height: size.width });
  await expect.poll(() => onScreen(page, top)).toBe(true);
  await page.setViewportSize(size);
  await expect.poll(() => onScreen(page, top)).toBe(true);
});

test('a vertical book keeps its paragraph across a window swap', async ({ page }) => {
  await page.goto('/');
  const size = page.viewportSize();
  await readFar(page, vertical);
  const top = await middleParagraph(page);
  await page.setViewportSize({ width: size.height, height: size.width });
  await expect.poll(() => onScreen(page, top)).toBe(true);
  await page.setViewportSize(size);
  await expect.poll(() => onScreen(page, top)).toBe(true);
});

test('a fixed-layout book keeps its page across a window swap', async ({ page }) => {
  await page.goto('/');
  const size = page.viewportSize();
  await readFixed(page, fixedLayoutBook('Fixed Stable', 6));
  await page.keyboard.press('ArrowRight');
  await page.keyboard.press('ArrowRight');
  const before = await fixedPlace(page);
  await page.setViewportSize({ width: size.height, height: size.width });
  await expect.poll(() => fixedPlace(page)).toEqual(before);
  await page.setViewportSize(size);
  await expect.poll(() => fixedPlace(page)).toEqual(before);
});

for (const [name, apply] of Object.entries(changes)) {
  test(`killed after changing the ${name}, the app opens at the same paragraph`, async ({ context, page }) => {
    await launch(context, page);
    await readFar(page, paged);
    await change(page, tabOf[name], apply);
    await expect.poll(() => middleParagraph(page)).toBeTruthy();
    const top = await middleParagraph(page);
    // let the place be kept (it is written as it settles)
    await page.waitForTimeout(1500);
    const next = await relaunch(page, 'killed');
    await expect(bookPage(next)).toBeVisible();
    await expect.poll(() => onScreen(next, top)).toBe(true);
  });
}

test('killed after a window swap, the app opens at the same paragraph', async ({ context, page }) => {
  await launch(context, page);
  const size = page.viewportSize();
  await readFar(page, paged);
  const top = await middleParagraph(page);
  await page.setViewportSize({ width: size.height, height: size.width });
  await expect.poll(() => onScreen(page, top)).toBe(true);
  await page.waitForTimeout(1500);
  const next = await relaunch(page, 'killed');
  await next.setViewportSize({ width: size.height, height: size.width });
  await expect(bookPage(next)).toBeVisible();
  await expect.poll(() => onScreen(next, top)).toBe(true);
});

// After an app update: a book kept by an older Quire's whole-library
// record (QLB1 to QLB6) is converted to records and opens at the chapter,
// page and anchor it was left at
for (let version = 1; version <= 6; version++) {
  for (const by of ['page', 'anchor']) {
    test(`a book converted from QLB${version} opens at its stored ${by}`, async ({ page }) => {
      await page.goto('/');
      const opts = { title: 'Legacy Place', author: 'Stability', rawChapters: chapters(5, 40), toc: [1, 2, 3, 4, 5].map(k => ({ label: `Chapter ${k}`, href: `chapter${k}.xhtml` })) };
      await importFiles(page, [epubFile(opts)], 1);
      await openBook(page, opts.title);
      // on to the fourth chapter, and two pages into it
      while ((await chapterShown(page)) < 4) await nextChapter(page);
      for (let k = 0; k < 2; k++) {
        const before = await place(page);
        await page.keyboard.press('ArrowRight');
        await expect.poll(async () => JSON.stringify(await place(page))).not.toBe(JSON.stringify(before));
      }
      await page.waitForTimeout(1500);
      const at = await place(page);
      const top = await middleParagraph(page);
      const node = await bookPage(page).evaluate((doc, top) => {
        const e = [...doc.querySelectorAll('p')].find(p => p.textContent.startsWith(top));
        return Number((e.firstElementChild || e).id.slice(1));
      }, top);
      await toLibrary(page);
      const key = Object.keys(await store(page)).find(k => k.startsWith('library/book/'));
      const id = key.slice('library/book/'.length);
      const idHigh = parseInt(id.slice(0, 7), 16), idLow = parseInt(id.slice(7), 16);
      const stored = by === 'page'
        ? { chapter: 3, chapters: 5, page: at.p - 1, pages: at.t, anchor: -1 }
        : { chapter: 3, chapters: 5, page: 0, pages: 0, anchor: node };
      await forgetRecords(page);
      await put(page, 'lib', [...legacyLibrary(version, [], [{ idHigh, idLow, title: opts.title, author: opts.author, ...stored }])]);
      await reload(page);
      await openBook(page, opts.title);
      await expect.poll(async () => (await place(page)).ch).toBe(at.ch);
      await expect.poll(() => onScreen(page, top)).toBe(true);
    });
  }
}
