// Quitting Quire and opening it again changes nothing (#302): in each
// state a reader leaves it in, the app is captured whole (relaunch.js:
// the screen's pixels, what is open, the book and its place, the
// library's view, every stored record), closed and opened again in the
// same browser (its storage kept), captured again once every launch step
// (a sync included) has ended, and the two captures must be the same.

import { test, expect, onAndroid } from './fixtures.js';
import { launch, chapterShown, nextChapter, previousChapter, pagesOn, unchanged, capture, relaunch, sameState } from './relaunch.js';
import {
  epubFile, importFiles, openBook, toLibrary, librarySearch, cards, chapters, japaneseChapters, dialog, openReadingSettings, readingSettings, selectText, selectionButton, fixedLayoutBook, readFixed, indicator, bookPage, chooseInSortMenu, sortMenuChecked,
} from './helpers.js';

const book = { title: 'Kept Book', author: 'Relaunch Tests', chapters: 4, rawChapters: chapters(4, 40) };

// ---- the library ----

test('the library, in a view, a filter, a sort and a search, is as it was', async ({ context, page }) => {
  await launch(context, page);
  await importFiles(page, [
    epubFile({ title: 'Alpha', author: 'Zed', rawChapters: chapters(2, 20) }),
    epubFile({ title: 'Mid', author: 'Young', rawChapters: chapters(2, 20) }),
    epubFile({ title: 'Zulu', author: 'Ann', rawChapters: chapters(2, 20) }),
  ], 3);
  await openBook(page, 'Mid');
  await pagesOn(page, 2);
  await toLibrary(page);
  page = await unchanged(page);
  // a grid, by title
  await chooseInSortMenu(page, 'Grid');
  await chooseInSortMenu(page, 'Title');
  expect(await sortMenuChecked(page)).toEqual(['Title', 'Grid']);
  page = await unchanged(page);
  // the books being read, by author
  await page.getByRole('group', { name: 'Show' }).getByRole('button', { name: 'Reading' }).click();
  await chooseInSortMenu(page, 'Author');
  expect(await sortMenuChecked(page)).toEqual(['Author', 'Grid']);
  page = await unchanged(page, 'killed');
  // all of them, searched
  await page.getByRole('group', { name: 'Show' }).getByRole('button', { name: 'All' }).click();
  await librarySearch(page).fill('lu');
  await expect(cards(page)).toHaveCount(1);
  await unchanged(page);
});

// ---- reading, in each layout ----

/** The book opened, read to the middle of its second chapter */
async function midChapter(page) {
  await importFiles(page, [epubFile(book)], 1);
  await openBook(page, 'Kept Book');
  await nextChapter(page);
  await pagesOn(page, 2);
}

/** A choice of the reading settings' Page tab */
async function pageChoice(page, group, name) {
  await openReadingSettings(page, 'Page');
  await readingSettings(page).getByRole('group', { name: group }).getByRole('button', { name, exact: true }).click();
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
}

for (const how of ['quit', 'killed']) {
  test(`paged, in the middle of a chapter, the book opens where it was (${how})`, async ({ context, page }) => {
    await launch(context, page);
    await midChapter(page);
    await unchanged(page, how);
  });
}

test('scrolled, in the middle of a chapter, the book opens where it was', async ({ context, page }) => {
  await launch(context, page);
  await importFiles(page, [epubFile(book)], 1);
  await openBook(page, 'Kept Book');
  await pageChoice(page, 'Layout', 'Scroll');
  await nextChapter(page);
  await page.keyboard.press('PageDown');
  await page.keyboard.press('PageDown');
  await unchanged(page);
});

test('in two columns, in the middle of a chapter, the book opens where it was', async ({ context, page }) => {
  await launch(context, page);
  await importFiles(page, [epubFile(book)], 1);
  await openBook(page, 'Kept Book');
  await pageChoice(page, 'Pages on screen', 'Two');
  await nextChapter(page);
  await pagesOn(page, 2);
  await unchanged(page);
});

test('set vertically, in the middle of a chapter, the book opens where it was', async ({ context, page }) => {
  await launch(context, page);
  await importFiles(page, [epubFile({ title: '縦の頁', author: 'Relaunch Tests', language: 'ja', rtl: true, rawChapters: japaneseChapters(2, 40) })], 1);
  await openBook(page, '縦の頁');
  for (let k = 0; k < 3; k++) {
    const before = await indicator(page).textContent();
    await page.keyboard.press('ArrowLeft');
    await expect(indicator(page)).not.toHaveText(before);
  }
  await unchanged(page);
});

test('a fixed-layout book opens on the page it was on, alone or in a spread', async ({ context, page }) => {
  await launch(context, page);
  await readFixed(page, fixedLayoutBook('Fixed Pages', 6, { spread: 'auto' }));
  await page.keyboard.press('ArrowRight');
  await page.keyboard.press('ArrowRight');
  page = await unchanged(page);
  // in spreads, whatever the window (the bars brought up by their key: a
  // tap on a fixed page is a tap on its picture)
  await page.keyboard.press('t');
  await openReadingSettings(page, 'Page');
  await readingSettings(page).getByRole('group', { name: 'Pages on screen' }).getByRole('button', { name: 'Two', exact: true }).click();
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
  await unchanged(page);
});

// ---- full screen (#313) ----

// In the Android app, full screen (both system bars hidden) is kept: the
// app opens again with the bars hidden and the switch on, set as it
// starts (the bars hidden, never shown first), or with them shown and
// the switch off when it was turned off. A browser enters full screen
// only at a click, so it keeps none (settings.spec.js)
for (const kept of ['on', 'off']) {
  test(`in the Android app, with full screen turned ${kept}, the app opens again so`, async ({ context, page }, testInfo) => {
    test.skip(!onAndroid(testInfo), 'full screen is kept by the Android app only: a browser enters it only at a click (#313)');
    await launch(context, page);
    await midChapter(page);
    const full = page => readingSettings(page).getByRole('button', { name: 'Full screen', exact: true });
    await openReadingSettings(page, 'Page');
    await full(page).click();
    await expect(full(page)).toHaveAttribute('aria-pressed', 'true');
    if (kept === 'off') {
      await full(page).click();
      await expect(full(page)).toHaveAttribute('aria-pressed', 'false');
    }
    await page.keyboard.press('Escape');
    await expect(readingSettings(page)).toBeHidden();
    for (const how of ['quit', 'killed']) {
      // the setting is kept; the system's bars are the reader's to hide
      // (quire#348), so the app opens again with them shown (the library,
      // or the reader with its own bars up) and hides them when it is read
      // with its own bars away
      page = await relaunch(page, how);
      await expect.poll(() => page.evaluate(() => window.__android.hidden)).toEqual({ status: false, navigation: false });
      await openReadingSettings(page, 'Page');
      await expect(full(page)).toHaveAttribute('aria-pressed', String(kept === 'on'));
      await page.keyboard.press('Escape');
      await expect(readingSettings(page)).toBeHidden();
      await page.keyboard.press('t');
      const hidden = kept === 'on';
      await expect.poll(() => page.evaluate(() => window.__android.hidden)).toEqual({ status: hidden, navigation: hidden });
      await page.keyboard.press('t');
    }
  });
}

// ---- after going back in a book ----

test('after going back in a book, it opens where the reader went back to, and offers nothing', async ({ context, page }) => {
  await launch(context, page);
  await importFiles(page, [epubFile(book)], 1);
  await openBook(page, 'Kept Book');
  await nextChapter(page);
  await nextChapter(page);
  await previousChapter(page);
  await previousChapter(page);
  expect(await chapterShown(page)).toBe(1);
  page = await unchanged(page);
  expect(await chapterShown(page)).toBe(1);
  // from the library too
  await toLibrary(page);
  page = await unchanged(page);
  await openBook(page, 'Kept Book');
  expect(await chapterShown(page)).toBe(1);
});

// ---- settings, annotations and a search ----

test('with settings changed, annotations made and a search done, all is as it was', async ({ context, page }) => {
  await launch(context, page);
  await importFiles(page, [epubFile(book)], 1);
  await openBook(page, 'Kept Book');
  await openReadingSettings(page, 'Look');
  await readingSettings(page).getByRole('group', { name: 'Theme' }).getByRole('button', { name: 'Sepia', exact: true }).click();
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
  await selectText(page, 0, 8);
  await selectionButton(page, 'Highlight').click();
  await page.evaluate(() => getSelection().removeAllRanges());
  // a search, gone to and closed
  await page.keyboard.press('/');
  const search = dialog(page, 'Search in book');
  await expect(search).toBeVisible();
  await page.keyboard.type('Para');
  await search.getByRole('region', { name: 'Results' }).getByRole('button').nth(3).click();
  const bar = page.getByRole('toolbar', { name: 'Search results' });
  await expect(bar).toBeVisible();
  await bar.getByRole('button', { name: 'Close search' }).click();
  await expect(bar).toBeHidden();
  await unchanged(page);
});

// ---- the reading face, still loading as the app opens again ----

/** How many pixels of the page's text are inked, on the screen as it
    is: those of the first paragraph's box that the screen shows and no
    bar covers, darker than any colour the page has but its text's */
async function inked(page) {
  const region = await page.evaluate(() => {
    const box = document.querySelector('#page p').getBoundingClientRect();
    let top = Math.max(box.top, 0);
    let bottom = Math.min(box.bottom, innerHeight);
    for (const bar of document.querySelectorAll('#reader-top-bar, #reader-bottom-bar')) {
      const r = bar.getBoundingClientRect();
      if (!r.height) continue;
      if (r.top <= top && r.bottom > top) top = r.bottom;
      if (r.top < bottom && r.bottom >= bottom) bottom = r.top;
    }
    const left = Math.max(box.left, 0);
    return { x: left, y: top, width: Math.min(box.right, innerWidth) - left, height: bottom - top };
  });
  expect(region.width * region.height, 'some of the page\'s text on the screen').toBeGreaterThan(0);
  // the screen as it is, taken by DevTools (Playwright's own screenshot
  // waits for the page's fonts to load first), whole (a clip would set
  // the screen's metrics for the moment), the region cut from it
  const session = await page.context().newCDPSession(page);
  const { data: shot } = await session.send('Page.captureScreenshot', { format: 'png' });
  await session.detach();
  return page.evaluate(async ([base64, { x, y, width, height }]) => {
    const bitmap = await createImageBitmap(await (await fetch(`data:image/png;base64,${base64}`)).blob());
    const scale = bitmap.width / innerWidth;
    const canvas = new OffscreenCanvas(Math.round(width * scale), Math.round(height * scale));
    const context = canvas.getContext('2d');
    context.drawImage(bitmap, -Math.round(x * scale), -Math.round(y * scale));
    const { data } = context.getImageData(0, 0, canvas.width, canvas.height);
    let dark = 0;
    for (let k = 0; k < data.length; k += 4) if (data[k] < 96 && data[k + 1] < 96 && data[k + 2] < 96) dark++;
    return dark;
  }, [shot, region]);
}

// A page laid out and painted in a fallback face, then again in its own
// as the face came in, is not what the reader left, and the renderer
// could leave a few pixels of the fallback's glyphs at the column's
// edges where the face's text did not repaint them (#328). The page's
// text is shown only in the face it is set in: until the face has come
// in (held back here), none of it is painted
test('opened again while its reading face is still loading, the page shows no text in another face, and then all is as it was', async ({ context, page }) => {
  await launch(context, page);
  await importFiles(page, [epubFile(book)], 1);
  await openBook(page, 'Kept Book');
  const before = await capture(page);
  let release;
  const held = new Promise(resolve => { release = resolve; });
  let asked;
  const requested = new Promise(resolve => { asked = resolve; });
  await context.route('**/literata-latin.woff2', async route => { asked(); await held; await route.continue(); });
  const next = await relaunch(page);
  await requested;
  await expect(bookPage(next).locator('p').first()).toBeAttached();
  const ink = await inked(next);
  release();
  expect(ink, 'the page\'s text painted while its face loads').toBe(0);
  await expect.poll(() => next.evaluate(() => document.fonts.check('18px Literata'))).toBe(true);
  // and painted once its face is in
  await expect.poll(() => inked(next)).toBeGreaterThan(0);
  const after = await capture(next);
  await sameState(next, before, after);
});
