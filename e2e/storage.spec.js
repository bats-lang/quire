// A record that could not be read from storage is never taken for an
// empty one (#174): the banner says so, nothing is saved over it this
// session, and it is all there again once it can be read.

import { test, expect } from './fixtures.js';
import {
  start, readBook, toLibrary, openBook, chapters, reload, importFiles, epubFile, cards, card,
  selectText, selectionButton, marks, dialog, openSettings, bookPage, librarySearch,
  librarySettings, libraryMenu, menuItem, settingsButton,
  readingSettings, openReadingSettings, showChrome, settingsScreen, pageShown,
} from './helpers.js';
import { webdav, folder, USER, PASSWORD } from './sync-stores.js';
import { coveredByBanner } from './controls-shown.js';
import { failReads, healReads, failLibrary, stubReads } from './storage-stub.js';

const alert = page => page.getByRole('alert');

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
  await expectUnreadable(page, 'Your browser is not letting Quire use its storage');
  await expect(alert(page)).toBeHidden();
  await expect(cards(page)).toHaveCount(0);
  // a book is not added: the library it would be saved in is not the one stored
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
    // the screen says it all, with the browser's name for it, and no
    // banner can cover Try again
    await expect(libraryScreen(page)).toContainText(`Details: ${name}.`);
    await expect(alert(page)).toBeHidden();
    expect(await coveredByBanner(page)).toEqual([]);
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
  await expect(alert(page)).toBeHidden();
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

// #374's leftovers

// The error banner is fixed at the top over the reader; with the bars up
// it must sit under the top bar (Material 3 puts a banner under the top
// app bar), and clear of the bottom bar
test('the error banner over the reader covers neither of its bars', async ({ page }) => {
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
  await expect(alert(page)).toBeVisible();
  await showChrome(page);
  await expect(page.locator('#reader-top-bar')).toBeVisible();
  await expect(page.locator('#reader-bottom-bar')).toBeVisible();
  expect(await coveredByBanner(page, '#reader-top-bar')).toEqual([]);
  expect(await coveredByBanner(page, '#reader-bottom-bar')).toEqual([]);
});

// The details of an unexpected failure outlive its banner: About copies them
test('the details of an unexpected error can still be copied from About after the banner is dismissed', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await stubReads(page);
  await start(page);
  // no failure yet, no row
  await libraryMenu(page);
  await menuItem(page, 'About Quire').click();
  await expect(page.getByRole('button', { name: 'Copy last error details' })).toBeHidden();
  await failLibrary(page, 'WeirdBrowserError');
  await reload(page);
  await expect(alert(page)).toContainText('An unexpected error occurred');
  await alert(page).getByRole('button', { name: 'Dismiss' }).click();
  await expect(alert(page)).toBeHidden();
  await libraryMenu(page);
  await menuItem(page, 'About Quire').click();
  await page.evaluate(() => navigator.clipboard.writeText(''));
  await page.getByRole('button', { name: 'Copy last error details' }).click();
  await expect(page.getByText('Copied', { exact: true })).toBeVisible();
  await expect.poll(() => clipboard(page)).toContain('WeirdBrowserError\nthe library could not be read');
});

// With the first read failed (with hope), what waits for the read (the
// sync and the stored view) waits for the retry, and runs when it ends
test('a sync and the stored view wait for Try again, and happen once the library is read', async ({ page, context }) => {
  const server = webdav();
  await context.route('**/dav/books/quire-sync.json', server.handle);
  await stubReads(page);
  await start(page);
  await importFiles(page, [epubFile({ title: 'Kept Safe', author: 'Storage Tests', rawChapters: chapters(2) })], 1);
  await librarySettings(page);
  await settingsButton(page, 'Sync').click();
  const panel = dialog(page, 'Sync');
  await panel.getByRole('button', { name: 'WebDAV', exact: true }).click();
  await panel.getByLabel('Folder URL').fill(folder(page));
  await panel.getByLabel('User name').fill(USER);
  await panel.getByLabel('Password', { exact: true }).fill(PASSWORD);
  await panel.getByRole('button', { name: 'Sign in to WebDAV' }).click();
  await expect(panel.getByRole('status')).toHaveText(/^Last synced on /);
  await panel.getByRole('button', { name: 'Done' }).click();
  await settingsButton(page, 'Done').click();
  await expect(settingsScreen(page)).toBeHidden();
  // a book open, so the view kept is that book
  await openBook(page, 'Kept Safe');
  await failLibrary(page, 'UnknownError', 1);
  await reload(page);
  await expectUnreadable(page, 'Quire could not read your library this time.');
  const before = server.gets;
  await page.waitForTimeout(1500);
  expect(server.gets, 'no sync before the library is read').toBe(before);
  await expect(bookPage(page)).toBeHidden();
  await tryAgain(page).click();
  await expect.poll(() => server.gets, 'the sync runs once the retry ends').toBeGreaterThan(before);
  await pageShown(page);
});

// Import is off while the library cannot be read, and looks it
test('Import looks disabled while the library cannot be read', async ({ page }) => {
  await stubReads(page);
  await start(page);
  const look = () => page.locator('#import-button').evaluate(e => {
    const s = getComputedStyle(e);
    return { background: s.backgroundColor, color: s.color, cursor: s.cursor, height: e.getBoundingClientRect().height };
  });
  const readable = await look();
  expect(readable.cursor).not.toBe('not-allowed');
  await failLibrary(page, 'SecurityError');
  await reload(page);
  await expectUnreadable(page, 'Your browser is not letting Quire use its storage');
  const off = await look();
  expect(off.cursor).toBe('not-allowed');
  expect(off.background).not.toBe(readable.background);
  expect(off.color).not.toBe(readable.color);
  // the same size, and its text still readable (muted on the card is proven 4.5:1)
  expect(off.height).toBe(readable.height);
});
