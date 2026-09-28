// The library: importing, the cards, sorting, shelves, the book menu,
// search, and what survives a reload.

import { test, expect } from '@playwright/test';
import {
  start, epubFile, rawFile, importFiles, importInput, card, cards, titles, openBook, toLibrary,
  chapters, dialog, menuItem, bookMenu, libraryMenu, librarySearch, bookPage,
  openSettings, colours, reload,
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
