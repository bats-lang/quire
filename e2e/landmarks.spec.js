// Where a book opens the first time (#409): the body matter its
// landmarks name (EPUB 3.3 5.4.1.2: bodymatter, "start reading"), or its
// guide's text reference (EPUB 2), else its first spine item. A book
// that has been read opens at its kept place. The books are in
// landmark-books.js, checked by epubcheck.spec.js.

import { test, expect } from './fixtures.js';
import {
  start, readBook, importFiles, epubFile, openBook, chapterTitle, visibleText, showChrome, control, dialog, toLibrary,
} from './helpers.js';
import { landmarkBooks } from './landmark-books.js';

const contents = page => dialog(page, 'Contents');

for (const [name, text, title] of [
  ['startsAtBody', 'Body begins here', 'Body begins here'],
  ['guideText', 'Body begins here', 'Body begins here'],
]) {
  test(`${name}: a book never read opens where its ${name === 'guideText' ? 'guide says the text' : 'landmarks say the body matter'} starts`, async ({ page }) => {
    const errors = await start(page);
    await readBook(page, landmarkBooks[name].opts);
    await expect(chapterTitle(page)).toHaveText(title);
    await expect.poll(() => visibleText(page)).toContain(text);
    expect(await visibleText(page)).not.toContain('Cover page');
    await expect(page.getByRole('alert')).toBeHidden();
    expect(errors).toEqual([]);
  });
}

// landmarks that name no start, or a start the book does not have: the
// book opens at its first spine item, saying nothing
for (const name of ['noBodyMatter', 'startWithoutHref', 'startMissing', 'startOutside']) {
  test(`${name}: opens at the first chapter, as a book with no start does`, async ({ page }) => {
    const errors = await start(page);
    await readBook(page, landmarkBooks[name].opts);
    await expect(chapterTitle(page)).toHaveText('Cover');
    await expect.poll(() => visibleText(page)).toContain('Cover page');
    await expect(page.getByRole('alert')).toBeHidden();
    expect(errors).toEqual([]);
  });
}

test('a book that has been read opens at its kept place, not at the start again', async ({ page }) => {
  const errors = await start(page);
  const opts = landmarkBooks.startsAtBody.opts;
  await readBook(page, opts);
  await expect(chapterTitle(page)).toHaveText('Body begins here');
  // read on to the second chapter
  await showChrome(page);
  await control(page, 'Contents').click();
  await contents(page).getByRole('tabpanel', { name: 'Contents' }).getByRole('button', { name: 'Second chapter' }).click();
  await expect(chapterTitle(page)).toHaveText('Second chapter');
  await toLibrary(page);
  await openBook(page, opts.title);
  await expect(chapterTitle(page)).toHaveText('Second chapter');
  // and back to the cover: the reader's own move there is kept as well
  await showChrome(page);
  await control(page, 'Contents').click();
  await contents(page).getByRole('tabpanel', { name: 'Contents' }).getByRole('button', { name: 'Cover' }).click();
  await expect(chapterTitle(page)).toHaveText('Cover');
  await toLibrary(page);
  await openBook(page, opts.title);
  await expect(chapterTitle(page)).toHaveText('Cover');
  expect(errors).toEqual([]);
});

// Decided from what other readers do (issue 409): Apple Books uses the
// bodymatter landmark to open the book, and lists no landmarks; Calibre's
// viewer shows none; only Thorium has a Landmarks list. Contents lists
// the book's table of contents, as publishers put the contents page,
// index and illustrations list in it too.
test('the contents list the table of contents, not the landmarks', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, landmarkBooks.startsAtBody.opts);
  await showChrome(page);
  await control(page, 'Contents').click();
  const rows = await contents(page).getByRole('tabpanel', { name: 'Contents' }).getByRole('button').allInnerTexts();
  expect(rows.map(r => r.trim())).toEqual(['Cover', 'Contents', 'Copyright', 'Body begins here', 'Second chapter']);
  expect(errors).toEqual([]);
});
