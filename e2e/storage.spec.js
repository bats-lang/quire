// A record that could not be read from storage is never taken for an
// empty one (#174): the banner says so, nothing is saved over it this
// session, and it is all there again once it can be read.

import { test, expect } from '@playwright/test';
import {
  start, readBook, toLibrary, openBook, chapters, reload, importFiles, epubFile, cards, card,
  selectText, selectionButton, marks, dialog, openSettings, bookPage, librarySearch,
  librarySettings, settingsButton,
} from './helpers.js';

const alert = page => page.getByRole('alert');

/** From the next load on, every IndexedDB read of a key that which
    names fails, as a read does when storage is failing: its request
    fires error. which is 'lib', 'set', or 'annotations' (a book's "a"
    record). The keys are kept in localStorage, so a reload keeps them
    failing until healReads */
async function failReads(page, which) {
  await page.evaluate(which => localStorage.setItem('failReads', which), which);
}

async function healReads(page) {
  await page.evaluate(() => localStorage.removeItem('failReads'));
}

/** Installed before every load: a read of a failing key errs */
async function stubReads(page) {
  await page.addInitScript(() => {
    const failing = key => {
      const which = localStorage.getItem('failReads');
      if (!which || typeof key !== 'string') return false;
      if (which === 'annotations') return key.length === 15 && key[0] === 'a';
      return key === which;
    };
    const get = IDBObjectStore.prototype.get;
    IDBObjectStore.prototype.get = function (key) {
      if (!failing(key)) return get.call(this, key);
      const request = { result: undefined, error: new DOMException('read failed', 'UnknownError') };
      setTimeout(() => { if (request.onerror) request.onerror(new Event('error')); });
      return request;
    };
  });
}

const libraryUnread = 'Quire could not read your library. Nothing will be saved until you reopen Quire, so your books and places are kept.';

test('a library that cannot be read is said, takes no book, and is not saved over', async ({ page }) => {
  await stubReads(page);
  await start(page);
  await importFiles(page, [epubFile({ title: 'Kept Safe', author: 'Storage Tests', rawChapters: chapters(1) })], 1);
  await failReads(page, 'lib');
  await reload(page);
  await expect(alert(page)).toContainText(libraryUnread);
  await expect(cards(page)).toHaveCount(0);
  // a book is not added: the library it would be saved in is not the one stored
  await alert(page).getByRole('button', { name: 'Dismiss' }).click();
  await page.getByLabel('Import EPUB').setInputFiles([epubFile({ title: 'Not Added', author: 'Storage Tests', rawChapters: chapters(1) })]);
  await expect(alert(page)).toContainText('Books cannot be added: Quire could not read your library. Reopen Quire to try again.');
  await expect(cards(page)).toHaveCount(0);
  // once it can be read, it is all there
  await healReads(page);
  await reload(page);
  await expect(cards(page)).toHaveCount(1);
  await expect(card(page, 'Kept Safe')).toBeVisible();
  await expect(alert(page)).toBeHidden();
});

test('a book\'s annotations that cannot be read are said, none is made, and none is lost', async ({ page }) => {
  await stubReads(page);
  await start(page);
  await readBook(page, { title: 'Marked Once', author: 'Storage Tests', rawChapters: chapters(2) });
  await selectText(page, 0, 8);
  await selectionButton(page, 'Highlight').click();
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'Para 1.0' });
  await toLibrary(page);
  await failReads(page, 'annotations');
  await reload(page);
  await openBook(page, 'Marked Once');
  await expect(alert(page)).toContainText('This book\'s highlights and notes could not be read. New ones cannot be made until you reopen Quire, so the old ones are kept.');
  await alert(page).getByRole('button', { name: 'Dismiss' }).click();
  // a highlight made now is not made (it could only be kept by saving
  // over the ones that could not be read)
  await selectText(page, 9, 17);
  await selectionButton(page, 'Highlight').click();
  await expect.poll(() => marks(page)).toEqual({ size: 0, text: '' });
  // the place is still kept, and the old highlight is there once read
  await page.keyboard.press('ArrowRight');
  await toLibrary(page);
  await healReads(page);
  await reload(page);
  await openBook(page, 'Marked Once');
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'Para 1.0' });
  await expect(alert(page)).toBeHidden();
});

test('settings that cannot be read are said, the defaults used, and not saved over', async ({ page }) => {
  await stubReads(page);
  await start(page);
  await readBook(page, { title: 'Set Once', author: 'Storage Tests', rawChapters: chapters(1) });
  const sheet = dialog(page, 'Typography and theme');
  const fontSize = () => bookPage(page).locator('p').first().evaluate(e => getComputedStyle(e).fontSize);
  await openSettings(page);
  await sheet.getByRole('slider', { name: 'Size' }).fill('28');
  await expect.poll(fontSize).toBe('28px');
  await sheet.getByRole('button', { name: 'Close', exact: true }).click();
  await toLibrary(page);
  await failReads(page, 'set');
  await reload(page);
  await expect(alert(page)).toContainText('Quire could not read your settings. It is using the defaults, and changes will not be saved until you reopen Quire.');
  await alert(page).getByRole('button', { name: 'Dismiss' }).click();
  await openBook(page, 'Set Once');
  await expect.poll(fontSize).toBe('18px');
  // a change now is used, but not saved over the settings stored
  await openSettings(page);
  await sheet.getByRole('slider', { name: 'Size' }).fill('14');
  await expect.poll(fontSize).toBe('14px');
  await sheet.getByRole('button', { name: 'Close', exact: true }).click();
  await toLibrary(page);
  await healReads(page);
  await reload(page);
  await expect(librarySearch(page)).toBeVisible();
  await openBook(page, 'Set Once');
  await expect.poll(fontSize).toBe('28px');
});

test('a backup that could not read a book\'s notes is not made', async ({ page }) => {
  await stubReads(page);
  await start(page);
  await readBook(page, { title: 'Noted', author: 'Storage Tests', rawChapters: chapters(1) });
  await selectText(page, 0, 8);
  await selectionButton(page, 'Highlight').click();
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'Para 1.0' });
  await toLibrary(page);
  await failReads(page, 'annotations');
  let downloaded = false;
  page.on('download', () => { downloaded = true; });
  await librarySettings(page);
  await settingsButton(page, 'Export backup').click();
  const said = dialog(page, 'Backup');
  await expect(said).toContainText('The backup could not be made: a book\'s notes could not be read. Try again.');
  await said.getByRole('button', { name: 'OK' }).click();
  expect(downloaded).toBe(false);
});

// Reading aloud's speed is kept in the settings record (bytes 20 on),
// so it follows the settings' flag: not saved over settings that could
// not be read
test('reading aloud\'s speed is not saved over settings that cannot be read', async ({ page }) => {
  await stubReads(page);
  await page.addInitScript(() => {
    window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
    const voices = [{ name: 'Reader', lang: 'en-US', voiceURI: 'reader-en', default: true }];
    const synth = { getVoices: () => voices, speak() {}, cancel() {}, addEventListener() {} };
    Object.defineProperty(window, 'speechSynthesis', { value: synth });
  });
  await start(page);
  await readBook(page, { title: 'Spoken Once', author: 'Storage Tests', rawChapters: chapters(1) });
  const sheet = dialog(page, 'Typography and theme');
  const speed = sheet.getByRole('combobox', { name: 'Reading speed' });
  await openSettings(page);
  await speed.selectOption('1.5');
  await sheet.getByRole('button', { name: 'Close', exact: true }).click();
  await toLibrary(page);
  await failReads(page, 'set');
  await reload(page);
  await expect(alert(page)).toContainText('Quire could not read your settings.');
  await alert(page).getByRole('button', { name: 'Dismiss' }).click();
  await openBook(page, 'Spoken Once');
  await openSettings(page);
  await expect(speed).toHaveValue('1');
  // a change now is used, but not saved over the settings stored
  await speed.selectOption('2');
  await sheet.getByRole('button', { name: 'Close', exact: true }).click();
  await toLibrary(page);
  await healReads(page);
  await reload(page);
  await expect(librarySearch(page)).toBeVisible();
  await openBook(page, 'Spoken Once');
  await openSettings(page);
  await expect(speed).toHaveValue('1.5');
});
