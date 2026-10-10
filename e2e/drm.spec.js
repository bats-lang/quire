// A book that declares its protection is refused at import, with the
// scheme named and the next step, and is not added to the library
// (quire#427): Adobe ADEPT, Readium LCP, Apple FairPlay, Kobo, and an
// encryption.xml that names an algorithm nobody knows. What is not
// protection is not refused: fonts that are only obfuscated, and a
// book that is damaged and declares nothing, which stays damaged.
// The books are made by e2e/drm-books.js, and checked by epubcheck in
// e2e/epubcheck.spec.js.

import { test, expect } from './fixtures.js';
import {
  expectBannerSaysWhatToDo, start, importInput, importFiles, epubFile, cards, openBook, bookPage, reload,
} from './helpers.js';
import { drmBooks } from './drm-books.js';

const alert = page => page.getByRole('alert');

/** What the banner says of each refused book: the scheme it names */
const refused = {
  adept: /is protected by Adobe DRM \(ADEPT\), which Quire cannot open, so it was not imported/,
  adeptEncryptionOnly: /is protected by Adobe DRM \(ADEPT\), which Quire cannot open, so it was not imported/,
  lcp: /is protected by Readium LCP, which Quire cannot open, so it was not imported/,
  lcpLicenseOnly: /is protected by Readium LCP, which Quire cannot open, so it was not imported/,
  fairPlay: /is protected by Apple FairPlay DRM, which Quire cannot open, so it was not imported/,
  kobo: /is protected by Kobo DRM, which Quire cannot open, so it was not imported/,
  unknownAlgorithm: /is encrypted by a DRM that Quire does not know and cannot open, so it was not imported/,
};
const nextStep = /Quire opens books without DRM only: read this one in the app it came from, or get a copy without DRM\./;

for (const [name, says] of Object.entries(refused)) {
  test(`a ${name} book is refused, named, with the next step, and not added to the library`, async ({ page }, testInfo) => {
    const errors = await start(page);
    await importInput(page).setInputFiles(epubFile(drmBooks[name].opts));
    await expect(alert(page)).toContainText(says);
    await expect(alert(page)).toContainText(nextStep);
    // it is not blamed on damage, and it says so in the app's own words
    await expect(alert(page)).not.toContainText(/damaged|could not be read/);
    await expectBannerSaysWhatToDo(page, testInfo);
    await expect(cards(page)).toHaveCount(0);
    // nothing of it was kept
    await reload(page);
    await expect(cards(page)).toHaveCount(0);
    expect(errors).toEqual([]);
  });
}

test('a book whose encryption.xml names only obfuscated fonts is not refused, and opens', async ({ page }) => {
  const errors = await start(page);
  await importFiles(page, [epubFile(drmBooks.obfuscatedFonts.opts)], 1);
  await expect(alert(page)).toBeHidden();
  await openBook(page, 'Obfuscated Fonts Book');
  await expect(bookPage(page)).toContainText('Chapter 1');
  expect(errors).toEqual([]);
});

test('a damaged book with no encryption.xml is reported as damaged, never as DRM', async ({ page }, testInfo) => {
  const errors = await start(page);
  await importInput(page).setInputFiles(epubFile(drmBooks.damagedPackage.opts));
  await expect(alert(page)).toContainText('has a damaged package document (.opf), so it could not be imported');
  await expect(alert(page)).not.toContainText(/DRM|protected|encrypted/i);
  await expectBannerSaysWhatToDo(page, testInfo);
  await expect(cards(page)).toHaveCount(0);
  expect(errors).toEqual([]);
});

test('a protected book beside a plain one: the plain one is added, the protected one is not', async ({ page }) => {
  const errors = await start(page);
  await importFiles(page, [
    epubFile(drmBooks.lcp.opts),
    epubFile({ title: 'Plain Book', author: 'Plain Author' }),
  ], 1);
  await expect(cards(page).filter({ hasText: 'Plain Book' })).toHaveCount(1);
  expect(errors).toEqual([]);
});
