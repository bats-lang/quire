// Real-world containers (#433): the archives and container.xml files that
// tools write and e2e/create-epub.js does not. Each book is made by
// container-books.js (create-epub.js's book written again by zip-writer.js
// with the quirk in it) and checked by epubcheck.spec.js.
//
// Decided (issue 433) from the specifications and what readers do:
// * ZIP: a reader finds an entry by the central directory and its data by
//   the local header's own name and extra lengths (APPNOTE 4.3.7, 4.4.11:
//   the central directory is authoritative for sizes and names; data
//   descriptors (bit 3) carry sizes the local header lacks), so descriptors,
//   extra fields, a comment and a local header that differs all read.
// * ZIP64: EPUB 3.3 (OCF 4.3) says a container MAY use the ZIP64
//   extensions, so a small archive in ZIP64 form is a legal book and opens.
// * mimetype: EPUB 3.3 says it MUST be first, stored and with no extra
//   field, and epubcheck reports each (PKG-005, 006, 007). A reading system
//   need not be a checker: Calibre, Thorium and Apple Books open such files
//   (the issue says so, and no complaint of a refusal was found), and the
//   book is intact whatever its mimetype entry; Quire reads the book by its
//   container.xml and opens them with no banner, as it does a missing one.
// * A CRC that is not the data's: ZIP says it is the data's check, and a
//   reader that does not check shows bytes that may be damaged; the chapter is
//   reported as one that could not be read (notice_say_part), the others read.
// * A duplicate entry name: readers differ (Python's zipfile and Java's
//   ZipFile take the last, libzip the first, unzip extracts both so the last
//   overwrites), EPUB 3.3 is silent and epubcheck calls it an error
//   (OPF-060). Quire keeps the first, the entry its index lists first, and
//   opens the book either way.
// * Names with a leading "./" or with backslashes (a tool for Windows) are
//   read as the names they stand for (the central directory's names are
//   tried as written, then with "./" before them, then with backslashes
//   for slashes), as Calibre and Thorium open such books; directory
//   entries are ignored (no file is named by one).
// * Two rootfiles: EPUB 3.3 (OCF 4.2.6.3.1.2) says a container may hold
//   several renditions and does not define how to choose; Quire reads the
//   first, the default rendition as Readium and Thorium take it, and makes
//   one book of it.
// * A rootfile full-path is a URL from the container's root: an encoded
//   space or a leading slash is found; a path the archive lacks is refused
//   with the words ("has no package document").
// * META-INF/metadata.xml, manifest.xml and signatures.xml are ignored;
//   rights.xml is Adobe's DRM and is refused by name (quire#427,
//   drm.spec.js).
// * An OPF with a BOM, a DOCTYPE, a stylesheet instruction, a prefix on
//   every element or CRLF line ends is XML, and read as XML.

import { test, expect } from './fixtures.js';
import {
  start, rawFile, importInput, importFiles, cards, card, pageShown, showChrome, control, dialog, visibleText,
  chapterTitle, expectBannerSaysWhatToDo, toLibrary,
} from './helpers.js';
import { containerBooks } from './container-books.js';

const contents = page => dialog(page, 'Contents');
const rows = page => contents(page).getByRole('tabpanel', { name: 'Contents' }).getByRole('button');

/** Imports the book named name and opens it */
async function openContainer(page, name) {
  const entry = containerBooks[name];
  const count = await cards(page).count();
  await importFiles(page, [rawFile(`${name}.epub`, entry.bytes())], count + 1);
  await card(page, entry.bytes.title).click();
  await pageShown(page);
}

/** Goes to the k-th row of the contents and returns the text then shown */
async function readRow(page, k) {
  await showChrome(page);
  await control(page, 'Contents').click();
  await expect(contents(page)).toBeVisible();
  await rows(page).nth(k).click();
  await expect(contents(page)).toBeHidden();
  await expect.poll(() => visibleText(page)).toContain(`Chapter ${k + 1}`);
  return visibleText(page);
}

/** Every chapter of a three chapter book reads */
async function expectThreeChapters(page) {
  for (const k of [0, 1, 2]) await readRow(page, k);
}

const opensAndReads = {
  descriptors: 'entries with data descriptors (bit 3)',
  descriptorsBare: 'entries with data descriptors that have no signature',
  extras: 'an archive comment and the timestamp, unix and ZIP64 extra fields',
  localNameDiffers: 'a local header whose name is not the central directory\'s',
  localExtraDiffers: 'a local header whose extra field is longer than the central directory\'s',
  mimetypeDeflated: 'a mimetype entry that is deflated',
  mimetypeNotFirst: 'a mimetype entry that is not the first',
  mimetypeExtra: 'a mimetype entry with an extra field',
  mimetypeMissing: 'no mimetype entry',
  directories: 'directory entries among the files',
  dotSlashNames: 'names that begin with "./"',
  backslashNames: 'backslashes in the names',
  metaInfFiles: 'metadata.xml, manifest.xml and signatures.xml in META-INF',
  opfBom: 'a package document with a byte order mark',
  opfDoctype: 'a package document with a DOCTYPE and a stylesheet instruction',
  opfPrefixed: 'a package document whose every element has a prefix',
  opfCrlf: 'a package document with CRLF line ends',
  rootfileEncoded: 'a rootfile full-path with an encoded space',
  rootfileSlash: 'a rootfile full-path with a leading slash',
};

for (const [name, what] of Object.entries(opensAndReads)) {
  test(`${what}: the book opens with no banner and every chapter reads`, async ({ page }) => {
    const errors = await start(page);
    await openContainer(page, name);
    await expect(page.getByRole('alert')).toBeHidden();
    await expectThreeChapters(page);
    await expect(page.getByRole('alert')).toBeHidden();
    expect(errors).toEqual([]);
  });
}

test('names flagged UTF-8 and names not flagged but in UTF-8 are both found by the package that names them', async ({ page }) => {
  const errors = await start(page);
  await openContainer(page, 'utf8Names');
  await expect(chapterTitle(page)).toHaveText('Flagged');
  await showChrome(page);
  await control(page, 'Contents').click();
  await rows(page).nth(1).click();
  await expect.poll(() => visibleText(page)).toContain('Unflagged name 0.');
  await expect(page.getByRole('alert')).toBeHidden();
  expect(errors).toEqual([]);
});

test('a small archive in ZIP64 form opens (EPUB 3.3 allows ZIP64) and its chapters read', async ({ page }) => {
  const errors = await start(page);
  await openContainer(page, 'zip64');
  await expect(page.getByRole('alert')).toBeHidden();
  await expectThreeChapters(page);
  expect(errors).toEqual([]);
});

test('a chapter whose CRC is not its data\'s is reported as unreadable, and the others read', async ({ page }) => {
  const errors = await start(page);
  await openContainer(page, 'wrongCrc');
  await readRow(page, 0);
  await showChrome(page);
  await control(page, 'Contents').click();
  await rows(page).nth(1).click();
  const banner = page.getByRole('alert');
  await expect(banner).toContainText(/Chapter 2 of this book could not be read/);
  // the banner stays until it is dismissed, and on a phone it lies over the
  // rows of the contents: the reader dismisses it before choosing the next chapter
  await banner.getByRole('button', { name: 'Dismiss' }).click();
  await expect(banner).toBeHidden();
  await readRow(page, 2);
  expect(errors).toEqual([]);
});

test('a duplicate entry name: the first entry is the one read, and the book opens', async ({ page }) => {
  const errors = await start(page);
  await openContainer(page, 'duplicateName');
  await expect(page.getByRole('alert')).toBeHidden();
  const text = await readRow(page, 0);
  expect(text).toContain('Chapter 1');
  expect(text).not.toContain('Second Copy');
  await readRow(page, 1);
  expect(errors).toEqual([]);
});

test('two rootfiles are one book: the first rendition, not a second book and not an error', async ({ page }) => {
  const errors = await start(page);
  await openContainer(page, 'twoRootfiles');
  await expect(page.getByRole('alert')).toBeHidden();
  await showChrome(page);
  await control(page, 'Contents').click();
  await expect(rows(page)).toHaveText(['Chapter 1', 'Chapter 2', 'Chapter 3']);
  expect(await visibleText(page)).not.toContain('Other');
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await expect(cards(page)).toHaveCount(1);
  expect(errors).toEqual([]);
});

test('a rootfile full-path that names no file is refused as having no package, with the words', async ({ page }, testInfo) => {
  const errors = await start(page);
  await importInput(page).setInputFiles(rawFile('missing.epub', containerBooks.rootfileMissing.bytes()));
  const banner = page.getByRole('alert');
  await expect(banner).toContainText('has no package document (.opf), so it could not be imported. Choose another file');
  await expectBannerSaysWhatToDo(page, testInfo);
  await expect(cards(page)).toHaveCount(0);
  expect(errors).toEqual([]);
});
