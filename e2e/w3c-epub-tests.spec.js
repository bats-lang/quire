// The W3C's EPUB 3 test suite (https://github.com/w3c/epub-tests) run once
// against Quire (quire#419, reports/quire.json, reports/quire-w3c-epub-tests.md):
// every test of the suite that Quire fails has a test of its own here, on a
// small book made for it (w3c-books.js), named by the suite's test and its
// level (must, should). They are written from the suite's statements, never
// relaxed to pass; a failure's test is added with its fix (the report says
// which failures are next).

import { test, expect } from './fixtures.js';
import { w3cBooks, W3C_TEXT } from './w3c-books.js';
import {
  start, rawFile, importFiles, importInput, openBook, bookPage, cards, visibleText, expectBannerSaysWhatToDo,
} from './helpers.js';

/** Imports the book of that name from w3c-books.js (what makes it the
    library's one more card) and opens it by its title */
async function readW3cBook(page, name, title) {
  const before = await cards(page).count();
  await importFiles(page, [rawFile(`${name}.epub`, w3cBooks[name].bytes())], before + 1);
  await openBook(page, title);
}

/** Imports the book, and goes as far into it as the reader lets: the
    book's card is opened when there is one */
async function tryW3cBook(page, name) {
  await importInput(page).setInputFiles(rawFile(`${name}.epub`, w3cBooks[name].bytes()));
  await page.waitForTimeout(2000);
  if (await cards(page).count() > 0) await cards(page).first().click();
  await page.waitForTimeout(2000);
}

/** The images of the page shown: each is loaded (a picture), or not */
const pictures = page => bookPage(page).locator('img').evaluateAll(images => images.map(i => ({
  settled: i.complete, loaded: i.complete && i.naturalWidth > 0,
})));

/** The page has no crash: a page that dies in the reader's own code is a
    test failure of its own */
function watchCrash(page) {
  const crashed = { value: false };
  page.on('crash', () => { crashed.value = true; });
  return crashed;
}

// ---- Package Documents ----

test('pkg-title-order (must): the book is titled by the first dc:title', async ({ page }) => {
  await start(page);
  await importFiles(page, [rawFile('two-titles.epub', w3cBooks['two-titles'].bytes())], 1);
  const text = await cards(page).first().innerText();
  expect(text).toContain('First title in the package');
  expect(text).not.toContain('Third title in the package');
});

test('pkg-creator-order (must): the first dc:creator is the author shown, never one after it', async ({ page }) => {
  await start(page);
  await importFiles(page, [rawFile('two-creators.epub', w3cBooks['two-creators'].bytes())], 1);
  const text = await cards(page).first().innerText();
  expect(text).toContain('First Creator');
  expect(text).not.toContain('Third Creator');
});

// ---- Publication Resources, Manifest Fallbacks: the item a reader does not show ----

test('pub-foreign_json-spine (must): a JSON spine item is replaced by its manifest fallback', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'json-spine', 'JSON in the spine');
  await expect.poll(() => visibleText(page)).toContain(W3C_TEXT.FALLBACK_TEXT);
  expect(await visibleText(page)).not.toContain('The JSON text');
});

test('pub-foreign_xml-spine, pub-foreign_xml-suffix-spine (must): an XML spine item is replaced by its manifest fallback', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'xml-spine', 'XML in the spine');
  await expect.poll(() => visibleText(page)).toContain(W3C_TEXT.FALLBACK_TEXT);
  expect(await visibleText(page)).not.toContain('The XML text');
});

test('pub-foreign_xml-suffix-spine (must): a spine item of an XML type with a +xml suffix is replaced by its manifest fallback', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'xml-suffix-spine', 'XML suffix in the spine');
  await expect.poll(() => visibleText(page)).toContain(W3C_TEXT.FALLBACK_TEXT);
  expect(await visibleText(page)).not.toContain('The XML suffix text');
});

test('lay-pp-images-in-spine, lay-pp-images-mixed, lay-pp-spine-overrides_image-spine-pp, lay-pp-spine-overrides_image-spine-reflow, lay-roll-images-in-spine, lay-roll-images-mixed (must): an image in the spine is replaced by its fallback, and is never read as text', async ({ page }) => {
  const crashed = watchCrash(page);
  await start(page);
  await readW3cBook(page, 'image-spine', 'Image in the spine');
  await expect.poll(() => visibleText(page)).toContain(W3C_TEXT.FALLBACK_TEXT);
  expect(crashed.value, 'the page died reading a 3 MB PNG as XHTML').toBe(false);
});

test('scr-support-fallback (must): a scripted spine item is replaced by its fallback where scripts are not run', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'scripted-spine', 'Scripted page with a fallback');
  await expect.poll(() => visibleText(page)).toContain(W3C_TEXT.FALLBACK_TEXT);
  expect(await visibleText(page)).not.toContain('The scripted page');
});

test('pub-foreign_bad-fallback (must): an item that cannot be shown, with a fallback that cannot either, is never shown as text', async ({ page }) => {
  const crashed = watchCrash(page);
  await start(page);
  await importInput(page).setInputFiles(rawFile('unsupported-fallback.epub', w3cBooks['unsupported-fallback'].bytes()));
  await page.waitForTimeout(2000);
  if (await cards(page).count() > 0) {
    await cards(page).first().click();
    await page.waitForTimeout(2000);
    // the book may refuse to open (the banner says so) or go on to the page after the item
    if (await bookPage(page).isVisible()) expect(await bookPage(page).innerText()).not.toContain('BINARYMARK');
  }
  expect(crashed.value).toBe(false);
});

test('pub-foreign_image (must): an image of a type the reader does not show is replaced by its manifest fallback', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'foreign-image', 'Photoshop image with a fallback');
  await expect.poll(async () => (await pictures(page))[0]?.settled).toBe(true);
  expect((await pictures(page))[0].loaded).toBe(true);
});

// ---- Internationalization ----

/** The direction the first card's text holds is drawn in */
const cardDirection = (page, text) => cards(page).first().getByText(text).first().evaluate(e => getComputedStyle(e).direction);

test('pkg-dir_creator-rtl, pkg-dir_rtl-root-unset (must): a title and a creator whose dir is rtl are shown right to left', async ({ page }) => {
  await start(page);
  await importFiles(page, [rawFile('directed-title.epub', w3cBooks['directed-title'].bytes())], 1);
  expect(await cardDirection(page, 'הרפתקה')).toBe('rtl');
  expect(await cardDirection(page, 'דוד')).toBe('rtl');
});

test('pkg-dir_unset-root-rtl (must): a title and a creator with no dir take the package\'s rtl', async ({ page }) => {
  await start(page);
  await importFiles(page, [rawFile('root-directed-title.epub', w3cBooks['root-directed-title'].bytes())], 1);
  expect(await cardDirection(page, 'הרפתקה')).toBe('rtl');
  expect(await cardDirection(page, 'דוד')).toBe('rtl');
});

test('pkg-dir_rtl-root-ltr (must): a dir of its own outranks the package\'s', async ({ page }) => {
  await start(page);
  await importFiles(page, [rawFile('own-direction-over-root.epub', w3cBooks['own-direction-over-root'].bytes())], 1);
  expect(await cardDirection(page, 'הרפתקה')).toBe('ltr');
  expect(await cardDirection(page, 'דוד')).toBe('ltr');
});

// ---- Publication Resources: XML that is not well formed ----

test('pub-xml-non-validating_unclosed (must): a content document with an unclosed element is reported as an error', async ({ page }, testInfo) => {
  await start(page);
  await tryW3cBook(page, 'unclosed-tag');
  await expectBannerSaysWhatToDo(page, testInfo);
  await expect(page.getByRole('alert')).toContainText('could not be read');
});

test('pub-xml-names (must): a content document with an invalid element name is reported as an error', async ({ page }, testInfo) => {
  await start(page);
  await tryW3cBook(page, 'double-colon-name');
  await expectBannerSaysWhatToDo(page, testInfo);
});

test('well formed markup that looks odd is not refused: comments, CDATA, empty elements, a ">" in an attribute, a processing instruction', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'odd-markup', 'Odd but well formed markup');
  await expect.poll(() => visibleText(page)).toContain('shown.');
});

// ---- Open Container Format: the zip ----

test('ocf-zip-comp (must): an archive with an entry compressed by anything but Deflate is refused', async ({ page }, testInfo) => {
  await start(page);
  await importInput(page).setInputFiles(rawFile('zip-bzip2.epub', w3cBooks['zip-bzip2'].bytes()));
  await expectBannerSaysWhatToDo(page, testInfo);
  await expect(page.getByRole('alert')).toContainText('Deflate');
  await expect(cards(page)).toHaveCount(0);
});

test('ocf-zip-mult (must): an archive split into segments is refused', async ({ page }, testInfo) => {
  await start(page);
  await importInput(page).setInputFiles(rawFile('zip-split.epub', w3cBooks['zip-split'].bytes()));
  await expectBannerSaysWhatToDo(page, testInfo);
  await expect(page.getByRole('alert')).toContainText('split');
  await expect(cards(page)).toHaveCount(0);
});
