// The W3C's EPUB 3 test suite (https://github.com/w3c/epub-tests) run once
// against Quire (quire#419, reports/quire.json, reports/quire-w3c-epub-tests.md):
// every test of the suite that Quire fails has a test of its own here, on a
// small book made for it (w3c-books.js), named by the suite's test and its
// level (must, should). They are written from the suite's statements, never
// relaxed to pass: a test here fails until the fix for it is in.

import { test, expect } from './fixtures.js';
import { w3cBooks, W3C_TEXT } from './w3c-books.js';
import {
  start, rawFile, importFiles, importInput, openBook, bookPage, cards, clickControl, dialog, visibleText,
  expectBannerSaysWhatToDo,
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

// ---- Internationalization ----

test('pkg-dir_creator-rtl, pkg-dir_rtl-root-unset, pkg-dir_rtl-root-ltr, pkg-dir_unset-root-rtl (must): a title and a creator whose dir is rtl are shown right to left', async ({ page }) => {
  await start(page);
  await importFiles(page, [rawFile('directed-title.epub', w3cBooks['directed-title'].bytes())], 1);
  const direction = text => cards(page).first().getByText(text).first().evaluate(e => getComputedStyle(e).direction);
  expect(await direction('הרפתקה')).toBe('rtl');
  expect(await direction('דוד')).toBe('rtl');
});

test('pkg-lang_but_not_content (must): a content document with no language is not given the package\'s', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'french-package', 'Package in French');
  const language = await bookPage(page).evaluate(doc => {
    const marked = doc.querySelector('q').closest('[lang]');
    return marked ? marked.getAttribute('lang') : null;
  });
  expect(language, 'the page\'s quotation, in a document that says no language, is under the language of the OPF').not.toBe('fr');
});

test('pkg-dir_but_not_content (must): a content document with no direction is not given the package\'s rtl', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'rtl-package', 'Package in Hebrew');
  expect(await bookPage(page).locator('ul').evaluate(list => getComputedStyle(list).direction)).toBe('ltr');
  expect(await bookPage(page).locator('p').first().evaluate(p => getComputedStyle(p).direction)).toBe('ltr');
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

test('pkg-manifest-unlisted-resource (should): an image the manifest does not list is not shown', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'unlisted-image', 'Image not in the manifest');
  await expect(bookPage(page).getByText('The red image is not in the manifest.')).toBeVisible();
  await page.waitForTimeout(1500);
  expect((await pictures(page)).filter(picture => picture.loaded)).toEqual([]);
});

test('ocf-url_link-path-absolute (must): a path-absolute address in the content is resolved from the container\'s root', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'path-absolute-image', 'Image by an absolute path');
  await expect.poll(async () => (await pictures(page))[0]?.settled).toBe(true);
  expect((await pictures(page))[0].loaded).toBe(true);
});

test('pub-data-urls_browsing-context, pub-data-urls_top-level-content (must): an image given as a data URL is shown in the page', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'data-url-image', 'Image as a data URL');
  await expect.poll(async () => (await pictures(page))[0]?.settled).toBe(true);
  expect((await pictures(page))[0].loaded).toBe(true);
});

test('pub-xml-non-validating_unclosed (must): a content document with an unclosed element is reported as an error', async ({ page }, testInfo) => {
  await start(page);
  await tryW3cBook(page, 'unclosed-tag');
  await expectBannerSaysWhatToDo(page, testInfo);
});

test('pub-xml-names (must): a content document with an invalid element name is reported as an error', async ({ page }, testInfo) => {
  await start(page);
  await tryW3cBook(page, 'double-colon-name');
  await expectBannerSaysWhatToDo(page, testInfo);
});

// ---- Open Container Format: the zip ----

test('ocf-zip-comp (must): an archive with an entry compressed by anything but Deflate is refused', async ({ page }, testInfo) => {
  await start(page);
  await importInput(page).setInputFiles(rawFile('zip-bzip2.epub', w3cBooks['zip-bzip2'].bytes()));
  await expectBannerSaysWhatToDo(page, testInfo);
  await expect(cards(page)).toHaveCount(0);
});

test('ocf-zip-mult (must): an archive split into segments is refused', async ({ page }, testInfo) => {
  await start(page);
  await importInput(page).setInputFiles(rawFile('zip-split.epub', w3cBooks['zip-split'].bytes()));
  await expectBannerSaysWhatToDo(page, testInfo);
  await expect(cards(page)).toHaveCount(0);
});

// ---- Core Media Types, Content Documents ----

test('pub-cmt-mp3, pub-cmt-mp4, pub-cmt-opus (must): an audio element in the page is shown, with its controls', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'audio-element', 'Audio in the page');
  const audio = bookPage(page).locator('audio');
  await expect(audio).toHaveCount(1);
  expect(await audio.getAttribute('controls')).not.toBeNull();
  await expect.poll(() => audio.evaluate(a => a.networkState)).not.toBe(3); // NETWORK_NO_SOURCE
  expect((await audio.boundingBox())?.width).toBeGreaterThan(0);
});

test('cnt-mathml-support (must): a MathML equation is shown as an equation', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'mathml', 'MathML in the page');
  const equation = bookPage(page).locator('math');
  await expect(equation).toHaveCount(1);
  await expect(equation.locator('msup')).toHaveCount(1);
  // the exponent is set above the base: a box of its own, higher than the base's
  const boxes = await equation.evaluate(math => ({
    base: math.querySelector('msup > mi').getBoundingClientRect().bottom,
    exponent: math.querySelector('msup > mn').getBoundingClientRect().bottom,
  }));
  expect(boxes.exponent).toBeLessThan(boxes.base);
});

test('cnt-svg-embedded, cnt-svg-css-inclusion (must): an inline SVG drawing is shown', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'inline-svg', 'SVG in the page');
  const drawn = bookPage(page).locator('svg rect#drawn');
  await expect(drawn).toHaveCount(1);
  expect((await drawn.boundingBox())?.width).toBeGreaterThan(50);
});

test('cnt-svg-support, cnt-svg-css, lay-pp-svg-icb_multi (must): an SVG content document in the spine is shown', async ({ page }) => {
  await start(page);
  await importFiles(page, [rawFile('svg-spine.epub', w3cBooks['svg-spine'].bytes())], 1);
  await openBook(page, 'SVG as a content document');
  const drawn = bookPage(page).locator('svg rect#drawn');
  await expect(drawn).toHaveCount(1);
  expect((await drawn.boundingBox())?.width).toBeGreaterThan(50);
});

// ---- Navigation Documents ----

test('nav-non-text_img, nav-non-text_img_title (should): a navigation link that holds an image is labelled by the image\'s alt text', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'nav-image-label', 'Image in a navigation label');
  await clickControl(page, 'Contents');
  const contents = dialog(page, 'Contents');
  await expect(contents).toBeVisible();
  const rows = await contents.getByRole('tabpanel', { name: 'Contents' }).getByRole('button').allInnerTexts();
  expect(rows.map(row => row.trim())).toEqual(['Start page', 'Description of the Abbey']);
});

test('nav-spine_in-spine-hidden-toc-html (must): a navigation document in the spine is shown without the entries its hidden attribute hides, and the table of contents lists all', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'nav-in-spine-hidden', 'Navigation document in the spine, an entry hidden');
  await expect.poll(() => visibleText(page)).toContain('Contents');
  expect(await bookPage(page).innerText()).toContain('The first link');
  expect(await bookPage(page).innerText(), 'the entry marked hidden is not shown in the page').not.toContain('The second link');
  await clickControl(page, 'Contents');
  const rows = await dialog(page, 'Contents').getByRole('tabpanel', { name: 'Contents' }).getByRole('button').allInnerTexts();
  expect(rows.map(row => row.trim())).toEqual(['The first link', 'The second link']);
});
