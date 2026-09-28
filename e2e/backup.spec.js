// Backup and restore: the library's state in one JSON file, put back
// into the library, and kept for a book that comes back later.

import { test, expect } from '@playwright/test';
import { readFileSync, writeFileSync } from 'node:fs';
import {
  start, epubFile, rawFile, importFiles, card, openBook, readBook, place, showChrome, toLibrary,
  selectText, marks, chapters,
} from './helpers.js';

async function exportBackup(page) {
  await page.locator('#qlgr').click();
  const download = page.waitForEvent('download');
  await page.locator('#qlme').click();
  const d = await download;
  expect(d.suggestedFilename()).toBe('quire-backup.json');
  return readFileSync(await d.path(), 'utf8');
}

async function restoreBackup(page, path) {
  await page.locator('#qlgr').click();
  await page.locator('#qbfi').setInputFiles([path]);
  await expect(page.locator('#qmod')).toBeVisible();
}

async function factoryReset(page) {
  await page.locator('#qlgr').click();
  await page.locator('#qlmr').click();
  await page.locator('#qmb2').click();
  await expect(page.locator('#qibn')).toBeVisible();
  await expect(page.locator('#qlst .card')).toHaveCount(0);
}

test('a backup holds the settings, the books, their places and annotations', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, { title: 'Backed "Up"', author: 'Keeper', rawChapters: chapters(2) });
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  await selectText(page, '#qcnt p', 0, 8);
  await page.locator('#qsln').click();
  await page.locator('#qmta').fill('Line one\nwith "quotes" and ünïcode');
  await page.locator('#qmb2').click();
  await showChrome(page);
  await page.locator('#qset').click();
  await page.locator('#qfsr').fill('24');
  await page.keyboard.press('Escape');
  await toLibrary(page);
  const json = await exportBackup(page);
  const b = JSON.parse(json);
  expect(b.quire).toBe(1);
  expect(b.settings).toMatchObject({ size: 24, lineHeight: 16, margins: 2, font: 0, theme: 0, sort: 0 });
  expect(b.books).toHaveLength(1);
  const book = b.books[0];
  expect(book).toMatchObject({ title: 'Backed "Up"', author: 'Keeper', shelf: 0, chapter: 0, chapters: 2, done: 0 });
  expect(book.id).toMatch(/^[0-9a-f]{14}$/);
  expect(book.pages).toBeGreaterThan(1);
  expect(book.annotations).toHaveLength(1);
  expect(book.annotations[0]).toMatchObject({ kind: 'highlight', chapter: 0, note: 'Line one\nwith "quotes" and ünïcode' });
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
  await selectText(page, '#qcnt p', 0, 8);
  await page.locator('#qslh').click();
  const hl = await marks(page, 1);
  await showChrome(page);
  await page.locator('#qset').click();
  await page.locator('#qth2').click();
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await card(page, 'Kept One').click({ button: 'right' });
  await page.locator('#qcmh').click();
  const path = rawFile('quire-backup.json', await exportBackup(page));

  await factoryReset(page);
  await expect(page.locator('#bats-root')).not.toHaveClass(/th-sepia/);
  // only book one comes back first
  await importFiles(page, [one], 1);
  await restoreBackup(page, path);
  await expect(page.locator('#qmtt')).toHaveText('Backup restored');
  await expect(page.locator('#qmtx')).toHaveText('Books restored: 2');
  await page.locator('#qmb1').click();
  await expect(page.locator('#bats-root')).toHaveClass(/th-sepia/);
  // book one is hidden again
  await expect(card(page, 'Kept One')).toHaveCount(0);
  // book two, imported after, takes its place and highlight back
  await importFiles(page, [two], 1);
  await openBook(page, 'Kept Two');
  expect(await place(page)).toEqual(at);
  await expect.poll(() => marks(page, 1)).toEqual(hl);
});

test('a file that is not a backup is refused with a message', async ({ page }) => {
  await start(page);
  await restoreBackup(page, rawFile('notes.json', Buffer.from('{"hello": [1, 2, 3]}')));
  await expect(page.locator('#qmtx')).toContainText('not a Quire backup');
  await page.locator('#qmb1').click();
  await restoreBackup(page, rawFile('broken.json', Buffer.from('{"quire":1,"books":[{"id":"00')));
  await expect(page.locator('#qmtx')).toContainText('not a Quire backup');
});

test('the same backup can be restored twice in a row', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Twice Restored', author: 'R' })], 1);
  const path = rawFile('twice.json', await exportBackup(page));
  await restoreBackup(page, path);
  await page.locator('#qmb1').click();
  await restoreBackup(page, path);
  await expect(page.locator('#qmtt')).toHaveText('Backup restored');
});
