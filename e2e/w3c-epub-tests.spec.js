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
  start, rawFile, importFiles, importInput, openBook, bookPage, cards, visibleText, expectBannerSaysWhatToDo, clickControl, dialog, openReadingSettings, readingSettings, card,
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

/** As readW3cBook, for a book that may be scrolled (the page indicator then says a percentage, not pages) */
async function readW3cBookScrolled(page, name, title) {
  const before = await cards(page).count();
  await importFiles(page, [rawFile(`${name}.epub`, w3cBooks[name].bytes())], before + 1);
  await card(page, title).click();
  await expect(bookPage(page)).toBeVisible();
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

// ---- Publication Resources: addresses ----

test('ocf-url_link-path-absolute (must): a path-absolute address in the content is resolved from the container\'s root', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'path-absolute-image', 'Image by an absolute path');
  await expect.poll(async () => (await pictures(page))[0]?.settled).toBe(true);
  expect((await pictures(page))[0].loaded).toBe(true);
});

test('pub-data-urls_browsing-context (must): an image given as a base64 data URL is shown in the page', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'data-url-image', 'Image as a data URL');
  await expect.poll(async () => (await pictures(page))[0]?.settled).toBe(true);
  expect((await pictures(page))[0].loaded).toBe(true);
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

// ---- Links out of the book, scrolled flow, roll layout, fonts ----

test('pub-external-links (should): a link to the web asks the reader first, and opens in a new tab on their word', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'external-links', 'Links out of the book');
  await bookPage(page).getByRole('link', { name: 'link to the web' }).click();
  const asked = dialog(page, 'Footnote');
  await expect(asked).toContainText('It goes to https://example.com/page.');
  const open = asked.getByRole('link', { name: 'Open link' });
  await expect(open).toHaveAttribute('href', 'https://example.com/page');
  await expect(open).toHaveAttribute('target', '_blank');
  // nothing opened before the word was given: the page is the reader's and no tab came
  expect(page.context().pages()).toHaveLength(1);
});

test('pub-external-links_consent (should): a mail link asks the reader first', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'external-links', 'Links out of the book');
  await bookPage(page).getByRole('link', { name: 'link to mail' }).click();
  const asked = dialog(page, 'Footnote');
  await expect(asked).toContainText('It goes to mailto:reader@example.com.');
  await expect(asked.getByRole('link', { name: 'Open link' })).toHaveAttribute('href', 'mailto:reader@example.com');
});

/** Whether the page scrolls down (a chapter in a column flow does not) */
const scrollsDown = page => bookPage(page).evaluate(e => getComputedStyle(e).overflowY !== 'hidden' && e.scrollHeight > e.clientHeight + 10);

test('lay-pkg-flow-scrolled-doc, lay-pkg-flow-scrolled-continuous (should): a book that asks for scrolled flow is scrolled, until the reader chooses Pages', async ({ page }) => {
  await start(page);
  await readW3cBookScrolled(page, 'flow-scrolled', 'Scrolled flow');
  await expect.poll(() => scrollsDown(page)).toBe(true);
  // the reader's own choice outranks the book's
  await openReadingSettings(page, 'Page');
  await readingSettings(page).getByRole('button', { name: 'Pages', exact: true }).click();
  await expect.poll(() => scrollsDown(page)).toBe(false);
});

test('lay-pkg-flow-paginated: a book that says nothing of its flow is in pages', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'flow-paginated', 'Paginated flow');
  expect(await scrollsDown(page)).toBe(false);
});

test('lay-roll-embedded-images, lay-roll-embedded-images-svg (must): a roll layout is read scrolled down, its pictures one after another', async ({ page }) => {
  await start(page);
  await readW3cBookScrolled(page, 'roll-layout', 'A roll of pictures');
  await expect.poll(() => scrollsDown(page)).toBe(true);
});

test('cnt-css-fonts_ot, cnt-css-fonts_tt, cnt-css-fonts_woff, cnt-css-fonts_woff2 (must): a font the package carries is the reader\'s Book font', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'book-font', 'A book with a font');
  await openReadingSettings(page, 'Look');
  await readingSettings(page).getByRole('button', { name: 'Book', exact: true }).click();
  await expect.poll(() => page.evaluate(() => document.fonts.check('16px QuireBook'))).toBe(true);
  expect(await bookPage(page).locator('p').first().evaluate(e => getComputedStyle(e).fontFamily)).toContain('QuireBook');
});

test('mol-tts_single, mol-tts_multi (should): a SMIL with no audio is read by speech synthesis', async ({ page }) => {
  await page.addInitScript(() => {
    window.spoken = [];
    window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
    const voices = [{ name: 'Reader', lang: 'en-US', voiceURI: 'reader-en', default: true }];
    const synth = {
      current: null,
      getVoices: () => voices,
      speak(u) { window.spoken.push(u.text); this.current = u; },
      cancel() { this.current = null; },
      addEventListener() {},
    };
    Object.defineProperty(window, 'speechSynthesis', { value: synth });
  });
  await start(page);
  await readW3cBook(page, 'smil-no-audio', 'A SMIL with no audio');
  // the narration has no clip to play: its controls are not offered, reading aloud by speech is
  await expect(page.getByRole('button', { name: 'Next phrase' })).toBeHidden();
  const readAloud = page.getByRole('button', { name: 'Read aloud', exact: true });
  await expect(readAloud).toBeVisible();
  await readAloud.click();
  await expect.poll(() => page.evaluate(() => window.spoken.join(' '))).toContain('read by speech synthesis');
});

test('pss-support_ignore-title (must): a title marked as a footnote is no note: its link opens no popup', async ({ page }) => {
  await start(page);
  await readW3cBook(page, 'title-as-note', 'A title marked as a note');
  await bookPage(page).getByRole('link', { name: 'this link' }).click();
  await page.waitForTimeout(1500);
  await expect(dialog(page, 'Footnote')).toBeHidden();
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

// ---- SVG ----

/** The red of the picture drawn in the page's first image: the colour of its centre pixel, once it is loaded */
async function pictureColour(page) {
  const image = bookPage(page).locator('img').first();
  await expect(image).toBeVisible();
  await expect.poll(() => image.evaluate(i => i.complete && i.naturalWidth > 0)).toBe(true);
  return image.evaluate(i => {
    const canvas = document.createElement('canvas');
    canvas.width = 20; canvas.height = 20;
    const context = canvas.getContext('2d');
    context.drawImage(i, 0, 0, 20, 20);
    return Array.from(context.getImageData(10, 10, 1, 1).data);
  });
}

test('cnt-svg-embedded, cnt-svg-support (must): an svg in a page and an svg as a page are drawn', async ({ page }) => {
  await start(page);
  await readW3cBookScrolled(page, 'svg-inline', 'Inline SVG');
  const [red, green, blue] = await pictureColour(page);
  expect([red, green, blue]).toEqual([255, 0, 0]);
});

test('cnt-svg-support (must): an svg content document is drawn, its own style applied', async ({ page }) => {
  await start(page);
  await readW3cBookScrolled(page, 'svg-document', 'SVG as a content document');
  const [red, green, blue] = await pictureColour(page);
  expect([red, green, blue]).toEqual([255, 0, 0]);
});

test('cnt-svg-css (must): the svg is a picture of its own, its style neither reaching the page nor reached by it', async ({ page }) => {
  await start(page);
  await readW3cBookScrolled(page, 'svg-inline', 'Inline SVG');
  await pictureColour(page);
  // the page holds no svg element and no style of the book's: nothing the svg says reaches the text
  await expect(bookPage(page).locator('svg')).toHaveCount(0);
  await expect(bookPage(page).locator('style')).toHaveCount(0);
  const colour = await bookPage(page).locator('p').first().evaluate(p => getComputedStyle(p).color);
  expect(colour).not.toBe('rgb(255, 0, 0)');
  // and it is a picture: an image whose source is a blob of its own
  const source = await bookPage(page).locator('img').first().getAttribute('src');
  expect(source).toMatch(/^blob:/);
});

// ---- MathML ----

test('cnt-mathml-support (must): a math element is drawn as an equation: MathML elements, a fraction set one number over the other', async ({ page }) => {
  await start(page);
  await readW3cBookScrolled(page, 'mathml', 'MathML in a page');
  const equation = await bookPage(page).evaluate(doc => {
    const math = doc.querySelector('math');
    const parts = math ? [...math.querySelectorAll('*')] : [];
    const fraction = math?.querySelector('mfrac');
    const [top, bottom] = fraction ? [...fraction.children].map(e => e.getBoundingClientRect().top) : [0, 0];
    return {
      namespace: math?.namespaceURI,
      names: parts.map(e => e.localName),
      spaces: parts.every(e => e.namespaceURI === 'http://www.w3.org/1998/Math/MathML'),
      stacked: bottom - top,
      variant: math?.querySelector('mi')?.getAttribute('mathvariant'),
      text: math?.textContent.replace(/\s+/g, ''),
      block: math ? getComputedStyle(math).display : '',
    };
  });
  expect(equation.namespace).toBe('http://www.w3.org/1998/Math/MathML');
  expect(equation.spaces).toBe(true);
  expect(equation.names).toEqual(expect.arrayContaining(['mi', 'mo', 'mfrac', 'mn', 'msqrt']));
  // the numerator is above the denominator: an equation, not a line of words
  expect(equation.stacked).toBeGreaterThan(4);
  expect(equation.variant).toBe('bold');
  expect(equation.text).toContain('x=12+y');
  // maction (it can run something) is refused; its content is shown in its place
  expect(equation.names).not.toContain('maction');
  expect(equation.block).toContain('math');
});
