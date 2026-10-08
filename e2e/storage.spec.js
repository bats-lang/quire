// A record that could not be read from storage is never taken for an
// empty one (#174): the banner says so, nothing is saved over it this
// session, and it is all there again once it can be read.

import { test, expect } from './fixtures.js';
import {
  start, readBook, toLibrary, openBook, chapters, reload, importFiles, epubFile, cards, card,
  selectText, selectionButton, marks, dialog, openSettings, bookPage, librarySearch,
  librarySettings, settingsButton,
  readingSettings, openReadingSettings,
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

/** The library's records are read together, by their prefix (#354).
    From the next load on, that read fails with a DOMException named
    name, as a browser's does (bridge reads the name, #374): for the next
    times reads (every one when times is -1). The count is kept in
    localStorage, so a reload carries it on */
async function failLibrary(page, name, times = -1) {
  await page.evaluate(([name, times]) => {
    localStorage.setItem('failReads', 'lib');
    localStorage.setItem('failName', name);
    localStorage.setItem('failLeft', String(times));
  }, [name, times]);
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
    const erring = () => {
      const request = { result: undefined, error: new DOMException('read failed', 'UnknownError') };
      setTimeout(() => { if (request.onerror) request.onerror(new Event('error')); });
      return request;
    };
    const get = IDBObjectStore.prototype.get;
    IDBObjectStore.prototype.get = function (key) {
      return failing(key) ? erring() : get.call(this, key);
    };
    // the library's records are read together, by their prefix (#354)
    const getAll = IDBObjectStore.prototype.getAll;
    IDBObjectStore.prototype.getAll = function (range, ...rest) {
      const lower = range && typeof range.lower === 'string' ? range.lower : '';
      if (lower.startsWith('library/') && localStorage.getItem('failReads') === 'lib') {
        const left = Number(localStorage.getItem('failLeft') ?? '-1');
        if (left !== 0) {
          if (left > 0) localStorage.setItem('failLeft', String(left - 1));
          // the browser's own error, named as the specification names it
          throw new DOMException('the library could not be read', localStorage.getItem('failName') ?? 'UnknownError');
        }
      }
      return getAll.call(this, range, ...rest);
    };
  });
}

const libraryScreen = page => page.locator('#library-empty');
const tryAgain = page => page.getByRole('button', { name: 'Try again' });
const clipboard = page => page.evaluate(() => navigator.clipboard.readText());
const ALWAYS = 'Quire has not changed anything and will not save until it can read your library.';

/** The library is unreadable: its text, no offer to import, Import off */
async function expectUnreadable(page, text) {
  await expect(libraryScreen(page)).toBeVisible();
  await expect(libraryScreen(page)).toContainText(text);
  await expect(libraryScreen(page)).toContainText(ALWAYS);
  await expect(page.getByText('Import an EPUB', { exact: false })).toHaveCount(0);
  await expect(page.locator('#import-file')).toHaveAttribute('inert', '');
}

test('a library that cannot be read is said, takes no book, and is not saved over', async ({ page }) => {
  await stubReads(page);
  await start(page);
  await importFiles(page, [epubFile({ title: 'Kept Safe', author: 'Storage Tests', rawChapters: chapters(1) })], 1);
  await failLibrary(page, 'SecurityError');
  await reload(page);
  await expect(alert(page)).toContainText('Quire could not read your library.');
  await expectUnreadable(page, 'Your browser is not letting Quire use its storage');
  await expect(cards(page)).toHaveCount(0);
  // a book is not added: the library it would be saved in is not the one stored
  await alert(page).getByRole('button', { name: 'Dismiss' }).click();
  await page.getByLabel('Import EPUB').setInputFiles([epubFile({ title: 'Not Added', author: 'Storage Tests', rawChapters: chapters(1) })]);
  await expect(alert(page)).toContainText('Books cannot be added until Quire can read your library.');
  await expect(cards(page)).toHaveCount(0);
  // once it can be read, it is all there
  await healReads(page);
  await reload(page);
  await expect(cards(page)).toHaveCount(1);
  await expect(card(page, 'Kept Safe')).toBeVisible();
  await expect(alert(page)).toBeHidden();
  await expect(page.locator('#import-file')).not.toHaveAttribute('inert', '');
});

// What the screen says and offers depends on why the read failed (#374)
const WHY = [
  ['UnknownError', 'Quire could not read your library this time.', true],
  ['SecurityError', 'Your browser is not letting Quire use its storage (a private window, or site data blocked). Allow site data for this address, or leave the private window, then reopen Quire.', false],
  ['VersionError', 'This device holds data from a newer version of Quire. Update Quire.', false],
  // AbortError has no hope: nothing says an abort is transient (see unreadable.bats)
  ['AbortError', 'The browser stopped Quire\'s read of your library. Reopen Quire to read it again.', false],
];
for (const [name, text, hope] of WHY) {
  test(`a library read that fails with ${name} says so${hope ? ' and offers Try again' : ', with no button'}`, async ({ page }) => {
    await stubReads(page);
    await start(page);
    await importFiles(page, [epubFile({ title: 'Kept Safe', author: 'Storage Tests', rawChapters: chapters(1) })], 1);
    await failLibrary(page, name);
    await reload(page);
    await expectUnreadable(page, text);
    await expect(alert(page)).toContainText('Quire could not read your library.');
    await expect(alert(page).getByRole('button', { name: 'Copy details' })).toBeVisible();
    await expect(alert(page).getByRole('link', { name: 'Report' })).toBeVisible();
    if (hope) await expect(tryAgain(page)).toBeVisible();
    else await expect(tryAgain(page)).toBeHidden();
  });
}

test('a name the specification does not list is an unexpected error, with the name in the details', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await stubReads(page);
  await start(page);
  await importFiles(page, [epubFile({ title: 'Kept Safe', author: 'Storage Tests', rawChapters: chapters(1) })], 1);
  await failLibrary(page, 'WeirdBrowserError');
  await reload(page);
  await expectUnreadable(page, 'An unexpected error stopped Quire from reading your library.');
  await expect(tryAgain(page)).toBeHidden();
  await expect(alert(page)).toContainText('An unexpected error occurred while reading your library.');
  await page.evaluate(() => navigator.clipboard.writeText(''));
  await alert(page).getByRole('button', { name: 'Copy details' }).click();
  await expect(page.getByText('Copied', { exact: true })).toBeVisible();
  await expect.poll(() => clipboard(page)).toContain('WeirdBrowserError\nthe library could not be read');
});

test('Try again reads the library once more: the books show, and a later change is saved', async ({ page }) => {
  await stubReads(page);
  await start(page);
  await importFiles(page, [epubFile({ title: 'Kept Safe', author: 'Storage Tests', rawChapters: chapters(1) })], 1);
  await failLibrary(page, 'UnknownError', 1);
  await reload(page);
  await expectUnreadable(page, 'Quire could not read your library this time.');
  await tryAgain(page).click();
  await expect(card(page, 'Kept Safe')).toBeVisible();
  await expect(tryAgain(page)).toBeHidden();
  await expect(alert(page)).toBeHidden();
  await expect(libraryScreen(page)).toBeHidden();
  await expect(page.locator('#import-file')).not.toHaveAttribute('inert', '');
  // saving works again: a book added now is there after a reload
  await importFiles(page, [epubFile({ title: 'Added After', author: 'Storage Tests', rawChapters: chapters(1) })], 2);
  await healReads(page);
  await reload(page);
  await expect(cards(page)).toHaveCount(2);
  await expect(card(page, 'Kept Safe')).toBeVisible();
  await expect(card(page, 'Added After')).toBeVisible();
});

test('Try again is one retry: when it fails too, the button is gone for the session', async ({ page }) => {
  await stubReads(page);
  await start(page);
  await importFiles(page, [epubFile({ title: 'Kept Safe', author: 'Storage Tests', rawChapters: chapters(1) })], 1);
  await failLibrary(page, 'UnknownError', 2);
  await reload(page);
  await expectUnreadable(page, 'Quire could not read your library this time.');
  await tryAgain(page).click();
  await expectUnreadable(page, 'Quire still could not read your library after trying again.');
  await expect(tryAgain(page)).toBeHidden();
  await expect(alert(page)).toContainText('Quire could not read your library.');
  await expect(cards(page)).toHaveCount(0);
  // nothing was saved over it: it is all there once it can be read
  await healReads(page);
  await reload(page);
  await expect(card(page, 'Kept Safe')).toBeVisible();
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
  const sheet = dialog(page, 'Reading settings');
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
  const sheet = readingSettings(page);
  const speed = sheet.getByRole('combobox', { name: 'Reading speed' });
  await openReadingSettings(page, 'Read aloud');
  await speed.selectOption('1.5');
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await failReads(page, 'set');
  await reload(page);
  await expect(alert(page)).toContainText('Quire could not read your settings.');
  await alert(page).getByRole('button', { name: 'Dismiss' }).click();
  await openBook(page, 'Spoken Once');
  await openReadingSettings(page, 'Read aloud');
  await expect(speed).toHaveValue('1');
  // a change now is used, but not saved over the settings stored
  await speed.selectOption('2');
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await healReads(page);
  await reload(page);
  await expect(librarySearch(page)).toBeVisible();
  await openBook(page, 'Spoken Once');
  await openReadingSettings(page, 'Read aloud');
  await expect(speed).toHaveValue('1.5');
});
