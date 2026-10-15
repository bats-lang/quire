// The Settings screen: opened from the library menu, it holds what the
// library menu used to (sync, the dictionaries, the backup, the resets)
// and the daily reading goal. Each complex area is a screen of its own,
// opened from its row, and Escape closes the screen on top, then
// Settings. In a book, the reading settings sheet is the one place
// (#342).

import { test, expect, onAndroid } from './fixtures.js';
import { toastClear, rowIsTarget } from './controls-shown.js';
import { readFileSync, writeFileSync } from 'node:fs';
import {
  start, epubFile, importFiles, cards, card, openBook, readBook, toLibrary, chapters, dialog, menuItem, libraryMenu,
  openSettings, colours, showChrome, librarySearch, bookPage, topBar, openReadingSettings, readingSettings,
  settingsScreen, settingsButton, librarySettings, restoreInput, exportedBackup, libraryShown,
} from './helpers.js';

const bg = async page => (await colours(page)).bg.join(',');
const undo = page => page.getByRole('button', { name: 'Undo' });
const syncRow = page => settingsScreen(page).getByRole('group', { name: 'Sync' });
const goal = page => settingsScreen(page).getByRole('group', { name: 'Daily reading goal' });

test('Settings opens from the library menu, which no longer holds what it took', async ({ page }) => {
  const errors = await start(page);
  await libraryMenu(page);
  for (const gone of ['Dictionaries', 'Export backup', 'Import backup', 'Restore backup', 'Reset reading settings', 'Remove all books']) {
    await expect(menuItem(page, gone)).toHaveCount(0);
  }
  await expect(page.getByRole('menu').getByLabel('Restore backup')).toHaveCount(0);
  // Empty Trash is on the Trash's own screen, not here (quire#385)
  await expect(menuItem(page, 'Empty Trash')).toHaveCount(0);
  // Sync is two taps from the library (#501); the rest of what Settings holds is not in the menu
  await expect(menuItem(page, 'Sync')).toBeVisible();
  await expect(menuItem(page, 'Reading statistics')).toBeVisible();
  await expect(menuItem(page, 'Catalogues')).toBeVisible();
  await menuItem(page, 'Settings').click();
  await expect(settingsScreen(page)).toBeVisible();
  await expect(page.getByRole('menu')).toBeHidden();
  for (const row of ['Sync', 'Dictionaries', 'Export backup', 'Reset reading settings', 'Remove all books', 'Back']) {
    await expect(settingsButton(page, row)).toBeVisible();
  }
  // the reading settings are the book's own sheet's, not a row here
  await expect(settingsButton(page, 'Reading')).toHaveCount(0);
  await expect(settingsScreen(page).getByRole('button', { name: 'Turn pages with volume keys' })).toHaveCount(0);
  await expect(settingsScreen(page).getByRole('group', { name: 'Tap to turn pages' })).toHaveCount(0);
  await expect(restoreInput(page)).toHaveCount(1);
  await settingsButton(page, 'Back').click();
  await expect(settingsScreen(page)).toBeHidden();
  expect(errors).toEqual([]);
});

test("in a book, the reading settings sheet is the one settings place: the top bar has no Settings", async ({ page }) => {
  const errors = await start(page);
  await readBook(page, { title: 'Settled', author: 'Reader', rawChapters: chapters(2) });
  await showChrome(page);
  await expect(topBar(page).getByRole('button', { name: 'Search in book' })).toBeVisible();
  await expect(topBar(page).getByRole('button', { name: 'Settings' })).toHaveCount(0);
  // where taps turn pages, and full screen, are in the sheet
  await openReadingSettings(page, 'Turning');
  await expect(readingSettings(page).getByRole('group', { name: 'Tap to turn pages' })).toBeVisible();
  await openReadingSettings(page, 'Page');
  await expect(readingSettings(page).getByRole('button', { name: 'Full screen', exact: true })).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
  await expect(settingsScreen(page)).toBeHidden();
  expect(errors).toEqual([]);
});

test('Sync opens from its row, a service\'s step from its own, and Escape closes the step, Sync, then Settings', async ({ page }) => {
  await start(page);
  await librarySettings(page);
  await expect(syncRow(page)).toContainText('Off');
  await settingsButton(page, 'Sync').click();
  const sync = dialog(page, 'Sync');
  await expect(sync).toBeVisible();
  // a service's row opens its own step over the list, and Escape (as
  // Cancel) goes back to the list (#331)
  await sync.getByRole('button', { name: 'WebDAV', exact: true }).click();
  await expect(sync.getByLabel('Folder URL')).toBeVisible();
  await expect(sync.getByRole('button', { name: 'WebDAV', exact: true })).toBeHidden();
  await page.keyboard.press('Escape');
  await expect(sync.getByLabel('Folder URL')).toBeHidden();
  await sync.getByRole('button', { name: 'WebDAV', exact: true }).click();
  await sync.getByRole('button', { name: 'Cancel' }).click();
  await expect(sync.getByLabel('Folder URL')).toBeHidden();
  await expect(sync.getByRole('button', { name: 'WebDAV', exact: true })).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(sync).toBeHidden();
  await expect(settingsScreen(page)).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(settingsScreen(page)).toBeHidden();
  await expect(libraryShown(page)).toBeVisible();
});

// quire#501: where sync and backup are. Sync is how a new phone gets
// places, shelves and notes, so it is two taps from the library (the
// menu, then Sync) and an empty library offers it; the backup is in
// Settings, three taps from the library at most, with a line saying what
// each holds. (Play Books syncs through the Google account with no setting
// to find; Moon+ Reader keeps its backup in Settings, so the pair is a
// menu item for the common task and Settings for the file.)
test('Sync is two taps from the library and the backup three, and an empty library offers sync', async ({ page }) => {
  const errors = await start(page);
  // the empty library offers it
  await page.getByRole('button', { name: 'Sync with another device' }).click();
  await expect(dialog(page, 'Sync')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(dialog(page, 'Sync')).toBeHidden();
  // tap 1: the library menu; tap 2: Sync
  await libraryMenu(page);
  await menuItem(page, 'Sync').click();
  await expect(dialog(page, 'Sync')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(dialog(page, 'Sync')).toBeHidden();
  await expect(libraryShown(page)).toBeVisible();
  // taps 1 and 2: the menu, Settings, where the backup is, with its line
  await librarySettings(page);
  await expect(settingsButton(page, 'Export backup')).toBeVisible();
  await expect(settingsScreen(page)).toContainText('Moving to a new phone?');
  await page.keyboard.press('Escape');
  await expect(settingsScreen(page)).toBeHidden();
  expect(errors).toEqual([]);
});

// quire#502: a pushed screen has a top bar with a Back arrow and its
// title, kept at the top as the screen scrolls, and no Done at its foot;
// Back does what Escape does
test('Settings, Sync, Dictionaries and About each have a top bar with Back, and no Done', async ({ page }) => {
  const errors = await start(page);
  await librarySettings(page);
  const bar = screen => screen.locator('.tbar');
  // the screens opened from Settings first, Settings itself last
  const screens = [
    ['Sync', dialog(page, 'Sync')],
    ['Dictionaries', dialog(page, 'Dictionaries')],
    ['About Quire', dialog(page, 'About Quire')],
    ['Settings', settingsScreen(page)],
  ];
  const opened = {
    Settings: async () => {},
    Sync: () => settingsButton(page, 'Sync').click(),
    Dictionaries: () => settingsButton(page, 'Dictionaries').click(),
    'About Quire': () => settingsButton(page, 'About Quire').click(),
  };
  for (const [title, screen] of screens) {
    await opened[title]();
    await expect(screen).toBeVisible();
    // the bar: Back first, then the title, at the top of the screen
    await expect(bar(screen).getByRole('button', { name: 'Back', exact: true })).toBeVisible();
    await expect(bar(screen)).toContainText(title);
    await expect(screen.getByRole('button', { name: 'Done' })).toHaveCount(0);
    const back = await bar(screen).getByRole('button', { name: 'Back', exact: true }).boundingBox();
    expect(back.width).toBeGreaterThanOrEqual(48);
    expect(back.height).toBeGreaterThanOrEqual(48);
    // it stays at the top as the screen scrolls
    const before = await bar(screen).boundingBox();
    await screen.locator('.info-in').evaluate(e => { e.scrollTop = e.scrollHeight; });
    const after = await bar(screen).boundingBox();
    expect(after.y, `${title}: the bar moved as the screen scrolled`).toBe(before.y);
    // Back closes the screen, as Escape does: to the screen under it
    await bar(screen).getByRole('button', { name: 'Back', exact: true }).click();
    await expect(screen).toBeHidden();
    if (title !== 'Settings') await expect(settingsScreen(page)).toBeVisible();
  }
  await expect(libraryShown(page)).toBeVisible();
  expect(errors).toEqual([]);
});

test('a row that ends in a chevron opens a screen, never a dialog, and a service\'s row says what it is (#389)', async ({ page }) => {
  await start(page);
  await librarySettings(page);
  for (const row of ['Sync', 'Dictionaries', 'About Quire']) {
    await settingsButton(page, row).click();
    const opened = dialog(page, row);
    await expect(opened, `${row} opens a screen`).toHaveClass(/\binfo\b/);
    if (row === 'Sync') {
      // each service says, under its name, what it is
      await expect(opened.locator('#sync-webdav-hint')).toHaveText(/Any WebDAV folder/);
      await expect(opened.locator('#sync-nextcloud-hint')).toHaveText(/Nextcloud server/);
    }
    if (row === 'Dictionaries') await expect(opened.getByText('Import dictionary')).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(opened).toBeHidden();
    await expect(settingsScreen(page)).toBeVisible();
  }
});

test('the backup is exported and restored from Settings', async ({ page }, testInfo) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Kept Safe', author: 'Archivist' })], 1);
  await librarySettings(page);
  const backup = JSON.parse(await exportedBackup(page));
  expect(backup.books.map(b => b.title)).toEqual(['Kept Safe']);
  // a goal put in the backup comes back with its restore
  backup.settings.dailyGoal = 20;
  const path = testInfo.outputPath('settings-backup.json');
  writeFileSync(path, JSON.stringify(backup));
  await restoreInput(page).setInputFiles([path]);
  await expect(dialog(page, 'Backup restored')).toBeVisible();
  await dialog(page, 'Backup restored').getByRole('button').first().click();
  await expect(settingsScreen(page)).toBeHidden();
  await librarySettings(page);
  await expect(goal(page).getByRole('button', { name: '20 min' })).toHaveAttribute('aria-pressed', 'true');
});

test('the daily goal is chosen in Settings, and the statistics panel shows it', async ({ page }) => {
  await start(page);
  await librarySettings(page);
  await expect(goal(page).getByRole('button', { name: 'Off' })).toHaveAttribute('aria-pressed', 'true');
  await goal(page).getByRole('button', { name: '30 min' }).click();
  await expect(goal(page).getByRole('button', { name: '30 min' })).toHaveAttribute('aria-pressed', 'true');
  await expect(goal(page).getByRole('button', { name: 'Off' })).toHaveAttribute('aria-pressed', 'false');
  await settingsButton(page, 'Back').click();
  await libraryMenu(page);
  await menuItem(page, 'Reading statistics').click();
  const stats = dialog(page, 'Reading statistics').getByRole('group', { name: 'Daily goal' });
  await expect(stats.getByRole('button', { name: '30 min' })).toHaveAttribute('aria-pressed', 'true');
});

test('Reset reading settings and Remove all books, from Settings, each with its Undo', async ({ page }) => {
  // the theme is Auto until a reader chooses one, and Auto is the night theme
  // from 22:00 to 07:00 by the clock (#570): the ground read as plain must not
  // be read again after the runner's clock has passed that hour
  await page.clock.install({ time: new Date('2026-06-01T12:00:00Z') });
  await start(page);
  await importFiles(page, [epubFile({ title: 'Reset Book', author: 'R' })], 1);
  const plain = await bg(page);
  await openBook(page, 'Reset Book');
  await openSettings(page);
  await page.getByRole('button', { name: 'Sepia', exact: true }).click();
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await expect.poll(() => bg(page)).not.toBe(plain);
  const sepia = await bg(page);
  // the settings reset, and back with Undo
  await librarySettings(page);
  await settingsButton(page, 'Reset reading settings').click();
  await expect(page.getByRole('status').filter({ hasText: 'Settings reset' })).toBeVisible();
  await undo(page).click();
  await settingsButton(page, 'Back').click();
  await expect.poll(() => bg(page)).toBe(sepia);
  await librarySettings(page);
  await settingsButton(page, 'Reset reading settings').click();
  await settingsButton(page, 'Back').click();
  await expect.poll(() => bg(page)).toBe(plain);
  await undo(page).click();
  await expect.poll(() => bg(page)).toBe(sepia);
  // the factory reset: Settings closes on the library, emptied
  await librarySettings(page);
  await settingsButton(page, 'Remove all books').click();
  await expect(settingsScreen(page)).toBeHidden();
  await expect(cards(page)).toHaveCount(0);
  await expect.poll(() => bg(page)).toBe(plain);
  await undo(page).click();
  await expect(card(page, 'Reset Book')).toHaveCount(1);
  await expect.poll(() => bg(page)).toBe(sepia);
});

test('a row that opens a screen is one target, and the Undo toast is over nothing of the screen (#380)', async ({ page }) => {
  await start(page);
  await librarySettings(page);
  expect(await rowIsTarget(page)).toEqual([]);
  // the groups have headings, and About comes before the resets
  const screen = settingsScreen(page);
  const order = await screen.locator('.a11yg').allTextContents();
  expect(order.indexOf('About')).toBeGreaterThanOrEqual(0);
  expect(order.indexOf('About')).toBeLessThan(order.indexOf('Reset'));
  await settingsButton(page, 'Reset reading settings').click();
  await expect(undo(page)).toBeVisible();
  await screen.locator('.info-in').evaluate(element => { element.scrollTop = element.scrollHeight; });
  expect(await toastClear(page)).toEqual([]);
});
