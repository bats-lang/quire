// Bookmarks, highlights and notes: made from the reader, listed, gone
// to, kept, and exported as Markdown.

import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import {
  start, readBook, place, showChrome, toLibrary, openBook, selectText, marks, chapters, dialog,
  control, selectionButton, reload,
} from './helpers.js';

const panel = page => dialog(page, 'Annotations');
const note = page => dialog(page, 'Note');
const selection = page => page.getByRole('toolbar', { name: 'Selection' });
const star = page => page.getByRole('button', { name: 'Bookmark this page' });

async function openPanel(page) {
  await showChrome(page);
  await control(page, 'Annotations').click();
  await expect(panel(page)).toBeVisible();
}

async function writeNote(page, text) {
  await expect(note(page).getByRole('textbox', { name: 'Note' })).toBeVisible();
  await note(page).getByRole('textbox', { name: 'Note' }).fill(text);
  await note(page).getByRole('button', { name: 'Save' }).click();
}

const book = { title: 'Marked Up', author: 'Annotations Tests', rawChapters: chapters(2) };

test('a highlight is marked, kept, and listed with its note', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, book);
  await selectText(page, 0, 8);
  await expect(selection(page)).toBeVisible();
  await selectionButton(page, 'Highlight').click();
  await expect(selection(page)).toBeHidden();
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'Para 1.0' });
  // a note on it
  await openPanel(page);
  await expect(panel(page)).toContainText('Para 1.0');
  await panel(page).getByRole('button', { name: 'Add note' }).click();
  await writeNote(page, 'A thought, with "quotes"');
  await expect(panel(page)).toContainText('A thought, with "quotes"');
  await panel(page).getByRole('button', { name: 'Close' }).click();
  // kept across a reload
  await toLibrary(page);
  await reload(page);
  await openBook(page, 'Marked Up');
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'Para 1.0' });
  await openPanel(page);
  await expect(panel(page)).toContainText('A thought, with "quotes"');
  expect(errors).toEqual([]);
});

test('a note can be made straight from a selection', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await selectText(page, 5, 8);
  await selectionButton(page, 'Note').click();
  await writeNote(page, 'Straight away');
  await openPanel(page);
  await expect(panel(page)).toContainText('1.0');
  await expect(panel(page)).toContainText('Straight away');
});

test('an annotation in the list is gone to, and can be deleted', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  await selectText(page, 0, 8);
  await selectionButton(page, 'Highlight').click();
  await page.keyboard.press('Home');
  await page.keyboard.press('ArrowLeft');
  await expect.poll(async () => (await place(page)).ch).toBe(1);
  await openPanel(page);
  await panel(page).getByRole('button', { name: /Para 2\.0/ }).click();
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  await expect.poll(() => marks(page)).toMatchObject({ size: 1 });
  await openPanel(page);
  // deleting asks nothing, and can be undone
  await panel(page).getByRole('button', { name: 'Delete' }).click();
  await expect(panel(page).getByRole('button', { name: 'Delete' })).toHaveCount(0);
  await page.getByRole('button', { name: 'Undo' }).click();
  await expect(panel(page).getByRole('button', { name: 'Delete' })).toHaveCount(1);
  await expect.poll(() => marks(page)).toMatchObject({ size: 1 });
  await panel(page).getByRole('button', { name: 'Delete' }).click();
  await expect(panel(page).getByRole('button', { name: 'Delete' })).toHaveCount(0);
  await expect(panel(page)).toContainText('No highlights yet');
  await expect.poll(() => marks(page)).toMatchObject({ size: 0 });
});

test('the export is Markdown with the book, its highlights and notes', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await selectText(page, 0, 8);
  await selectionButton(page, 'Note').click();
  await writeNote(page, 'Exported note');
  await openPanel(page);
  const download = page.waitForEvent('download');
  await panel(page).getByRole('button', { name: 'Export', exact: true }).click();
  const d = await download;
  expect(d.suggestedFilename()).toBe('quire-annotations.md');
  const md = readFileSync(await d.path(), 'utf8');
  expect(md).toMatch(/^# Marked Up\n## Annotations Tests\n/);
  expect(md).toContain('Para 1.0');
  expect(md).toContain('Exported note');
  // each quote says where it is from, as Kindle's notebook does
  expect(md).toMatch(/> Para 1\.0[^\n]*\n\n— Annotations Tests, \*Marked Up\*, Chapter 1\n\n\*\*Note:\*\* Exported note/);
});

// every mark set on the page, with the text of each range in it
const markSets = page => page.evaluate(() =>
  Object.fromEntries([...CSS.highlights].map(([name, h]) => [name, [...h].map(r => r.toString())])));

test('a highlight is yellow, orange or underlined: marked so, named in the list, filtered, and kept', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, book);
  await selectText(page, 0, 8);
  await selectionButton(page, 'Highlight').click();
  await selectText(page, 9, 14);
  await selectionButton(page, 'Orange').click();
  await selectText(page, 15, 20);
  await selectionButton(page, 'Underline').click();
  const expected = { 'bats-mark-1': ['Para 1.0'], 'bats-mark-3': ['lorem'], 'bats-mark-4': ['ipsum'] };
  await expect.poll(() => markSets(page)).toEqual(expected);
  // each is named by its style in words, not by its colour alone
  await openPanel(page);
  const rows = panel(page).getByRole('button', { name: /^(Yellow|Orange|Underlined).+/ });
  await expect(rows).toHaveCount(3);
  await expect(rows.nth(0)).toContainText('Yellow');
  await expect(rows.nth(1)).toContainText('Orange');
  await expect(rows.nth(2)).toContainText('Underlined');
  // one style's are listed on their own
  const show = panel(page).getByRole('group', { name: 'Show' });
  await show.getByRole('button', { name: 'Orange' }).click();
  await expect(show.getByRole('button', { name: 'Orange' })).toHaveAttribute('aria-pressed', 'true');
  await expect(rows).toHaveCount(1);
  await expect(rows.first()).toContainText('lorem');
  await show.getByRole('button', { name: 'Underlined' }).click();
  await expect(rows).toHaveCount(1);
  await expect(rows.first()).toContainText('ipsum');
  await show.getByRole('button', { name: 'All' }).click();
  await expect(rows).toHaveCount(3);
  await panel(page).getByRole('button', { name: 'Close' }).click();
  // kept across a reload
  await toLibrary(page);
  await reload(page);
  await openBook(page, 'Marked Up');
  await expect.poll(() => markSets(page)).toEqual(expected);
  expect(errors).toEqual([]);
});

test('the export names a highlight\'s style, unless it is yellow', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await selectText(page, 0, 8);
  await selectionButton(page, 'Highlight').click();
  await selectText(page, 9, 14);
  await selectionButton(page, 'Orange').click();
  await selectText(page, 15, 20);
  await selectionButton(page, 'Underline').click();
  await openPanel(page);
  const download = page.waitForEvent('download');
  await panel(page).getByRole('button', { name: 'Export', exact: true }).click();
  const md = readFileSync(await (await download).path(), 'utf8');
  expect(md).toMatch(/> Para 1\.0\n\n— /);
  expect(md).toMatch(/> lorem\n\n\*Orange highlight\*\n\n— /);
  expect(md).toMatch(/> ipsum\n\n\*Underlined\*\n\n— /);
});

test('a bookmark can have a note, which is listed and exported', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  await page.keyboard.press('b');
  await showChrome(page);
  await control(page, 'Contents').click();
  await dialog(page, 'Contents').getByRole('tab', { name: 'Bookmarks' }).click();
  const list = dialog(page, 'Contents').getByRole('tabpanel', { name: 'Bookmarks' });
  await list.getByRole('button', { name: 'Add note' }).click();
  await writeNote(page, 'Come back here');
  await expect(list).toContainText('Come back here');
  await expect(list.getByRole('button', { name: 'Edit note' })).toBeVisible();
  await page.keyboard.press('Escape');
  await openPanel(page);
  const download = page.waitForEvent('download');
  await panel(page).getByRole('button', { name: 'Export', exact: true }).click();
  const md = readFileSync(await (await download).path(), 'utf8');
  expect(md).toMatch(/\*\*Bookmark:\*\* [^\n]+\n\n\*\*Note:\*\* Come back here/);
});

test('the star bookmarks the page, lists it, and unbookmarks it', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  await showChrome(page);
  await expect(star(page)).toHaveAttribute('aria-pressed', 'false');
  await star(page).click();
  await expect(star(page)).toHaveAttribute('aria-pressed', 'true');
  // not on another page
  await page.keyboard.press('ArrowRight');
  await showChrome(page);
  await expect(star(page)).toHaveAttribute('aria-pressed', 'false');
  // listed on the contents panel's bookmarks tab, and gone to from there
  await control(page, 'Contents').click();
  const tab = dialog(page, 'Contents').getByRole('tab', { name: 'Bookmarks' });
  await tab.click();
  await expect(tab).toHaveAttribute('aria-selected', 'true');
  const marked = dialog(page, 'Contents').getByRole('tabpanel', { name: 'Bookmarks' }).getByRole('button', { name: /Chapter 1/ });
  await expect(marked).toBeVisible();
  await marked.click();
  await expect.poll(async () => (await place(page)).p).toBe(2);
  // the b key takes it off again
  await page.keyboard.press('b');
  await showChrome(page);
  await expect(star(page)).toHaveAttribute('aria-pressed', 'false');
});

test('Copy puts the selected text on the clipboard', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await start(page);
  await readBook(page, book);
  await selectText(page, 0, 8);
  await selectionButton(page, 'Copy').click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe('Para 1.0');
});

test('Look up opens the selection in a dictionary of the book\'s language, in a new tab', async ({ page }) => {
  await start(page);
  await readBook(page, { ...book, title: 'Livre', language: 'fr-CA' });
  await selectText(page, 0, 8);
  const toolbar = page.getByRole('toolbar', { name: 'Selection' });
  const look = toolbar.getByRole('link', { name: 'Look up' });
  await expect(look).toHaveAttribute('href', 'https://fr.wiktionary.org/wiki/Special:Search?search=Para%201.0');
  await expect(look).toHaveAttribute('target', '_blank');
  await expect(look).toHaveAttribute('rel', /noopener/);
  // it follows the selection, and a book with no language is looked up in English
  await toLibrary(page);
  await readBook(page, { ...book, title: 'Plain', language: null });
  await selectText(page, 5, 8);
  await expect(look).toHaveAttribute('href', 'https://en.wiktionary.org/wiki/Special:Search?search=1.0');
});

test('a note that is cancelled leaves nothing behind', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await selectText(page, 0, 8);
  await selectionButton(page, 'Note').click();
  await note(page).getByRole('textbox', { name: 'Note' }).fill('Never mind');
  await note(page).getByRole('button', { name: 'Cancel' }).click();
  await expect(note(page)).toBeHidden();
  await expect.poll(() => marks(page)).toMatchObject({ size: 0 });
  await openPanel(page);
  await expect(panel(page)).toContainText('No highlights yet');
});

test('a bookmark is deleted from the bookmarks tab', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await page.keyboard.press('b');
  await showChrome(page);
  await expect(star(page)).toHaveAttribute('aria-pressed', 'true');
  await control(page, 'Contents').click();
  await dialog(page, 'Contents').getByRole('tab', { name: 'Bookmarks' }).click();
  const list = dialog(page, 'Contents').getByRole('tabpanel', { name: 'Bookmarks' });
  await list.getByRole('button', { name: 'Delete' }).click();
  await expect(list.getByRole('button', { name: 'Delete' })).toHaveCount(0);
  await page.keyboard.press('Escape');
  await showChrome(page);
  await expect(star(page)).toHaveAttribute('aria-pressed', 'false');
});

// Sharing, by the page's script (pwa): here with a share sheet that
// keeps what it is given
async function fakeShare(page) {
  await page.addInitScript(() => {
    window.shared = [];
    navigator.canShare = d => !!d.files;
    navigator.share = async d => {
      const files = await Promise.all((d.files || []).map(async f => ({ name: f.name, type: f.type, text: await f.text() })));
      window.shared.push({ text: d.text, files });
    };
  });
}
const shared = page => page.evaluate(() => window.shared);

test('a selection is shared with its book, and the highlights and notes as the exported file', async ({ page }) => {
  await fakeShare(page);
  await start(page);
  await readBook(page, book);
  await selectText(page, 0, 8);
  await selectionButton(page, 'Share').click();
  await expect.poll(() => shared(page)).toEqual([{ text: '“Para 1.0”\n— Annotations Tests, Marked Up', files: [] }]);
  await selectText(page, 0, 8);
  await selectionButton(page, 'Note').click();
  await writeNote(page, 'Shared note');
  await openPanel(page);
  await panel(page).getByRole('button', { name: 'Share', exact: true }).click();
  await expect.poll(async () => (await shared(page)).length).toBe(2);
  const [file] = (await shared(page))[1].files;
  expect(file).toMatchObject({ name: 'quire-annotations.md', type: 'text/markdown' });
  expect(file.text).toMatch(/^# Marked Up\n## Annotations Tests\n/);
  expect(file.text).toMatch(/> Para 1\.0[^\n]*\n\n— Annotations Tests, \*Marked Up\*, Chapter 1\n\n\*\*Note:\*\* Shared note/);
});

test('where nothing can be shared, Share is not offered', async ({ page }) => {
  await page.addInitScript(() => { delete Navigator.prototype.share; delete navigator.share; });
  await start(page);
  await readBook(page, book);
  await selectText(page, 0, 8);
  await expect(selection(page).getByRole('button', { name: 'Share', exact: true })).toBeHidden();
  await openPanel(page);
  await expect(panel(page).getByRole('button', { name: 'Share', exact: true })).toBeHidden();
});
