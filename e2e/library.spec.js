// The library: importing, the cards, sorting, shelves, the book menu,
// search, and what survives a reload.

import { test, expect } from '@playwright/test';
import {
  start, epubFile, rawFile, importFiles, importInput, card, cards, titles, openBook, toLibrary,
  chapters, dialog, menuItem, bookMenu, libraryMenu, librarySearch, bookPage,
  openSettings, colours, reload, place, pageShown,
} from './helpers.js';

// The shelf button is named by the shelf it shows
const shelf = page => page.getByRole('button', { name: /^(Library|Hidden|Archived|Trash)$/ });
const sort = page => page.getByRole('button', { name: /^Sort:/ });
const empty = /Import an EPUB file/;

test('an empty library says how to start', async ({ page }) => {
  const errors = await start(page);
  await expect(page.getByText(empty)).toBeVisible();
  await expect(cards(page)).toHaveCount(0);
  expect(errors).toEqual([]);
});

test('imported books show their title and author, and survive a reload', async ({ page }) => {
  const errors = await start(page);
  await importFiles(page, [
    epubFile({ title: 'Alpha Book', author: 'Ann Author', coverImage: true }),
    epubFile({ title: 'Beta Book', author: 'Bob Writer' }),
  ], 2);
  await expect(card(page, 'Alpha Book')).toContainText('Ann Author');
  await expect(card(page, 'Beta Book')).toContainText('Bob Writer');
  await expect(page.getByText(empty)).toBeHidden();
  // the cover is shown from the book's image. It is decorative (alt=""),
  // the title being beside it, so it has no role to find it by: it is
  // the card's one image element
  await expect.poll(() => card(page, 'Alpha Book').locator('img').evaluate(i => i.complete && i.naturalWidth > 0)).toBe(true);
  await reload(page);
  await expect(cards(page)).toHaveCount(2);
  await expect(card(page, 'Beta Book')).toContainText('Bob Writer');
  expect(errors).toEqual([]);
});

test('a file that is not an EPUB is refused with a message', async ({ page }) => {
  await start(page);
  await importInput(page).setInputFiles([rawFile('notes.epub', Buffer.from('this is not a zip file at all'))]);
  const alert = page.getByRole('alert');
  await expect(alert).toBeVisible();
  await expect(alert).toContainText('could not be imported');
  await expect(cards(page)).toHaveCount(0);
  await alert.getByRole('button', { name: 'Dismiss' }).click();
  await expect(alert).toBeHidden();
});

test('importing the same book again asks, and Skip keeps one copy', async ({ page }) => {
  await start(page);
  const f = epubFile({ title: 'Twice Told', author: 'Echo' });
  await importFiles(page, [f], 1);
  await importInput(page).setInputFiles([f]);
  const ask = dialog(page, 'Already in library');
  await expect(ask).toBeVisible();
  await ask.getByRole('button', { name: 'Skip' }).click();
  await expect(ask).toBeHidden();
  await expect(cards(page)).toHaveCount(1);
  // nothing is left saying the file is being read
  await expect(page.getByRole('status').filter({ hasText: 'Reading file' })).toBeHidden();
});

test('the sort button cycles the orders, and the order is kept', async ({ page }) => {
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'Mango', author: 'Zed' }),
    epubFile({ title: 'Apple', author: 'Yan' }),
    epubFile({ title: 'Kiwi', author: 'Abe' }),
  ], 3);
  await expect(sort(page)).toHaveText('Sort: Last opened');
  await sort(page).click();
  await expect(sort(page)).toHaveText('Sort: Title');
  expect(await titles(page)).toEqual(['Apple', 'Kiwi', 'Mango']);
  await sort(page).click();
  await expect(sort(page)).toHaveText('Sort: Author');
  expect(await titles(page)).toEqual(['Kiwi', 'Apple', 'Mango']);
  await reload(page);
  await expect(sort(page)).toHaveText('Sort: Author');
  expect(await titles(page)).toEqual(['Kiwi', 'Apple', 'Mango']);
});

test('last opened comes first when sorting by last opened', async ({ page }) => {
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'First In', author: 'A' }),
    epubFile({ title: 'Second In', author: 'B' }),
  ], 2);
  await openBook(page, 'First In');
  await toLibrary(page);
  expect((await titles(page))[0]).toBe('First In');
});

test('the search box filters by title and author', async ({ page }) => {
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'Ocean Tales', author: 'Marina' }),
    epubFile({ title: 'Desert Songs', author: 'Sandy' }),
  ], 2);
  const q = librarySearch(page);
  await q.fill('ocean');
  await expect(cards(page)).toHaveCount(1);
  await expect(cards(page)).toContainText('Ocean Tales');
  await q.fill('sandy');
  await expect(cards(page)).toHaveCount(1);
  await expect(cards(page)).toContainText('Desert Songs');
  await q.fill('nothing like it');
  await expect(cards(page)).toHaveCount(0);
  await expect(page.getByText('No books match')).toBeVisible();
  await q.fill('');
  await expect(cards(page)).toHaveCount(2);
  // the clear button shows only while there is something to clear
  const clear = page.getByRole('button', { name: 'Clear search' });
  await expect(clear).toBeHidden();
  await librarySearch(page).fill('ocean');
  await expect(cards(page)).toHaveCount(1);
  await clear.click();
  await expect(cards(page)).toHaveCount(2);
  await expect(librarySearch(page)).toHaveValue('');
  await expect(librarySearch(page)).toBeFocused();
  await expect(clear).toBeHidden();
});

test('a hidden book moves to the hidden shelf and back', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Secret Diary', author: 'Me' }), epubFile({ title: 'Open Book', author: 'You' })], 2);
  await bookMenu(page, 'Secret Diary');
  await menuItem(page, 'Hide').click();
  await expect(cards(page)).toHaveCount(1);
  await expect(card(page, 'Secret Diary')).toHaveCount(0);
  await shelf(page).click();
  await expect(shelf(page)).toHaveText('Hidden');
  await expect(cards(page)).toHaveCount(1);
  await bookMenu(page, 'Secret Diary');
  await menuItem(page, 'Unhide').click();
  await expect(cards(page)).toHaveCount(0);
  await expect(page.getByText('No hidden books')).toBeVisible();
  // Hidden, then Archived, the Trash and back to the Library
  await shelf(page).click();
  await shelf(page).click();
  await shelf(page).click();
  await expect(shelf(page)).toHaveText('Library');
  await expect(cards(page)).toHaveCount(2);
});

test('an archived book keeps its record, and is read again by importing it', async ({ page }) => {
  await start(page);
  const f = epubFile({ title: 'Old Volume', author: 'Past' });
  await importFiles(page, [f], 1);
  await bookMenu(page, 'Old Volume');
  await menuItem(page, 'Archive').click();
  await expect(cards(page)).toHaveCount(0);
  await shelf(page).click();
  await shelf(page).click();
  await expect(shelf(page)).toHaveText('Archived');
  await card(page, 'Old Volume').click();
  const said = dialog(page, 'Archived');
  await expect(said).toBeVisible();
  await said.getByRole('button', { name: 'OK' }).click();
  await expect(bookPage(page)).toBeHidden();
  // importing it again restores it to the shelf
  await importInput(page).setInputFiles([f]);
  await shelf(page).click();
  await shelf(page).click();
  await expect(shelf(page)).toHaveText('Library');
  await expect(card(page, 'Old Volume')).toHaveCount(1);
  await openBook(page, 'Old Volume');
});

const bg = async page => (await colours(page)).bg.join(',');
const undo = page => page.getByRole('button', { name: 'Undo' });

test('a book moved to the Trash can be undone, and restored from it', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Doomed', author: 'X' }), epubFile({ title: 'Kept', author: 'Y' })], 2);
  // moving it to the Trash asks nothing, and offers Undo
  await bookMenu(page, 'Doomed');
  await menuItem(page, 'Move to Trash').click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(cards(page)).toHaveCount(1);
  await undo(page).click();
  await expect(cards(page)).toHaveCount(2);
  await expect(undo(page)).toBeHidden();
  // in the Trash it is kept, across a reload
  await bookMenu(page, 'Doomed');
  await menuItem(page, 'Move to Trash').click();
  await expect(cards(page)).toHaveCount(1);
  await reload(page);
  await expect(cards(page)).toHaveCount(1);
  for (let i = 0; i < 3; i++) await shelf(page).click();
  await expect(shelf(page)).toHaveText('Trash');
  await expect(card(page, 'Doomed')).toHaveCount(1);
  // a book in the Trash can only be restored: it leaves for good only
  // when the Trash is emptied
  await bookMenu(page, 'Doomed');
  await expect(menuItem(page, 'Restore')).toBeVisible();
  await expect(menuItem(page, 'Move to Trash')).toBeHidden();
  await expect(menuItem(page, 'Archive')).toBeHidden();
  await menuItem(page, 'Restore').click();
  await expect(page.getByText('The Trash is empty')).toBeVisible();
  await shelf(page).click();
  await expect(cards(page)).toHaveCount(2);
  await reload(page);
  await expect(cards(page)).toHaveCount(2);
});

test('emptying the Trash asks, and deletes only what is in it', async ({ page }) => {
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'Trash One', author: 'A' }),
    epubFile({ title: 'Trash Two', author: 'B' }),
    epubFile({ title: 'Stays', author: 'C' }),
  ], 3);
  for (const t of ['Trash One', 'Trash Two']) {
    await bookMenu(page, t);
    await menuItem(page, 'Move to Trash').click();
  }
  await libraryMenu(page);
  // the one irreversible action is the one marked: red, unlike the
  // items and the button beside it
  const colour = l => l.evaluate(e => getComputedStyle(e).color);
  const red = await colour(menuItem(page, 'Empty Trash'));
  expect(red).not.toBe(await colour(menuItem(page, 'Factory reset')));
  await menuItem(page, 'Empty Trash').click();
  const ask = dialog(page, 'Empty the Trash?');
  expect(await colour(ask.getByRole('button', { name: 'Empty' }))).toBe(red);
  expect(await colour(ask.getByRole('button', { name: 'Cancel' }))).not.toBe(red);
  await ask.getByRole('button', { name: 'Cancel' }).click();
  for (let i = 0; i < 3; i++) await shelf(page).click();
  await expect(cards(page)).toHaveCount(2);
  await libraryMenu(page);
  await menuItem(page, 'Empty Trash').click();
  await ask.getByRole('button', { name: 'Empty' }).click();
  await expect(page.getByText('The Trash is empty')).toBeVisible();
  // what the Trash held can no longer be offered back
  await expect(undo(page)).toBeHidden();
  await reload(page);
  await expect(cards(page)).toHaveCount(1);
  await expect(card(page, 'Stays')).toHaveCount(1);
});

test('archiving can be undone, and the book still opens', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Nearly Archived', author: 'A', rawChapters: chapters(1, 5) })], 1);
  await bookMenu(page, 'Nearly Archived');
  await menuItem(page, 'Archive').click();
  await expect(cards(page)).toHaveCount(0);
  await undo(page).click();
  await expect(cards(page)).toHaveCount(1);
  await openBook(page, 'Nearly Archived');
});

test('book info shows the book and its progress', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Info Book', author: 'Informant', rawChapters: chapters(2) })], 1);
  await bookMenu(page, 'Info Book');
  await menuItem(page, 'Book info').click();
  const info = dialog(page, 'Book info');
  await expect(info).toBeVisible();
  await expect(info).toContainText('Info Book');
  await expect(info).toContainText('Informant');
  await expect(info).toContainText(/Last read\s*Never/);
  // a book without a cover shows no image (covers are decorative, so
  // they are found as the view's image element, not by role)
  await expect(info.locator('img')).toBeHidden();
  await info.getByRole('button', { name: '← Library' }).click();
  // one with a cover shows it, at a size that can be seen
  await importFiles(page, [epubFile({ title: 'Covered Book', author: 'Pictor', coverImage: true })], 2);
  await bookMenu(page, 'Covered Book');
  await menuItem(page, 'Book info').click();
  const cover = info.locator('img');
  await expect.poll(() => cover.evaluate(i => i.complete && i.naturalWidth > 0)).toBe(true);
  expect((await cover.boundingBox()).width).toBeGreaterThanOrEqual(100);
  await info.getByRole('button', { name: '← Library' }).click();
  await expect(info).toBeHidden();
});

test('a factory reset moves the library to the Trash and resets the settings, and can be undone', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Ephemeral', author: 'Z' }), epubFile({ title: 'Lasting', author: 'W' })], 2);
  await bookMenu(page, 'Lasting');
  await menuItem(page, 'Hide').click();
  const plain = await bg(page);
  await openBook(page, 'Ephemeral');
  await openSettings(page);
  await page.getByRole('button', { name: 'Sepia', exact: true }).click();
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await expect.poll(() => bg(page)).not.toBe(plain);
  const sepia = await bg(page);
  // it asks nothing, and offers Undo
  await libraryMenu(page);
  await menuItem(page, 'Factory reset').click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(cards(page)).toHaveCount(0);
  await expect(page.getByText(empty)).toBeVisible();
  await expect.poll(() => bg(page)).toBe(plain);
  // Undo puts back every book on its own shelf, and the settings
  await undo(page).click();
  await expect(card(page, 'Ephemeral')).toHaveCount(1);
  await expect(card(page, 'Lasting')).toHaveCount(0);
  await expect.poll(() => bg(page)).toBe(sepia);
  await shelf(page).click();
  await expect(card(page, 'Lasting')).toHaveCount(1);
  for (let i = 0; i < 3; i++) await shelf(page).click();
  // without Undo, the books wait in the Trash
  await expect(shelf(page)).toHaveText('Library');
  await libraryMenu(page);
  await menuItem(page, 'Factory reset').click();
  await expect(cards(page)).toHaveCount(0);
  await reload(page);
  await expect(cards(page)).toHaveCount(0);
  for (let i = 0; i < 3; i++) await shelf(page).click();
  await expect(cards(page)).toHaveCount(2);
});

test('dropping a file on the library imports it', async ({ page }) => {
  await start(page);
  const data = [...(await import('node:fs')).readFileSync(epubFile({ title: 'Dropped In', author: 'Gravity' }))];
  const dt = await page.evaluateHandle(bytes => {
    const dt = new DataTransfer();
    dt.items.add(new File([new Uint8Array(bytes)], 'dropped.epub', { type: 'application/epub+zip' }));
    return dt;
  }, data);
  const lib = page.getByRole('main');
  await lib.dispatchEvent('dragover', { dataTransfer: dt });
  await lib.dispatchEvent('drop', { dataTransfer: dt });
  await expect(card(page, 'Dropped In')).toHaveCount(1, { timeout: 30000 });
});

test('importing the same book again and choosing Replace keeps one copy that still opens', async ({ page }) => {
  await start(page);
  const f = epubFile({ title: 'Replaced Twice', author: 'Echo', rawChapters: chapters(1, 5) });
  await importFiles(page, [f], 1);
  await importInput(page).setInputFiles([f]);
  const ask = dialog(page, 'Already in library');
  await ask.getByRole('button', { name: 'Replace' }).click();
  await expect(ask).toBeHidden();
  await expect(cards(page)).toHaveCount(1);
  await expect(page.getByRole('status').filter({ hasText: /Reading file|Opening archive|Adding/ })).toBeHidden();
  await openBook(page, 'Replaced Twice');
});

test('the book menu and the library menu close without doing anything', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Left Alone', author: 'A' })], 1);
  await bookMenu(page, 'Left Alone');
  await page.keyboard.press('Escape');
  await expect(page.getByRole('menu')).toBeHidden();
  await bookMenu(page, 'Left Alone');
  // a click outside the menu
  await page.mouse.click(5, 5);
  await expect(page.getByRole('menu')).toBeHidden();
  // a right-click on the card opens the same menu
  await card(page, 'Left Alone').getByRole('button').first().click({ button: 'right' });
  await expect(page.getByRole('menu', { name: 'Book menu' })).toBeVisible();
  await page.keyboard.press('Escape');
  await libraryMenu(page);
  await menuItem(page, 'Close').click();
  await expect(page.getByRole('menu')).toBeHidden();
  await expect(cards(page)).toHaveCount(1);
});

test('book info hides, archives and trashes the book it shows', async ({ page }) => {
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'Info Hide', author: 'A' }),
    epubFile({ title: 'Info Archive', author: 'B' }),
    epubFile({ title: 'Info Delete', author: 'C' }),
  ], 3);
  const info = dialog(page, 'Book info');
  const viaInfo = async (title, button) => {
    await bookMenu(page, title);
    await menuItem(page, 'Book info').click();
    await info.getByRole('button', { name: button, exact: true }).click();
  };
  await viaInfo('Info Hide', 'Hide');
  await expect(info).toBeHidden();
  await expect(card(page, 'Info Hide')).toHaveCount(0);
  await viaInfo('Info Archive', 'Archive');
  await expect(card(page, 'Info Archive')).toHaveCount(0);
  await viaInfo('Info Delete', 'Move to Trash');
  await expect(cards(page)).toHaveCount(0);
  // the other shelves hold them
  await shelf(page).click();
  await expect(card(page, 'Info Hide')).toHaveCount(1);
  await shelf(page).click();
  await expect(card(page, 'Info Archive')).toHaveCount(1);
  await shelf(page).click();
  await expect(card(page, 'Info Delete')).toHaveCount(1);
});

test('restoring an archived book from its menu says to import it again', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Stored Away', author: 'A' })], 1);
  await bookMenu(page, 'Stored Away');
  await menuItem(page, 'Archive').click();
  await shelf(page).click();
  await shelf(page).click();
  await bookMenu(page, 'Stored Away');
  await menuItem(page, 'Restore').click();
  const said = dialog(page, 'Restore');
  await expect(said).toContainText('import its file again');
  await said.getByRole('button', { name: 'OK' }).click();
  await expect(said).toBeHidden();
});

test('after a duplicate is skipped, the other files picked with it are imported', async ({ page }) => {
  await start(page);
  const first = epubFile({ title: 'Already Here', author: 'A' });
  await importFiles(page, [first], 1);
  await importInput(page).setInputFiles([first, epubFile({ title: 'Brand New', author: 'B' })]);
  await dialog(page, 'Already in library').getByRole('button', { name: 'Skip' }).click();
  await expect(card(page, 'Brand New')).toHaveCount(1, { timeout: 30000 });
  await expect(cards(page)).toHaveCount(2);
});

// As the Android app hands over a file another app shared or opened with
// it: fetched from a local URL, under the name the other app gave it
test('a file handed over by the host is imported', async ({ page }) => {
  const errors = await start(page);
  const epub = epubFile({ title: 'Shared With Quire', author: 'Smoke Test', chapters: 2, storeChapters: true });
  await page.route('**/_capacitor_file_/**', r => r.fulfill({ path: epub, contentType: 'application/octet-stream' }));
  await page.evaluate(() => globalThis.batsFetchExternal('/_capacitor_file_/data/cache/incoming/in1.bin', 'smoke-share'));
  await expect(card(page, 'Shared With Quire')).toContainText('Smoke Test', { timeout: 30000 });
  expect(errors).toEqual([]);
});

// EPUB Accessibility 1.1's discovery metadata, shown in the W3C
// Publishing CG's display guidelines' words
const infoOf = async (page, title) => {
  await bookMenu(page, title);
  await menuItem(page, 'Book info').click();
  return dialog(page, 'Book info').getByRole('region', { name: 'Accessibility' });
};

test('Book info shows the book\'s accessibility metadata in plain words', async ({ page }) => {
  await start(page);
  const metadata = `    <meta property="schema:accessMode">textual</meta>
    <meta property="schema:accessMode">visual</meta>
    <meta property="schema:accessModeSufficient">textual</meta>
    <meta property="schema:accessibilityFeature">displayTransformability</meta>
    <meta property="schema:accessibilityFeature">alternativeText</meta>
    <meta property="schema:accessibilityFeature">tableOfContents</meta>
    <meta property="schema:accessibilityFeature">structuralNavigation</meta>
    <meta property="schema:accessibilityHazard">none</meta>
    <meta property="schema:accessibilitySummary">Images are described; no hazards &amp; no tables.</meta>
    <link rel="dcterms:conformsTo" href="http://www.idpf.org/epub/a11y/accessibility-20170105.html#wcag-aa"/>
`;
  await importFiles(page, [epubFile({ title: 'Accessible', author: 'A', metadata, rawChapters: chapters(1) })], 1);
  const a11y = await infoOf(page, 'Accessible');
  await expect(a11y.locator('div div')).toHaveText([
    'Ways of reading', 'Appearance can be modified', 'Readable in read aloud or dynamic braille', 'Has alternative text',
    'Conformance', 'This publication meets accepted accessibility standards',
    'Navigation', 'Table of contents', 'Headings',
    'Hazards', 'No hazards',
    'Accessibility summary', 'Images are described; no hazards & no tables.',
  ]);
});

test('Book info reads EPUB 2\'s accessibility metadata too, and says when there is none', async ({ page }) => {
  await start(page);
  const metadata = `    <meta name="schema:accessibilityHazard" content="noFlashingHazard"/>
    <meta name="schema:accessibilityHazard" content="sound"/>
    <meta name="dcterms:conformsTo" content="EPUB Accessibility 1.1 - WCAG 2.1 Level AAA"/>
`;
  await importFiles(page, [
    epubFile({ title: 'Two', author: 'A', metadata, rawChapters: chapters(1) }),
    epubFile({ title: 'Bare', author: 'B', rawChapters: chapters(1) }),
  ], 2);
  let a11y = await infoOf(page, 'Two');
  await expect(a11y).toContainText('This publication exceeds accepted accessibility standards');
  await expect(a11y).toContainText('Sounds');
  await expect(a11y).toContainText('No flashing hazards');
  await dialog(page, 'Book info').getByRole('button', { name: /Library/ }).click();
  a11y = await infoOf(page, 'Bare');
  await expect(a11y.locator('div div')).toHaveText([
    'Ways of reading', 'No information about appearance modifiability is available',
    'No information about nonvisual reading is available',
    'Conformance', 'No information is available',
  ]);
});

// A larger library: which books, as a list or a grid, and the one to
// continue
const show = page => page.getByRole('group', { name: 'Show' });
const continueReading = page => page.getByRole('region', { name: 'Continue reading' });

test('the library shows all, unread, reading or finished books, and the choice is kept', async ({ page }) => {
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'Untouched', author: 'A', rawChapters: chapters(1, 3) }),
    epubFile({ title: 'Begun', author: 'B', rawChapters: chapters(2, 20) }),
    epubFile({ title: 'Ended', author: 'C', rawChapters: chapters(1, 3) }),
  ], 3);
  await openBook(page, 'Begun');
  await toLibrary(page);
  await openBook(page, 'Ended');
  await page.keyboard.press('End');
  await toLibrary(page);
  await show(page).getByRole('button', { name: 'Unread' }).click();
  await expect.poll(() => titles(page)).toEqual(['Untouched']);
  await show(page).getByRole('button', { name: 'Reading' }).click();
  await expect.poll(() => titles(page)).toEqual(['Begun']);
  await show(page).getByRole('button', { name: 'Finished' }).click();
  await expect.poll(() => titles(page)).toEqual(['Ended']);
  await expect(show(page).getByRole('button', { name: 'Finished' })).toHaveAttribute('aria-pressed', 'true');
  await reload(page);
  await expect.poll(() => titles(page)).toEqual(['Ended']);
  await show(page).getByRole('button', { name: 'All' }).click();
  await expect(cards(page)).toHaveCount(3);
});

test('the library is a list or a grid of covers, kept with the settings', async ({ page }) => {
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'Grid One', author: 'A', coverImage: true, rawChapters: chapters(1) }),
    epubFile({ title: 'Grid Two', author: 'B', rawChapters: chapters(1) }),
  ], 2);
  const view = page.getByRole('group', { name: 'View' });
  const list = page.getByRole('region', { name: 'Books' });
  expect(await list.evaluate(e => getComputedStyle(e).display)).toBe('flex');
  await view.getByRole('button', { name: 'Grid' }).click();
  await expect(view.getByRole('button', { name: 'Grid' })).toHaveAttribute('aria-pressed', 'true');
  await expect.poll(() => list.evaluate(e => getComputedStyle(e).display)).toBe('grid');
  // the covers stand upright, as tall as 3 to their 2
  const cover = card(page, 'Grid One').locator('img');
  const box = await cover.boundingBox();
  expect(box.height / box.width).toBeCloseTo(1.5, 1);
  await reload(page);
  await expect.poll(() => list.evaluate(e => getComputedStyle(e).display)).toBe('grid');
  await view.getByRole('button', { name: 'List' }).click();
  await expect.poll(() => list.evaluate(e => getComputedStyle(e).display)).toBe('flex');
});

test('the book last opened and not finished is offered to continue, above the rest', async ({ page }) => {
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'Earlier', author: 'A', rawChapters: chapters(2, 20) }),
    epubFile({ title: 'Later', author: 'B', rawChapters: chapters(2, 20) }),
  ], 2);
  await expect(continueReading(page)).toBeHidden();
  await openBook(page, 'Earlier');
  await toLibrary(page);
  await openBook(page, 'Later');
  await page.keyboard.press('ArrowRight');
  await toLibrary(page);
  await expect(continueReading(page)).toBeVisible();
  await expect(continueReading(page).getByRole('button')).toHaveCount(1);
  await expect(continueReading(page)).toContainText('Later');
  // not while searching
  await librarySearch(page).fill('Earl');
  await expect(continueReading(page)).toBeHidden();
  await librarySearch(page).fill('');
  // it opens the book where it was left
  await continueReading(page).getByRole('button').click();
  await pageShown(page);
  await expect.poll(async () => (await place(page)).p).toBe(2);
});

test('books of a series are shown with their number, and sorted by series together, in order', async ({ page }) => {
  await start(page);
  // EPUB 3's collection, Calibre's series, and a book of none
  const epub3 = `    <meta property="belongs-to-collection" id="c1">Foundation</meta>
    <meta refines="#c1" property="collection-type">series</meta>
    <meta refines="#c1" property="group-position">2</meta>
`;
  const calibre = `    <meta name="calibre:series" content="Foundation"/>
    <meta name="calibre:series_index" content="1.0"/>
`;
  await importFiles(page, [
    epubFile({ title: 'Foundation and Empire', author: 'Asimov', metadata: epub3, rawChapters: chapters(1) }),
    epubFile({ title: 'Alone', author: 'Nobody', rawChapters: chapters(1) }),
    epubFile({ title: 'Foundation', author: 'Asimov', metadata: calibre, rawChapters: chapters(1) }),
  ], 3);
  await expect(card(page, 'Foundation and Empire')).toContainText('Foundation · 2');
  await expect(card(page, 'Alone')).not.toContainText('·');
  const sort = page.getByRole('button', { name: /^Sort:/ });
  while ((await sort.textContent()) !== 'Sort: Series') await sort.click();
  await expect.poll(() => titles(page)).toEqual(['Foundation', 'Foundation and Empire', 'Alone']);
  // kept, and read back
  await reload(page);
  await expect(sort).toHaveText('Sort: Series');
  await expect.poll(() => titles(page)).toEqual(['Foundation', 'Foundation and Empire', 'Alone']);
  await expect(cards(page).first()).toContainText('Foundation · 1');
});

// Collections: a book's menu puts it in any of them, the library shows
// one, and one is renamed or deleted (with Undo)
const collectionRow = page => page.getByRole('group', { name: 'Collection' });
const collectionsPanel = page => dialog(page, 'Collections');

test('a collection is made from a book\'s menu, shows its books, and is renamed or deleted', async ({ page }) => {
  const errors = await start(page);
  await importFiles(page, [
    epubFile({ title: 'Kept One', author: 'A' }),
    epubFile({ title: 'Kept Two', author: 'B' }),
    epubFile({ title: 'Left Out', author: 'C' }),
  ], 3);
  await expect(collectionRow(page)).toBeHidden();
  // made from the first book's menu, the book in it
  await bookMenu(page, 'Kept One');
  await menuItem(page, 'Collections').click();
  await expect(collectionsPanel(page).getByText('No collections yet')).toBeVisible();
  await collectionsPanel(page).getByRole('button', { name: 'New collection' }).click();
  const name = dialog(page, 'New collection').getByRole('textbox', { name: 'Name' });
  await expect(name).toBeFocused();
  await name.fill('  To read  ');
  await name.press('Enter');
  const toRead = collectionsPanel(page).getByRole('button', { name: 'To read', exact: true });
  await expect(toRead).toHaveAttribute('aria-pressed', 'true');
  await expect(collectionsPanel(page).getByText('No collections yet')).toBeHidden();
  await collectionsPanel(page).getByRole('button', { name: 'Done' }).click();
  await expect(collectionsPanel(page)).toBeHidden();
  // the second one put in with its toggle
  await bookMenu(page, 'Kept Two');
  await menuItem(page, 'Collections').click();
  await expect(toRead).toHaveAttribute('aria-pressed', 'false');
  await toRead.click();
  await expect(toRead).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');
  await expect(collectionsPanel(page)).toBeHidden();
  // the library shows the collection's books only
  await collectionRow(page).getByRole('button', { name: 'To read' }).click();
  await expect(cards(page)).toHaveCount(2);
  await expect(card(page, 'Left Out')).toHaveCount(0);
  await collectionRow(page).getByRole('button', { name: 'All books' }).click();
  await expect(cards(page)).toHaveCount(3);
  // kept
  await reload(page);
  await collectionRow(page).getByRole('button', { name: 'To read' }).click();
  await expect(cards(page)).toHaveCount(2);
  // renamed, the dialog holding its name
  await page.getByRole('button', { name: 'Rename' }).click();
  const rename = dialog(page, 'Rename collection').getByRole('textbox', { name: 'Name' });
  await expect(rename).toHaveValue('To read');
  await rename.fill('Favourites');
  await dialog(page, 'Rename collection').getByRole('button', { name: 'Rename' }).click();
  await expect(collectionRow(page).getByRole('button', { name: 'Favourites' })).toHaveAttribute('aria-pressed', 'true');
  await expect(cards(page)).toHaveCount(2);
  // deleted: every book shown, none lost; Undo puts it back with its books
  await page.getByRole('button', { name: 'Delete collection' }).click();
  await expect(collectionRow(page)).toBeHidden();
  await expect(cards(page)).toHaveCount(3);
  await page.getByRole('button', { name: 'Undo' }).click();
  await collectionRow(page).getByRole('button', { name: 'Favourites' }).click();
  await expect(cards(page)).toHaveCount(2);
  await expect(card(page, 'Left Out')).toHaveCount(0);
  expect(errors).toEqual([]);
});

// Installing: the page's script (pwa) marks the page pwa-can-install
// where the browser offers to, and pwa-ios-browser on iOS Safari
// outside the Home Screen; here the tests mark it
const markPage = (page, name) => page.evaluate(n => document.documentElement.classList.add(n), name);

test('Install Quire is offered in the library menu only where the browser can install it', async ({ page }) => {
  const errors = await start(page);
  await libraryMenu(page);
  const install = menuItem(page, 'Install Quire');
  await expect(install).toBeHidden();
  await page.keyboard.press('Escape');
  await markPage(page, 'pwa-can-install');
  await libraryMenu(page);
  await expect(install).toBeVisible();
  await expect(install).toHaveAttribute('data-pwa-install', 'y');
  await install.click();
  await expect(page.getByRole('menu', { name: 'Library menu' })).toBeHidden();
  expect(errors).toEqual([]);
});

test('on iOS Safari, once there is a book, a hint says to add Quire to the Home Screen, until it is dismissed', async ({ page }) => {
  const errors = await start(page);
  await markPage(page, 'pwa-ios-browser');
  const hint = page.getByRole('status').filter({ hasText: 'Add Quire to your Home Screen' });
  // not before there is a book
  await expect(hint).toBeHidden();
  await importFiles(page, [epubFile({ title: 'Kept', author: 'A' })], 1);
  await expect(hint).toBeVisible();
  await expect(hint).toContainText('tap Share, then Add to Home Screen');
  await hint.getByRole('button', { name: 'Got it' }).click();
  await expect(hint).toBeHidden();
  // never again
  await reload(page);
  await expect(card(page, 'Kept')).toBeVisible();
  await markPage(page, 'pwa-ios-browser');
  await expect(hint).toBeHidden();
  expect(errors).toEqual([]);
});

test('elsewhere, the Home Screen hint is not shown', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Kept', author: 'A' })], 1);
  await expect(page.getByText('Add Quire to your Home Screen')).toBeHidden();
});
