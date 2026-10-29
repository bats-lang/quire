// A book's own font, plain or masked by the obfuscations the EPUB OCF
// requires a reading system to undo (section 4.1.2; quire#410): IDPF's
// (the key the SHA-1 of the package's unique identifier) and Adobe's
// (the key the identifier's UUID). The books are in font-books.js; their
// font has one glyph no system font has, U+E000, 1.7 em wide, so the
// book's face is told from a fallback by measuring that one character.
// A font in an algorithm Quire has no client for, one the archive lacks,
// one that is noise and one shorter than the masked bytes degrade where
// they are: the text is read in the reader's own face, and the book
// raises no banner.

import { test, expect } from './fixtures.js';
import { start, importFiles, epubFile, openBook, openSettings, bookPage, reload, fontsReady } from './helpers.js';
import { fontBooks } from './font-books.js';

const MARKER_WIDTHS_EM = 1.7;

/** The width of the marker character, and the font size it is set in */
const marker = page => bookPage(page).locator('p').first().evaluate(paragraph => {
  const range = document.createRange();
  range.selectNodeContents(paragraph);
  return { width: range.getBoundingClientRect().width, size: parseFloat(getComputedStyle(paragraph).fontSize) };
});

/** Whether the marker is set in the book's face: 1.7 em wide */
async function inBookFace(page) {
  const { width, size } = await marker(page);
  return Math.abs(width - MARKER_WIDTHS_EM * size) < 1;
}

const bookFont = page => page.getByRole('button', { name: 'Book', exact: true });

async function chooseBookFont(page) {
  await openSettings(page);
  await bookFont(page).click();
  await page.keyboard.press('Escape');
}

/** The faces of the page named QuireBook, by their status */
const faces = page => page.evaluate(() => [...document.fonts].filter(face => face.family.replace(/"/g, '') === 'QuireBook').map(face => face.status));

async function openFontBook(page, key) {
  await importFiles(page, [epubFile(fontBooks[key].opts)], 1);
  await openBook(page, fontBooks[key].opts.title);
  await expect(bookPage(page).locator('p').first()).toBeVisible();
}

for (const key of ['plain', 'idpf', 'idpfSpaced', 'adobe']) {
  test(`a font ${key === 'plain' ? 'that is not masked' : `masked by ${key.startsWith('idpf') ? "IDPF's" : "Adobe's"} obfuscation${key === 'idpfSpaced' ? ', its identifier written with white space,' : ''}`} is the book's face when the reader chooses Book`, async ({ page }) => {
    const errors = await start(page);
    await openFontBook(page, key);
    await chooseBookFont(page);
    // the glyph only the font has is drawn in it, 1.7 em wide, and the face is loaded
    await expect.poll(() => inBookFace(page)).toBe(true);
    await expect.poll(() => faces(page)).toEqual(['loaded']);
    expect(errors).toEqual([]);
  });
}

test('a masked font is unmasked again when the book is opened from storage', async ({ page }) => {
  const errors = await start(page);
  await openFontBook(page, 'idpf');
  await chooseBookFont(page);
  await expect.poll(() => inBookFace(page)).toBe(true);
  // the page comes back to the book, whose file is read again from the store
  await reload(page);
  await expect(bookPage(page).locator('p').first()).toBeVisible();
  await expect.poll(() => inBookFace(page)).toBe(true);
  await expect.poll(() => faces(page)).toEqual(['loaded']);
  expect(errors).toEqual([]);
});

for (const key of ['plain', 'idpf', 'adobe']) {
  test(`a ${key} font is not used while the reader has not chosen Book`, async ({ page }) => {
    const errors = await start(page);
    await openFontBook(page, key);
    await expect.poll(async () => (await marker(page)).width).toBeGreaterThan(0);
    expect(await inBookFace(page)).toBe(false);
    expect(errors).toEqual([]);
  });
}

/** The marker is set in a fallback, the book is read and nothing is raised for it: no banner */
async function degrades(page, key) {
  await openFontBook(page, key);
  await chooseBookFont(page);
  await expect(bookPage(page).getByText('Plain words follow the marker.')).toBeVisible();
  await expect(page.locator('#error-banner')).toBeHidden();
  // the page's fonts have finished loading, and the face did not arrive
  await fontsReady(page);
  expect(await inBookFace(page)).toBe(false);
  expect(await faces(page)).not.toContain('loaded');
  await expect(page.locator('#error-banner')).toBeHidden();
}

for (const [key, why] of [
  ['unknownAlgorithm', 'in an algorithm nobody knows (DRM on the font)'],
  ['aesFont', 'in AES'],
  ['adobeNoUuid', 'masked by Adobe\'s, its identifier no UUID'],
  ['missing', 'that the archive lacks'],
  ['corrupt', 'that is noise'],
  ['short', 'shorter than the bytes the mask covers'],
]) {
  test(`a font ${why} degrades where it is: the text is read in the reader's own face, no banner for the book`, async ({ page }) => {
    await start(page);
    await degrades(page, key);
  });
}
