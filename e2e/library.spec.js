// The library: importing, the cards, sorting, shelves, the book menu,
// search, and what survives a reload.

import { test, expect } from '@playwright/test';
import { start, epubFile, rawFile, importFiles, card, openBook, toLibrary, chapters } from './helpers.js';

test('an empty library says how to start', async ({ page }) => {
  const errors = await start(page);
  await expect(page.locator('#qelb')).toHaveText(/Import an EPUB file/);
  await expect(page.locator('#qlst .card')).toHaveCount(0);
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
  await expect(page.locator('#qelb')).toBeHidden();
  // the cover is shown from the book's image
  await expect.poll(() => card(page, 'Alpha Book').locator('img').evaluate(i => i.complete && i.naturalWidth > 0)).toBe(true);
  await page.reload();
  await expect(page.locator('#qlst .card')).toHaveCount(2);
  await expect(card(page, 'Beta Book')).toContainText('Bob Writer');
  expect(errors).toEqual([]);
});

test('a file that is not an EPUB is refused with a message', async ({ page }) => {
  await start(page);
  await page.locator('#qfin').setInputFiles([rawFile('notes.epub', Buffer.from('this is not a zip file at all'))]);
  await expect(page.locator('#qerr')).toBeVisible();
  await expect(page.locator('#qert')).toContainText('could not be imported');
  await expect(page.locator('#qlst .card')).toHaveCount(0);
  await page.locator('#qerx').click();
  await expect(page.locator('#qerr')).toBeHidden();
});

test('importing the same book again asks, and Skip keeps one copy', async ({ page }) => {
  await start(page);
  const f = epubFile({ title: 'Twice Told', author: 'Echo' });
  await importFiles(page, [f], 1);
  await page.locator('#qfin').setInputFiles([f]);
  await expect(page.locator('#qmod')).toBeVisible();
  await expect(page.locator('#qmtt')).toHaveText('Already in library');
  await page.locator('#qmb1').click();
  await expect(page.locator('#qmod')).toBeHidden();
  await expect(page.locator('#qlst .card')).toHaveCount(1);
});

test('the sort button cycles the orders, and the order is kept', async ({ page }) => {
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'Mango', author: 'Zed' }),
    epubFile({ title: 'Apple', author: 'Yan' }),
    epubFile({ title: 'Kiwi', author: 'Abe' }),
  ], 3);
  const titles = () => page.locator('#qlst .card .bt').allInnerTexts();
  await expect(page.locator('#qsrt')).toHaveText('Sort: Last opened');
  await page.locator('#qsrt').click();
  await expect(page.locator('#qsrt')).toHaveText('Sort: Title');
  expect(await titles()).toEqual(['Apple', 'Kiwi', 'Mango']);
  await page.locator('#qsrt').click();
  await expect(page.locator('#qsrt')).toHaveText('Sort: Author');
  expect(await titles()).toEqual(['Kiwi', 'Apple', 'Mango']);
  await page.reload();
  await expect(page.locator('#qsrt')).toHaveText('Sort: Author');
  expect(await titles()).toEqual(['Kiwi', 'Apple', 'Mango']);
});

test('last opened comes first when sorting by last opened', async ({ page }) => {
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'First In', author: 'A' }),
    epubFile({ title: 'Second In', author: 'B' }),
  ], 2);
  await openBook(page, 'First In');
  await toLibrary(page);
  await expect(page.locator('#qlst .card .bt').first()).toHaveText('First In');
});

test('the search box filters by title and author', async ({ page }) => {
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'Ocean Tales', author: 'Marina' }),
    epubFile({ title: 'Desert Songs', author: 'Sandy' }),
  ], 2);
  await page.locator('#qlsq').fill('ocean');
  await expect(page.locator('#qlst .card')).toHaveCount(1);
  await expect(page.locator('#qlst .card')).toContainText('Ocean Tales');
  await page.locator('#qlsq').fill('sandy');
  await expect(page.locator('#qlst .card')).toHaveCount(1);
  await expect(page.locator('#qlst .card')).toContainText('Desert Songs');
  await page.locator('#qlsq').fill('nothing like it');
  await expect(page.locator('#qlst .card')).toHaveCount(0);
  await expect(page.locator('#qelb')).toHaveText('No books match');
  await page.locator('#qlsq').fill('');
  await expect(page.locator('#qlst .card')).toHaveCount(2);
});

test('a hidden book moves to the hidden shelf and back', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Secret Diary', author: 'Me' }), epubFile({ title: 'Open Book', author: 'You' })], 2);
  await card(page, 'Secret Diary').click({ button: 'right' });
  await expect(page.locator('#qctx')).toBeVisible();
  await page.locator('#qcmh').click();
  await expect(page.locator('#qlst .card')).toHaveCount(1);
  await expect(card(page, 'Secret Diary')).toHaveCount(0);
  await page.locator('#qshf').click();
  await expect(page.locator('#qshf')).toHaveText('Hidden');
  await expect(page.locator('#qlst .card')).toHaveCount(1);
  await card(page, 'Secret Diary').click({ button: 'right' });
  await expect(page.locator('#qcmh')).toHaveText('Unhide');
  await page.locator('#qcmh').click();
  await expect(page.locator('#qlst .card')).toHaveCount(0);
  await expect(page.locator('#qelb')).toHaveText('No hidden books');
  await page.locator('#qshf').click();
  await page.locator('#qshf').click();
  await expect(page.locator('#qshf')).toHaveText('Library');
  await expect(page.locator('#qlst .card')).toHaveCount(2);
});

test('an archived book keeps its record, and is read again by importing it', async ({ page }) => {
  await start(page);
  const f = epubFile({ title: 'Old Volume', author: 'Past' });
  await importFiles(page, [f], 1);
  await card(page, 'Old Volume').click({ button: 'right' });
  await page.locator('#qcma').click();
  await expect(page.locator('#qlst .card')).toHaveCount(0);
  await page.locator('#qshf').click();
  await page.locator('#qshf').click();
  await expect(page.locator('#qshf')).toHaveText('Archived');
  await card(page, 'Old Volume').click();
  await expect(page.locator('#qmtt')).toHaveText('Archived');
  await page.locator('#qmb1').click();
  await expect(page.locator('#qrvw')).toBeHidden();
  // importing it again restores it to the shelf
  await page.locator('#qfin').setInputFiles([f]);
  await page.locator('#qshf').click();
  await expect(page.locator('#qshf')).toHaveText('Library');
  await expect(card(page, 'Old Volume')).toHaveCount(1);
  await openBook(page, 'Old Volume');
});

test('a deleted book is gone after a reload', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Doomed', author: 'X' }), epubFile({ title: 'Kept', author: 'Y' })], 2);
  await card(page, 'Doomed').click({ button: 'right' });
  await page.locator('#qcmd').click();
  await expect(page.locator('#qmtt')).toHaveText('Delete book?');
  await page.locator('#qmb2').click();
  await expect(page.locator('#qlst .card')).toHaveCount(1);
  await page.reload();
  await expect(page.locator('#qlst .card')).toHaveCount(1);
  await expect(card(page, 'Kept')).toHaveCount(1);
});

test('book info shows the book and its progress', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Info Book', author: 'Informant', rawChapters: chapters(2) })], 1);
  await card(page, 'Info Book').click({ button: 'right' });
  await page.locator('#qcmi').click();
  await expect(page.locator('#qinf')).toBeVisible();
  await expect(page.locator('#qint')).toHaveText('Info Book');
  await expect(page.locator('#qina')).toHaveText('Informant');
  await expect(page.locator('#qivl')).toHaveText('Never');
  await page.locator('#qinx').click();
  await expect(page.locator('#qinf')).toBeHidden();
});

test('a factory reset empties the library', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Ephemeral', author: 'Z' })], 1);
  await page.locator('#qlgr').click();
  await page.locator('#qlmr').click();
  await expect(page.locator('#qmtt')).toHaveText('Factory reset?');
  await page.locator('#qmb2').click();
  await expect(page.locator('#qibn')).toBeVisible();
  await expect(page.locator('#qlst .card')).toHaveCount(0);
  await expect(page.locator('#qelb')).toHaveText(/Import an EPUB file/);
});

test('dropping a file on the library imports it', async ({ page }) => {
  await start(page);
  const data = [...(await import('node:fs')).readFileSync(epubFile({ title: 'Dropped In', author: 'Gravity' }))];
  const dt = await page.evaluateHandle(bytes => {
    const dt = new DataTransfer();
    dt.items.add(new File([new Uint8Array(bytes)], 'dropped.epub', { type: 'application/epub+zip' }));
    return dt;
  }, data);
  await page.locator('#qllc').dispatchEvent('dragover', { dataTransfer: dt });
  await page.locator('#qllc').dispatchEvent('drop', { dataTransfer: dt });
  await expect(card(page, 'Dropped In')).toHaveCount(1, { timeout: 30000 });
});
