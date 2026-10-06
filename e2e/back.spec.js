// Back, Android's and the browser's (quire#333): one step back from
// wherever the reader is, as Android's back stack goes. The dialog is
// answered No, else the overlay on top closes (Sync goes back to
// Settings, Settings to what was under it), else the book goes back to
// the library; at the library with nothing open the app goes to the
// background (Android 12's own Back at an app's root) and a browser
// leaves the page. In the android project Back is the App plugin's
// backButton (fixtures.js plays it); elsewhere the browser's history.

import { test, expect, onAndroid } from './fixtures.js';
import {
  start, epubFile, importFiles, readBook, chapters, bookPage, libraryMenu, menuItem, dialog,
  librarySettings, settingsScreen, settingsButton, bookMenu, librarySearch, openReadingSettings,
  readingSettings, card,
} from './helpers.js';
import { walkEveryScreen, appPlayed } from './walk.js';

/** The overlays shown: each dialog and menu (by id, else name) */
const overlaysShown = page => page.evaluate(() => [...document.querySelectorAll('[role=dialog],[role=alertdialog],[role=menu]')]
  .filter(e => e.checkVisibility() && e.getClientRects().length > 0)
  .map(e => e.id || e.getAttribute('aria-label')).sort());

/** Presses Back: Android's (the App plugin's backButton) in the
    android project, the browser's elsewhere */
async function pressBack(page, testInfo) {
  if (onAndroid(testInfo)) await page.evaluate(() => window.__android.back());
  else await page.goBack();
}

/** How many times the app moved itself to the background */
const minimized = page => page.evaluate(() => window.__android.calls.filter(c => c.plugin === 'App' && c.method === 'minimizeApp').length);

/** Presses Back and expects exactly one step back: one overlay fewer,
    the others still there (and the book still open under them), or,
    with none open in the reader, the library; or, for a step within a
    screen (within says which), the same overlays still open (the walk
    checks the screen is back where it was) */
async function stepBack(page, testInfo, within) {
  const before = await overlaysShown(page);
  const reading = await bookPage(page).isVisible();
  await pressBack(page, testInfo);
  if (within) {
    await expect.poll(() => overlaysShown(page), `one step back from ${within}`).toEqual(before);
  } else if (before.length > 0) {
    await expect.poll(() => overlaysShown(page).then(shown => shown.length), `one step back from ${before}`).toBe(before.length - 1);
    expect(before, `one step back from ${before}`).toEqual(expect.arrayContaining(await overlaysShown(page)));
    if (reading) await expect(bookPage(page)).toBeVisible();
  } else {
    expect(reading, 'Back pressed with nothing to go back from').toBe(true);
    await expect(librarySearch(page)).toBeVisible();
    await expect(bookPage(page)).toBeHidden();
  }
}

/** Back at the library with nothing open: the app to the background
    (and still at the library when it comes back), or the browser off
    the page */
async function backAtRoot(page, testInfo) {
  expect(await overlaysShown(page)).toEqual([]);
  if (onAndroid(testInfo)) {
    const before = await minimized(page);
    await pressBack(page, testInfo);
    await expect.poll(() => minimized(page)).toBe(before + 1);
    await expect(librarySearch(page)).toBeVisible();
  } else {
    await pressBack(page, testInfo);
    await expect.poll(() => page.url()).toBe('about:blank');
  }
}

// Every screen, sheet, menu and dialog the layout's walk opens (so one
// added there is covered here), each left by Back, one step at a time;
// then the book, and the library
test('Back goes exactly one step back from every screen, sheet, menu and dialog, then leaves at the library', async ({ page }, testInfo) => {
  test.setTimeout(240000);
  // the app's own screen rows, as the layout's walk shows them (the
  // android project has the app's Capacitor already)
  if (!onAndroid(testInfo)) await page.addInitScript(appPlayed);
  await walkEveryScreen(page, { look: async () => {}, back: within => stepBack(page, testInfo, within) });
  await stepBack(page, testInfo);
  await backAtRoot(page, testInfo);
});

test('Back from About goes back to the library, and from there leaves', async ({ page }, testInfo) => {
  const errors = await start(page);
  await libraryMenu(page);
  await menuItem(page, 'About Quire').click();
  await expect(dialog(page, 'About Quire')).toBeVisible();
  await pressBack(page, testInfo);
  await expect(dialog(page, 'About Quire')).toBeHidden();
  await expect(librarySearch(page)).toBeVisible();
  expect(errors).toEqual([]);
  await backAtRoot(page, testInfo);
});

test('Back from Settings › Sync goes back to Settings, then to the library', async ({ page }, testInfo) => {
  const errors = await start(page);
  await librarySettings(page);
  await settingsButton(page, 'Sync ›').click();
  const sync = page.getByRole('dialog', { name: 'Sync', exact: true });
  await expect(sync).toBeVisible();
  await pressBack(page, testInfo);
  await expect(sync).toBeHidden();
  await expect(settingsScreen(page)).toBeVisible();
  await pressBack(page, testInfo);
  await expect(settingsScreen(page)).toBeHidden();
  await expect(librarySearch(page)).toBeVisible();
  expect(errors).toEqual([]);
});

test('Back closes a sheet over the book, then leaves the book for the library', async ({ page }, testInfo) => {
  const errors = await start(page);
  await readBook(page, { title: 'Sheets', author: 'B', rawChapters: chapters(2) });
  await openReadingSettings(page, 'Look');
  await expect(readingSettings(page)).toBeVisible();
  await pressBack(page, testInfo);
  await expect(readingSettings(page)).toBeHidden();
  await expect(bookPage(page)).toBeVisible();
  await pressBack(page, testInfo);
  await expect(librarySearch(page)).toBeVisible();
  await expect(bookPage(page)).toBeHidden();
  expect(errors).toEqual([]);
});

test('Back answers a dialog No: the Trash is not emptied', async ({ page }, testInfo) => {
  const errors = await start(page);
  await importFiles(page, [epubFile({ title: 'Kept From The Trash', author: 'B' })], 1);
  await bookMenu(page, 'Kept From The Trash');
  await menuItem(page, 'Move to Trash').click();
  await libraryMenu(page);
  await menuItem(page, 'Empty Trash').click();
  const asked = dialog(page, 'Empty the Trash?');
  await expect(asked).toBeVisible();
  await pressBack(page, testInfo);
  await expect(asked).toBeHidden();
  // the shelf button goes round the shelves: Library, Hidden, Archived, Trash
  const shelf = page.getByRole('button', { name: /^(Library|Hidden|Archived|Trash)$/ });
  for (let i = 0; i < 3; i++) await shelf.click();
  await expect(shelf).toHaveText('Trash');
  await expect(card(page, 'Kept From The Trash')).toHaveCount(1);
  expect(errors).toEqual([]);
});

// A screen closed by its own button leaves nothing for Back to take: at
// the library the next Back leaves at once
test('after a screen is closed by its own button, Back at the library leaves at once', async ({ page }, testInfo) => {
  const errors = await start(page);
  await librarySettings(page);
  await settingsButton(page, 'Done').click();
  await expect(settingsScreen(page)).toBeHidden();
  await readBook(page, { title: 'Closed By Its Button', author: 'B', rawChapters: chapters(1) });
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await expect(librarySearch(page)).toBeVisible();
  expect(errors).toEqual([]);
  await backAtRoot(page, testInfo);
});
