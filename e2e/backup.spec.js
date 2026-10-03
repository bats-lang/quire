// Backup and restore: the library's state in one JSON file, put back
// into the library, and kept for a book that comes back later.

import { test, expect } from './fixtures.js';
import { readFileSync, writeFileSync } from 'node:fs';
import {
  start, epubFile, rawFile, importFiles, card, cards, openBook, readBook, place, toLibrary,
  selectText, marks, chapters, dialog, menuItem, libraryMenu, bookMenu, importInput, openSettings,
  selectionButton, colours, bookPage, pagedBook, showChrome, control,
  librarySettings, settingsButton, restoreInput,
} from './helpers.js';

const restored = page => dialog(page, 'Backup restored');
const refused = page => dialog(page, 'Backup');
const bg = async page => (await colours(page)).bg.join(',');

async function exportBackup(page) {
  await librarySettings(page);
  const download = page.waitForEvent('download');
  await settingsButton(page, 'Export backup').click();
  const d = await download;
  expect(d.suggestedFilename()).toBe('quire-backup.json');
  await settingsButton(page, 'Done').click();
  return readFileSync(await d.path(), 'utf8');
}

async function restoreBackup(page, path) {
  await librarySettings(page);
  await restoreInput(page).setInputFiles([path]);
  await expect(page.getByRole('dialog')).toBeVisible();
}

// A reset with its Trash emptied: nothing of the library is left
async function factoryReset(page) {
  await librarySettings(page);
  await settingsButton(page, 'Factory reset').click();
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
  // the version of Quire that wrote it, as About shows it (#219)
  expect(b.appVersion).toMatch(/^\d{4}\.\d{1,2}\.\d{1,2}\.\d+ \([0-9a-f]{7,}\)$/);
  expect(b.settings).toMatchObject({
    size: 24, lineHeight: 16, margins: 2, font: 0, theme: 0, sort: 0,
    align: 0, hyphens: 1, paragraphSpacing: 8, letterSpacing: 0, wordSpacing: 10, dimImages: 1, tapZones: 0, volumeKeys: 0, ruby: 1,
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
  // the place as the book is left: justified text can move a page's
  // first paragraph to the page before
  await expect(page.getByRole('dialog', { name: 'Typography and theme' })).toBeHidden();
  const left = await place(page);
  expect(left.ch).toBe(at.ch);
  await toLibrary(page);
  const sepia = await bg(page);
  await bookMenu(page, 'Kept One');
  await menuItem(page, 'Hide').click();
  // the last sort order, Series
  const sort = page.getByRole('button', { name: /^Sort:/ });
  while (await sort.textContent() !== 'Sort: Series') await sort.click();
  const path = rawFile('quire-backup.json', await exportBackup(page));

  await factoryReset(page);
  expect(await bg(page)).not.toBe(sepia);
  // the library's order is its own, not a setting: changed by hand
  while (await sort.textContent() !== 'Sort: Title') await sort.click();
  // only book one comes back first
  await importFiles(page, [one], 1);
  await restoreBackup(page, path);
  await expect(restored(page)).toContainText('Books restored: 2');
  await restored(page).getByRole('button', { name: 'OK' }).click();
  await expect.poll(() => bg(page)).toBe(sepia);
  await expect(sort).toHaveText('Sort: Series');
  // book one is hidden again
  await expect(card(page, 'Kept One')).toHaveCount(0);
  // book two, imported after, takes its place and highlight back
  await importFiles(page, [two], 1);
  await openBook(page, 'Kept Two');
  expect(await place(page)).toEqual(left);
  await expect.poll(() => marks(page)).toEqual(hl);
  // in its style
  expect(await page.evaluate(() => CSS.highlights.has('bats-mark-3'))).toBe(true);
  // and the settings came back with the rest
  expect(await bookPage(page).locator('p').first().evaluate(e => getComputedStyle(e).textAlign)).toBe('justify');
});

test('a highlight\'s print page is in the backup, and a restore keeps it', async ({ page }) => {
  const errors = await start(page);
  const paged = pagedBook('Printed Backup', 'Print Tests');
  const file = epubFile(paged);
  await importFiles(page, [file], 1);
  await openBook(page, 'Printed Backup');
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  await selectText(page, 0, 8);
  await selectionButton(page, 'Highlight').click();
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(3);
  await selectText(page, 0, 8);
  await selectionButton(page, 'Highlight').click();
  await toLibrary(page);
  const json = await exportBackup(page);
  const [book] = JSON.parse(json).books;
  expect(book.annotations).toHaveLength(2);
  expect(book.annotations[0]).toMatchObject({ kind: 'highlight', chapter: 1, text: 'Para 2.0', printPage: '4' });
  // a highlight on no print page has no member for it
  expect(book.annotations[1]).toMatchObject({ kind: 'highlight', chapter: 2, text: 'Para 3.0' });
  expect(book.annotations[1]).not.toHaveProperty('printPage');
  const path = rawFile('quire-backup.json', json);

  await factoryReset(page);
  await importFiles(page, [file], 1);
  await restoreBackup(page, path);
  await expect(restored(page)).toContainText('Books restored: 1');
  await restored(page).getByRole('button', { name: 'OK' }).click();
  // the restored highlight cites its page in the export, and is in the
  // next backup with it
  await openBook(page, 'Printed Backup');
  await showChrome(page);
  await control(page, 'Annotations').click();
  const panel = dialog(page, 'Annotations');
  const download = page.waitForEvent('download');
  await panel.getByRole('button', { name: 'Export', exact: true }).click();
  const md = readFileSync(await (await download).path(), 'utf8');
  expect(md).toMatch(/> Para 2\.0\n\n— Print Tests, \*Printed Backup\*, [^\n]+, page 4\n/);
  expect(md).toMatch(/> Para 3\.0\n\n— Print Tests, \*Printed Backup\*, [^\n,]+\n/);
  await panel.getByRole('button', { name: 'Close' }).click();
  await toLibrary(page);
  const [again] = JSON.parse(await exportBackup(page)).books;
  expect(again.annotations[0]).toMatchObject({ text: 'Para 2.0', printPage: '4' });
  expect(errors).toEqual([]);
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

test('a backup holds the collections, and restoring it puts each book back in its own', async ({ page }) => {
  await start(page);
  const one = epubFile({ title: 'Grouped One', author: 'A' });
  const two = epubFile({ title: 'Grouped Two', author: 'B' });
  await importFiles(page, [one, two], 2);
  for (const [title, collection] of [['Grouped One', 'Poetry'], ['Grouped Two', 'Essays']]) {
    await bookMenu(page, title);
    await menuItem(page, 'Collections').click();
    await dialog(page, 'Collections').getByRole('button', { name: 'New collection' }).click();
    await dialog(page, 'New collection').getByRole('textbox', { name: 'Name' }).fill(collection);
    await dialog(page, 'New collection').getByRole('button', { name: 'Create' }).click();
    await dialog(page, 'Collections').getByRole('button', { name: 'Done' }).click();
  }
  const json = await exportBackup(page);
  const b = JSON.parse(json);
  expect(b.collections).toEqual(['Poetry', 'Essays']);
  expect(b.books.find(x => x.title === 'Grouped One').collections).toEqual([0]);
  expect(b.books.find(x => x.title === 'Grouped Two').collections).toEqual([1]);
  const path = rawFile('quire-backup.json', json);

  await factoryReset(page);
  await importFiles(page, [one, two], 2);
  await restoreBackup(page, path);
  await restored(page).getByRole('button', { name: 'OK' }).click();
  const row = page.getByRole('group', { name: 'Collection' });
  await row.getByRole('button', { name: 'Essays' }).click();
  await expect(cards(page)).toHaveCount(1);
  await expect(card(page, 'Grouped Two')).toHaveCount(1);
  await row.getByRole('button', { name: 'Poetry' }).click();
  await expect(card(page, 'Grouped One')).toHaveCount(1);
  await expect(cards(page)).toHaveCount(1);
});

// The Android app's plugins, each call kept; and a speech engine with
// voices (none says anything here)
async function deviceStubs(page) {
  await page.addInitScript(() => {
    window.calls = [];
    const call = name => a => { window.calls.push(name + (a ? ' ' + JSON.stringify(a) : '')); return Promise.resolve(); };
    window.Capacitor = { isNativePlatform: () => true, Plugins: {
      StatusBar: { hide: call('hide'), show: call('show') },
      ScreenOrientation: { lock: call('lock'), unlock: call('unlock') },
      ScreenBrightness: { setBrightness: call('brightness') },
    } };
    window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
    const voices = [
      { name: 'Reader', lang: 'en-US', voiceURI: 'reader-en', default: true },
      { name: 'Narrator', lang: 'en-GB', voiceURI: 'narrator-en', default: false },
    ];
    Object.defineProperty(window, 'speechSynthesis', { value: {
      getVoices: () => voices, speak() {}, cancel() {}, pause() {}, resume() {}, addEventListener() {},
    } });
  });
}

test('a backup holds reading aloud\'s speed and voices, the brightness and the rotation lock, and a restore puts them back', async ({ page }) => {
  await deviceStubs(page);
  await start(page);
  await readBook(page, { title: 'Device Backup', author: 'Keeper', rawChapters: chapters(1, 5) });
  await openSettings(page);
  const sheet = dialog(page, 'Typography and theme');
  await sheet.getByRole('combobox', { name: 'Reading speed' }).selectOption('1.5');
  await sheet.getByRole('combobox', { name: 'Voice' }).selectOption({ label: 'Narrator' });
  await sheet.getByRole('combobox', { name: 'Brightness' }).selectOption({ label: '25%' });
  await sheet.getByRole('button', { name: 'Lock rotation', exact: true }).click();
  await expect(sheet.getByRole('button', { name: 'Lock rotation', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');
  await toLibrary(page);
  const json = await exportBackup(page);
  const b = JSON.parse(json);
  expect(b.settings).toMatchObject({ readingSpeed: 150, brightness: 25, rotationLocked: true, voices: { en: 'Narrator' } });
  // reset, then restored
  await librarySettings(page);
  await settingsButton(page, 'Reset settings').click();
  await settingsButton(page, 'Done').click();
  await expect(page.getByRole('button', { name: 'Undo' })).toBeVisible();
  const reset = JSON.parse(await exportBackup(page));
  expect(reset.settings).toMatchObject({ readingSpeed: 100, brightness: 'system', rotationLocked: false, voices: {} });
  const path = rawFile('device-backup.json', json);
  await restoreBackup(page, path);
  await expect(restored(page)).toBeVisible();
  await restored(page).getByRole('button', { name: 'OK' }).click();
  await expect.poll(() => page.evaluate(() => window.calls.slice(-2))).toContain('brightness {"brightness":0.25}');
  await openBook(page, 'Device Backup');
  await openSettings(page);
  await expect(sheet.getByRole('combobox', { name: 'Reading speed' })).toHaveValue('1.5');
  await expect(sheet.getByRole('combobox', { name: 'Voice' }).locator('option:checked')).toHaveText('Narrator');
  await expect(sheet.getByRole('combobox', { name: 'Brightness' })).toHaveValue('25');
  await expect(sheet.getByRole('button', { name: 'Lock rotation', exact: true })).toHaveAttribute('aria-pressed', 'true');
});
