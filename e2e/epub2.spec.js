// True EPUB 2 packages (#416): OPF 2.0, XHTML 1.1, an NCX and no nav
// document. The books are in epub2-books.js (create-epub.js's `epub2`),
// checked by epubcheck.spec.js; `guide` references are played by
// landmarks.spec.js, and a 3.0 package with only an NCX (what `ncx: true`
// makes) by navigation.spec.js.

import { test, expect } from './fixtures.js';
import {
  start, readBook, importFiles, epubFile, openBook, card, chapterTitle, visibleText, showChrome, control, dialog, bookPage,
  expectBarFollows,
} from './helpers.js';
import { epub2Books } from './epub2-books.js';

const contents = page => dialog(page, 'Contents');
const rows = async page => {
  await showChrome(page);
  await control(page, 'Contents').click();
  const texts = await contents(page).getByRole('tabpanel', { name: 'Contents' }).getByRole('button').allInnerTexts();
  return texts.map(t => t.trim());
};

test('an EPUB 2 package opens: its title, author, chapters and contents', async ({ page }) => {
  const errors = await start(page);
  const opts = epub2Books.plain.opts;
  await importFiles(page, [epubFile(opts)], 1);
  await expect(card(page, 'Plain EPUB 2')).toContainText('Ann Author');
  await openBook(page, 'Plain EPUB 2');
  await expect(chapterTitle(page)).toHaveText('First part');
  await expect.poll(() => visibleText(page)).toContain('Part 1 text');
  expect(await rows(page)).toEqual(['First part', 'Second part', 'Deep in two', 'Third part']);
  await contents(page).getByRole('tabpanel', { name: 'Contents' }).getByRole('button', { name: 'Third part' }).click();
  await expect(chapterTitle(page)).toHaveText('Third part');
  await expect(page.getByRole('alert')).toBeHidden();
  expect(errors).toEqual([]);
});

test('an author is shown as the book writes it, not as its file-as sort name', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile(epub2Books.plain.opts)], 1);
  await expect(card(page, 'Plain EPUB 2')).toContainText('Ann Author');
  await expect(card(page, 'Plain EPUB 2')).not.toContainText('Author, Ann');
});

test('the cover an EPUB 2 book names with <meta name="cover"> is shown in the library', async ({ page }) => {
  const errors = await start(page);
  await importFiles(page, [epubFile(epub2Books.cover.opts)], 1);
  const cover = card(page, 'EPUB 2 with a cover').locator('img');
  await expect(cover).toHaveCount(1);
  await expect.poll(() => cover.evaluate(i => i.complete && i.naturalWidth > 0)).toBe(true);
  expect(errors).toEqual([]);
});

test('a nested NCX with play orders out of document order lists in document order', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, epub2Books.ncxOutOfOrder.opts);
  expect(await rows(page)).toEqual(['Third part', 'First part', 'Inside the first', 'Second part']);
  expect(errors).toEqual([]);
});

test('a navPoint with no content, and one with an empty label, leave the rest of the contents', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, epub2Books.ncxNoContent.opts);
  expect(await rows(page)).toEqual(['First part', 'Goes nowhere', 'Third part']);
  // the entry that goes nowhere does nothing; the others still go
  const list = contents(page).getByRole('tabpanel', { name: 'Contents' });
  await list.getByRole('button', { name: 'Goes nowhere' }).click();
  await expect(contents(page)).toBeVisible();
  await list.getByRole('button', { name: 'Third part' }).click();
  await expect(chapterTitle(page)).toHaveText('Third part');
  await page.keyboard.press('Escape');
  expect(errors).toEqual([]);
});

test('a navPoint with an empty label is listed as Untitled', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, epub2Books.ncxEmptyLabel.opts);
  expect(await rows(page)).toEqual(['First part', 'Untitled', 'Third part']);
  expect(errors).toEqual([]);
});

test("XHTML 1.1's named entities are the characters they name", async ({ page }) => {
  const errors = await start(page);
  await readBook(page, epub2Books.entities.opts);
  await expect.poll(async () => (await visibleText(page)).replace(/ /g, ' '))
    .toContain('Before after — dash “quoted” © 2026 été …');
  expect(errors).toEqual([]);
});

test('a package that says 2.0 and has a nav document opens, with its contents', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, epub2Books.declaredTwoWithNav.opts);
  expect(await rows(page)).toEqual(['First part', 'Second part', 'Deep in two', 'Third part']);
  expect(errors).toEqual([]);
});

// Decided as the Hebrew test in reader.spec.js has it (Readium reads a
// right-to-left language's book right to left when its spine says
// nothing): the same for an EPUB 2 package.
test('an EPUB 2 Hebrew book whose spine does not say reads right to left', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, epub2Books.hebrew.opts);
  expect(await bookPage(page).evaluate(e => getComputedStyle(e).direction)).toBe('rtl');
  await expectBarFollows(page, true);
  expect(errors).toEqual([]);
});

// Decided (issue 416): OPS 2.0.1 permits DTBook and OEB 1 documents, a
// reader needs XHTML only, and the book names an XHTML fallback for them;
// a search found no documentation of Thorium or Calibre rendering either.
// Quire shows the item's text (its elements as blocks and inline text, as
// for any XML) rather than refuse the book, which costs nothing and loses
// no words.
for (const [name, text] of [['dtbook', 'DTBook paragraph'], ['oeb1', 'OEB1 paragraph']]) {
  test(`an EPUB 2 ${name} spine item is read through: its text is shown, nothing is raised`, async ({ page }) => {
    const errors = await start(page);
    await readBook(page, epub2Books[name].opts);
    for (let k = 0; k < 8 && !(await visibleText(page)).includes(text); k++) {
      await page.keyboard.press('ArrowRight');
      await page.waitForTimeout(300);
    }
    expect(await visibleText(page)).toContain(text);
    await expect(page.getByRole('alert')).toBeHidden();
    expect(errors).toEqual([]);
  });
}
