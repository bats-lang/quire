// Note popups beyond the basics of reader.spec.js (#414): links in a
// note, nested notes, notes marked other ways, long and hidden notes, and
// links that look like notes but are not marked. The book is in
// note-books.js, checked by epubcheck.spec.js.
//
// Decided (issue 414) from what readers do. The EPUB spec defines
// "footnote" and "noteref" and nothing of a popup (EDRLab). Apple's asset
// guide has a noteref open the aside it names as a popup; links inside
// that popup are the long-standing trouble (iBooks' popover collapses on
// a tap on one: Stack Overflow 12952352) and Apple advises a note as a
// single paragraph. Quire's popup is the note's text, with no links in it
// (so none can only close it); the note's own links work where the note
// is, which Go to note reaches with the way back. Nested notes and
// backlinks are followed there too. Calibre's maintainer says heuristic
// detection of unmarked footnotes works in most readers, but Apple Books
// and Kobo ask for markup, and a heuristic opens a popup for a "see 3"
// cross-reference that the reader meant to follow: Quire detects none, an
// unmarked link is a link.

import { test, expect } from './fixtures.js';
import { start, readBook, bookPage, dialog, visibleText, place, jumpBack, chapterTitle } from './helpers.js';
import { noteBooks } from './note-books.js';

const note = page => dialog(page, 'Footnote');
const link = (page, name) => bookPage(page).getByRole('link', { name, exact: true });
const close = page => note(page).getByRole('button', { name: 'Close', exact: true });
const goTo = page => note(page).getByRole('button', { name: 'Go to note' });

test('a note opens as its text, with no links in it; Go to note reaches the note, where its links work and its backlink returns', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, noteBooks.notes.opts);
  const at = await place(page);
  await link(page, '1').click();
  await expect(note(page)).toBeVisible();
  await expect(note(page)).toContainText('See the far place, the web and ↩.');
  await expect(note(page).getByRole('link')).toHaveCount(0);
  expect(await place(page)).toEqual(at);
  await goTo(page).click();
  await expect(note(page)).toBeHidden();
  await expect(jumpBack(page)).toBeVisible();
  // the note's own links, where it is: inside the book it jumps, outside it opens outside
  const out = bookPage(page).getByRole('link', { name: 'the web' });
  await expect(out).toHaveAttribute('target', '_blank');
  await expect(out).toHaveAttribute('rel', /noopener/);
  await bookPage(page).getByRole('link', { name: 'the far place' }).click();
  await expect.poll(() => visibleText(page)).toContain('Far target');
  await jumpBack(page).click();
  // the backlink goes to the reference, the way back is there
  await expect.poll(() => visibleText(page)).toContain('See the far place');
  await bookPage(page).getByRole('link', { name: '↩', exact: true }).click();
  await expect.poll(() => visibleText(page)).toContain('One1, two2');
  await expect(jumpBack(page)).toBeVisible();
  expect(errors).toEqual([]);
});

test('a note is reached and closed from the keyboard, and its buttons are in the Tab order', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, noteBooks.notes.opts);
  await link(page, '1').focus();
  await page.keyboard.press('Enter');
  await expect(note(page)).toBeVisible();
  // focus starts on Close; Tab reaches Go to note, and round again
  await expect(close(page)).toBeFocused();
  await page.keyboard.press('Tab');
  await expect(goTo(page)).toBeFocused();
  await page.keyboard.press('Shift+Tab');
  await expect(close(page)).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(note(page)).toBeHidden();
  await expect(link(page, '1')).toBeFocused();
  // Go to note by key
  await link(page, '1').focus();
  await page.keyboard.press('Enter');
  await goTo(page).focus();
  await page.keyboard.press('Enter');
  await expect(note(page)).toBeHidden();
  await expect(jumpBack(page)).toBeVisible();
  expect(errors).toEqual([]);
});

test('a note that cites another is shown as its text; the second note opens from the first note\'s place, with the way back', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, noteBooks.notes.opts);
  await link(page, '2').click();
  // an inline reference keeps its words together
  await expect(note(page)).toContainText('Second cites3.');
  await goTo(page).click();
  await expect(note(page)).toBeHidden();
  await expect(jumpBack(page)).toBeVisible();
  // the note in its place: its noteref opens the third note over the page
  await bookPage(page).getByRole('link', { name: '3', exact: true }).nth(1).click();
  await expect(note(page)).toContainText('Third, a div.');
  await close(page).click();
  // and the way back is still to where the first note's reference was
  await jumpBack(page).click();
  await expect.poll(() => visibleText(page)).toContain('One1, two2');
  expect(errors).toEqual([]);
});

test('an unmarked numeric link is an ordinary link, followed, and the popup does not open', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, noteBooks.notes.opts);
  await link(page, '3').first().click();
  await expect(note(page)).toBeHidden();
  await expect.poll(() => visibleText(page)).toContain('A short paragraph a numeric link goes to.');
  await expect(jumpBack(page)).toBeVisible();
  expect(errors).toEqual([]);
});

for (const [n, text] of [
  ['4', 'Hidden note text.'],
  ['5', 'Long note paragraph 0'],
  ['6', 'Sixth, an endnote in a list.'],
  ['7', 'Seventh, a rear note.'],
]) {
  test(`note ${n} (${{ 4: 'hidden', 5: 'long, role doc-footnote', 6: 'a list item, doc-endnote', 7: 'rearnote' }[n]}) opens like an aside one`, async ({ page }) => {
    const errors = await start(page);
    await readBook(page, noteBooks.notes.opts);
    await link(page, n).click();
    await expect(note(page)).toBeVisible();
    await expect(note(page)).toContainText(text);
    // within the window, its Close and Go to note whole
    const size = page.viewportSize();
    for (const part of [note(page), close(page), goTo(page)]) {
      const box = await part.boundingBox();
      expect(box.y).toBeGreaterThanOrEqual(0);
      expect(box.y + box.height).toBeLessThanOrEqual(size.height + 1);
      expect(box.x).toBeGreaterThanOrEqual(0);
      expect(box.x + box.width).toBeLessThanOrEqual(size.width + 1);
    }
    await close(page).click();
    await expect(note(page)).toBeHidden();
    expect(errors).toEqual([]);
  });
}

test('a note longer than the popup holds ends in an ellipsis, and Go to note has all of it', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, noteBooks.notes.opts);
  await link(page, '5').click();
  const text = (await note(page).locator('#footnote-text').textContent()).trim();
  expect(text.endsWith('…')).toBe(true);
  expect(text).not.toMatch(/�/);
  await goTo(page).click();
  await expect.poll(() => visibleText(page)).toContain('Long note paragraph');
  expect(errors).toEqual([]);
});
