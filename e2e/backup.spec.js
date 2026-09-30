// Backup and restore: the library's state in one JSON file, put back
// into the library, and kept for a book that comes back later.

import { test, expect } from '@playwright/test';
import { readFileSync, writeFileSync } from 'node:fs';
import {
  start, epubFile, rawFile, importFiles, card, cards, openBook, readBook, place, toLibrary,
  selectText, marks, chapters, dialog, menuItem, libraryMenu, bookMenu, importInput, openSettings,
  selectionButton, colours, bookPage,
} from './helpers.js';

const restored = page => dialog(page, 'Backup restored');
const refused = page => dialog(page, 'Backup');
const bg = async page => (await colours(page)).bg.join(',');

async function exportBackup(page) {
  await libraryMenu(page);
  const download = page.waitForEvent('download');
  await menuItem(page, 'Export backup').click();
  const d = await download;
  expect(d.suggestedFilename()).toBe('quire-backup.json');
  return readFileSync(await d.path(), 'utf8');
}

async function restoreBackup(page, path) {
  await libraryMenu(page);
  await page.getByLabel('Import backup').setInputFiles([path]);
  await expect(page.getByRole('dialog')).toBeVisible();
}

// A reset with its Trash emptied: nothing of the library is left
async function factoryReset(page) {
  await libraryMenu(page);
  await menuItem(page, 'Factory reset').click();
  await expect(cards(page)).toHaveCount(0);
  await libraryMenu(page);
  await menuItem(page, 'Empty Trash').click();
  await dialog(page, 'Empty the Trash?').getByRole('button', { name: 'Empty' }).click();
  await expect(importInput(page)).toBeVisible();
  await expect(cards(page)).toHaveCount(0);
}

test('a backup holds the settings, the books, their places and annotations', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, { title: 'Backed "Up"', author: 'Keeper', rawChapters: chapters(2) });
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  await selectText(page, 0, 8);
  await selectionButton(page, 'Note').click();
  await dialog(page, 'Note').getByRole('textbox', { name: 'Note' }).fill('Line one\nwith "quotes" and ünïcode');
  await dialog(page, 'Note').getByRole('button', { name: 'Save' }).click();
  await selectText(page, 9, 14);
  await selectionButton(page, 'Underline').click();
  await openSettings(page);
  await page.getByRole('slider', { name: 'Size' }).fill('24');
  await page.getByRole('slider', { name: 'Word spacing' }).fill('10');
  await page.keyboard.press('Escape');
  await toLibrary(page);
  const json = await exportBackup(page);
  const b = JSON.parse(json);
  expect(b.quire).toBe(1);
  expect(b.settings).toMatchObject({
    size: 24, lineHeight: 16, margins: 2, font: 0, theme: 0, sort: 0,
    align: 0, hyphens: 1, paragraphSpacing: 8, letterSpacing: 0, wordSpacing: 10, dimImages: 1, tapZones: 0, volumeKeys: 0,
  });
  expect(b.books).toHaveLength(1);
  const book = b.books[0];
  expect(book).toMatchObject({ title: 'Backed "Up"', author: 'Keeper', shelf: 0, chapter: 0, chapters: 2, done: 0 });
  expect(book.id).toMatch(/^[0-9a-f]{14}$/);
  expect(book.pages).toBeGreaterThan(1);
  expect(book.annotations).toHaveLength(2);
  expect(book.annotations[0]).toMatchObject({ kind: 'highlight', style: 'yellow', chapter: 0, note: 'Line one\nwith "quotes" and ünïcode' });
  expect(book.annotations[1]).toMatchObject({ kind: 'highlight', style: 'underline', chapter: 0, text: 'lorem' });
  expect(errors).toEqual([]);
});

test('a backup restored after a reset brings everything back, and a book imported later takes its record', async ({ page }) => {
  await start(page);
  const one = epubFile({ title: 'Kept One', author: 'A', rawChapters: chapters(2) });
  const two = epubFile({ title: 'Kept Two', author: 'B', rawChapters: chapters(2, 20, 'Bpar') });
  await importFiles(page, [one, two], 2);
  await openBook(page, 'Kept Two');
  for (let k = 0; k < 3; k++) await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(4);
  const at = await place(page);
  await selectText(page, 0, 8);
  await selectionButton(page, 'Orange').click();
  const hl = await marks(page);
  await openSettings(page);
  const plain = await bg(page);
  await page.getByRole('button', { name: 'Sepia', exact: true }).click();
  await expect.poll(() => bg(page)).not.toBe(plain);
  await page.getByRole('button', { name: 'Justified', exact: true }).click();
  await page.keyboard.press('Escape');
  await toLibrary(page);
  const sepia = await bg(page);
  await bookMenu(page, 'Kept One');
  await menuItem(page, 'Hide').click();
  const path = rawFile('quire-backup.json', await exportBackup(page));

  await factoryReset(page);
  expect(await bg(page)).not.toBe(sepia);
  // only book one comes back first
  await importFiles(page, [one], 1);
  await restoreBackup(page, path);
  await expect(restored(page)).toContainText('Books restored: 2');
  await restored(page).getByRole('button', { name: 'OK' }).click();
  await expect.poll(() => bg(page)).toBe(sepia);
  // book one is hidden again
  await expect(card(page, 'Kept One')).toHaveCount(0);
  // book two, imported after, takes its place and highlight back
  await importFiles(page, [two], 1);
  await openBook(page, 'Kept Two');
  expect(await place(page)).toEqual(at);
  await expect.poll(() => marks(page)).toEqual(hl);
  // in its style
  expect(await page.evaluate(() => CSS.highlights.has('bats-mark-3'))).toBe(true);
  // and the settings came back with the rest
  expect(await bookPage(page).locator('p').first().evaluate(e => getComputedStyle(e).textAlign)).toBe('justify');
});

test('a file that is not a backup is refused with a message', async ({ page }) => {
  await start(page);
  await restoreBackup(page, rawFile('notes.json', Buffer.from('{"hello": [1, 2, 3]}')));
  await expect(refused(page)).toContainText('not a Quire backup');
  await refused(page).getByRole('button', { name: 'OK' }).click();
  await restoreBackup(page, rawFile('broken.json', Buffer.from('{"quire":1,"books":[{"id":"00')));
  await expect(refused(page)).toContainText('not a Quire backup');
});

test('the same backup can be restored twice in a row', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Twice Restored', author: 'R' })], 1);
  const path = rawFile('twice.json', await exportBackup(page));
  await restoreBackup(page, path);
  await restored(page).getByRole('button', { name: 'OK' }).click();
  await restoreBackup(page, path);
  await expect(restored(page)).toBeVisible();
});
