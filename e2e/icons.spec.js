// Every icon is drawn by the icon face (#295). The icons are characters
// of the bundled Material Symbols subset, in the Private Use Area
// (U+E000 to U+F8FF; ui.bats's _glyph): drawn in any other face they
// have no glyph, which Android shows as its "NO GLYPH" box and a desktop
// browser as a blank or a box. A check of the button's name passes all
// the same, so this one looks at what is drawn.
//
// What is checked does not hang on the fonts of the machine the test
// runs on: each icon is drawn on a canvas in its element's own computed
// font, and must come out exactly as the same character drawn in the
// icon face alone, and unlike it drawn in Inter (the app's face, which
// has nothing in the Private Use Area, so whatever the machine falls
// back to draws it). The face's glyph is there (document.fonts.check),
// and the element's font-family starts with the icon face.
//
// It runs on the library (list and grid, its search and menu), the
// reader's bars, its sheets, Settings, search in the book and a
// catalogue, in every project: the narrow one's 320 px and the android
// one's phone among them.

import { test, expect } from './fixtures.js';
import {
  start, epubFile, importFiles, readBook, showChrome, chapters, dialog, menuItem,
  libraryMenu, librarySettings, settingsScreen, settingsButton, bookMenu, clickControl,
  openReadingSettings, toLibrary, topBar, librarySearch, chooseInSortMenu,
} from './helpers.js';

const FACE = 'Material Symbols';

/** Each element whose own text holds a character of the Private Use
    Area, checked as it is drawn now: its name, its characters, whether
    it is shown, and what is wrong with it (nothing, when it is drawn by
    the icon face) */
async function icons(page) {
  return page.evaluate(async face => {
    const privateUse = /[\u{E000}-\u{F8FF}]/u;
    const own = e => [...e.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join('');
    const found = [...document.querySelectorAll('body *')].filter(e => privateUse.test(own(e)));
    const canvas = document.createElement('canvas');
    canvas.width = 96;
    canvas.height = 96;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    /** The pixels of character drawn in font */
    const drawn = (character, font) => {
      context.clearRect(0, 0, canvas.width, canvas.height);
      context.font = font;
      context.fillStyle = '#000';
      context.textBaseline = 'middle';
      context.fillText(character, 16, 48);
      return context.getImageData(0, 0, canvas.width, canvas.height).data;
    };
    const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
    const inked = pixels => pixels.some((v, i) => i % 4 === 3 && v > 0);
    const results = [];
    for (const e of found) {
      const style = getComputedStyle(e);
      const size = style.fontSize;
      const characters = [...own(e)].filter(c => privateUse.test(c));
      const problems = [];
      if (!style.fontFamily.replace(/["']/g, '').startsWith(face)) problems.push(`its font-family is ${style.fontFamily}`);
      for (const c of characters) {
        const code = 'U+' + c.codePointAt(0).toString(16).toUpperCase();
        // the face loaded, with a glyph for it
        await document.fonts.load(`${size} '${face}'`, c);
        if (!document.fonts.check(`${size} '${face}'`, c)) problems.push(`${code}: the icon face is not loaded`);
        const asShown = drawn(c, `${style.fontStyle} ${style.fontWeight} ${size} ${style.fontFamily}`);
        const inFace = drawn(c, `${style.fontStyle} ${style.fontWeight} ${size} '${face}'`);
        const elsewhere = drawn(c, `${style.fontStyle} ${style.fontWeight} ${size} Inter`);
        if (!inked(inFace)) problems.push(`${code}: the icon face draws nothing`);
        if (same(inFace, elsewhere)) problems.push(`${code}: the icon face has no glyph of its own`);
        if (!same(asShown, inFace)) problems.push(`${code}: not drawn by the icon face`);
      }
      results.push({
        name: e.getAttribute('aria-label') || e.id || e.className,
        shown: e.checkVisibility() && e.getClientRects().length > 0,
        problems,
      });
    }
    return results;
  }, FACE);
}

/** Expects every icon on the page drawn by the icon face, and at least
    one shown on screen, naming the screen when one is not */
async function iconsDrawn(page, screen) {
  const found = await icons(page);
  const wrong = found.filter(f => f.problems.length).map(f => `${f.name}${f.shown ? '' : ' (hidden)'}: ${f.problems.join('; ')}`);
  expect(wrong, `icons not drawn by the icon face on ${screen}`).toEqual([]);
  expect(found.filter(f => f.shown).length, `an icon shown on ${screen}`).toBeGreaterThan(0);
  return found;
}

test('every icon of the library, its search, its menu, Settings and a catalogue is drawn by the icon face', async ({ page }) => {
  const host = 'https://catalogue.test';
  await page.route(url => url.hostname !== 'localhost', route => route.abort());
  await page.route(`${host}/**`, route => route.fulfill({
    status: 200, headers: { 'Access-Control-Allow-Origin': '*' }, contentType: 'application/atom+xml',
    body: `<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"><id>urn:icons</id><title>Icons Catalogue</title><updated>2026-10-01T00:00:00Z</updated>
  <entry><title>A Book</title><id>a</id><link rel="http://opds-spec.org/acquisition" href="/a.epub" type="application/epub+zip"/></entry>
</feed>`,
  }));
  await start(page);
  await importFiles(page, [epubFile({ title: 'First', author: 'A' }), epubFile({ title: 'Second', author: 'B' })], 2);
  const list = await iconsDrawn(page, 'the library as a list');
  // each card's Book menu among them
  expect(list.filter(f => f.name === 'Book menu' && f.shown).length).toBe(2);
  await chooseInSortMenu(page, 'Grid');
  const grid = await iconsDrawn(page, 'the library as a grid');
  expect(grid.filter(f => f.name === 'Book menu' && f.shown).length).toBe(2);
  await chooseInSortMenu(page, 'List');
  await librarySearch(page).fill('Fir');
  await expect(page.getByRole('button', { name: 'Clear search' })).toBeVisible();
  await iconsDrawn(page, 'the library searched');
  await page.getByRole('button', { name: 'Clear search' }).click();
  await bookMenu(page, 'First');
  await iconsDrawn(page, 'the book menu');
  await page.keyboard.press('Escape');
  await libraryMenu(page);
  await iconsDrawn(page, 'the library menu');
  await page.keyboard.press('Escape');
  await librarySettings(page);
  await iconsDrawn(page, 'Settings');
  await settingsButton(page, 'Done').click();
  await expect(settingsScreen(page)).toBeHidden();
  // a catalogue browsed: its Back and Close
  await libraryMenu(page);
  await menuItem(page, 'Catalogues').click();
  const catalogues = dialog(page, 'Catalogues');
  await catalogues.getByRole('textbox', { name: 'Catalogue name' }).fill('Icons Catalogue');
  await catalogues.getByRole('textbox', { name: 'Catalogue URL' }).fill(`${host}/root.xml`);
  await catalogues.getByRole('button', { name: 'Add catalogue' }).click();
  await catalogues.getByRole('group', { name: 'Icons Catalogue' }).getByRole('button', { name: 'Icons Catalogue' }).click();
  const browsed = page.getByRole('dialog').filter({ has: page.getByRole('button', { name: 'Close catalogue' }) });
  await expect(browsed).toHaveAccessibleName('Icons Catalogue');
  await iconsDrawn(page, 'a catalogue');
});

test("every icon of the reader's bars, its sheets and search is drawn by the icon face", async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Icons', author: 'L', rawChapters: chapters(3) });
  await showChrome(page);
  const bars = await iconsDrawn(page, "the reader's bars");
  for (const name of ['Back to library', 'Bookmark this page', 'Search in book', 'Previous page', 'Next page', 'Contents', 'Reading settings', 'Annotations']) {
    expect(bars.some(f => f.name === name), `${name} is an icon`).toBe(true);
  }
  // the bookmark's other icon (ui_icon_set)
  await topBar(page).getByRole('button', { name: 'Bookmark this page' }).click();
  await showChrome(page);
  await iconsDrawn(page, 'the reader with the page bookmarked');
  await clickControl(page, 'Contents');
  await expect(dialog(page, 'Contents')).toBeVisible();
  await iconsDrawn(page, 'Contents');
  await page.keyboard.press('Escape');
  await openReadingSettings(page, 'Look');
  await iconsDrawn(page, 'Reading settings');
  await page.keyboard.press('Escape');
  await clickControl(page, 'Annotations');
  await expect(dialog(page, 'Annotations')).toBeVisible();
  await iconsDrawn(page, 'Annotations');
  await page.keyboard.press('Escape');
  await showChrome(page);
  await topBar(page).getByRole('button', { name: 'Search in book' }).click();
  await expect(dialog(page, 'Search in book')).toBeVisible();
  await iconsDrawn(page, 'Search in book');
  await page.keyboard.press('Escape');
  await toLibrary(page);
});
