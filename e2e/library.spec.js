// The library: importing, the cards, sorting, shelves, the book menu,
// search, and what survives a reload.

import { test, expect } from '@playwright/test';
import {
  start, epubFile, rawFile, importFiles, importInput, card, cards, titles, openBook, toLibrary,
  chapters, dialog, menuItem, bookMenu, libraryMenu, librarySearch, bookPage,
} from './helpers.js';

const shelf = page => page.getByRole('button', { name: 'Shelf shown' });
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
  // the cover is shown from the book's image
  await expect.poll(() => card(page, 'Alpha Book').getByRole('img').evaluate(i => i.complete && i.naturalWidth > 0)).toBe(true);
  await page.reload();
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
  await page.reload();
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
  await expect(shelf(page)).toHaveText('Library');
  await expect(card(page, 'Old Volume')).toHaveCount(1);
  await openBook(page, 'Old Volume');
});

test('a deleted book is gone after a reload', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Doomed', author: 'X' }), epubFile({ title: 'Kept', author: 'Y' })], 2);
  await bookMenu(page, 'Doomed');
  await menuItem(page, 'Delete').click();
  const ask = dialog(page, 'Delete book?');
  await ask.getByRole('button', { name: 'Delete' }).click();
  await expect(cards(page)).toHaveCount(1);
  await page.reload();
  await expect(cards(page)).toHaveCount(1);
  await expect(card(page, 'Kept')).toHaveCount(1);
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
  await info.getByRole('button', { name: '← Library' }).click();
  await expect(info).toBeHidden();
});

test('a factory reset empties the library', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Ephemeral', author: 'Z' })], 1);
  await libraryMenu(page);
  await menuItem(page, 'Factory reset').click();
  await dialog(page, 'Factory reset?').getByRole('button', { name: 'Reset' }).click();
  await expect(importInput(page)).toBeVisible();
  await expect(cards(page)).toHaveCount(0);
  await expect(page.getByText(empty)).toBeVisible();
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
