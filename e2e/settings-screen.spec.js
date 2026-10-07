// The Settings screen: opened from the library menu, it holds what the
// library menu used to (sync, the dictionaries, the backup, the resets)
// and the daily reading goal. Each complex area is a screen of its own,
// opened from its row, and Escape closes the screen on top, then
// Settings. In a book, the reading settings sheet is the one place
// (#342).

import { test, expect, onAndroid } from './fixtures.js';
import { readFileSync, writeFileSync } from 'node:fs';
import {
  start, epubFile, importFiles, cards, card, openBook, readBook, toLibrary, chapters, dialog, menuItem, libraryMenu,
  openSettings, colours, showChrome, librarySearch, bookPage, topBar, openReadingSettings, readingSettings,
  settingsScreen, settingsButton, librarySettings, restoreInput,
} from './helpers.js';

const bg = async page => (await colours(page)).bg.join(',');
const undo = page => page.getByRole('button', { name: 'Undo' });
const syncRow = page => settingsScreen(page).getByRole('group', { name: 'Sync' });
const goal = page => settingsScreen(page).getByRole('group', { name: 'Daily reading goal' });

test('Settings opens from the library menu, which no longer holds what it took', async ({ page }) => {
  const errors = await start(page);
  await libraryMenu(page);
  for (const gone of ['Sync', 'Dictionaries', 'Export backup', 'Import backup', 'Restore backup', 'Reset settings', 'Factory reset']) {
    await expect(menuItem(page, gone)).toHaveCount(0);
  }
  await expect(page.getByRole('menu').getByLabel('Restore backup')).toHaveCount(0);
  // what stays: the Trash's one irreversible action among them
  await expect(menuItem(page, 'Empty Trash')).toBeVisible();
  await expect(menuItem(page, 'Reading statistics')).toBeVisible();
  await expect(menuItem(page, 'Catalogues')).toBeVisible();
  await menuItem(page, 'Settings').click();
  await expect(settingsScreen(page)).toBeVisible();
  await expect(page.getByRole('menu')).toBeHidden();
  for (const row of ['Sync ›', 'Dictionaries ›', 'Export backup', 'Reset settings', 'Factory reset', 'Done']) {
    await expect(settingsButton(page, row)).toBeVisible();
  }
  // the reading settings are the book's own sheet's, not a row here
  await expect(settingsButton(page, 'Reading ›')).toHaveCount(0);
  await expect(settingsScreen(page).getByRole('button', { name: 'Turn pages with volume keys' })).toHaveCount(0);
  await expect(settingsScreen(page).getByRole('group', { name: 'Tap to turn pages' })).toHaveCount(0);
  await expect(restoreInput(page)).toHaveCount(1);
  await settingsButton(page, 'Done').click();
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
  await settingsButton(page, 'Sync ›').click();
  const sync = dialog(page, 'Sync');
  await expect(sync).toBeVisible();
  // a service's row opens its own step over the list, and Escape (as
  // Cancel) goes back to the list (#331)
  await sync.getByRole('button', { name: 'WebDAV ›' }).click();
  await expect(sync.getByLabel('Folder URL')).toBeVisible();
  await expect(sync.getByRole('button', { name: 'WebDAV ›' })).toBeHidden();
  await page.keyboard.press('Escape');
  await expect(sync.getByLabel('Folder URL')).toBeHidden();
  await sync.getByRole('button', { name: 'WebDAV ›' }).click();
  await sync.getByRole('button', { name: 'Cancel' }).click();
  await expect(sync.getByLabel('Folder URL')).toBeHidden();
  await expect(sync.getByRole('button', { name: 'WebDAV ›' })).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(sync).toBeHidden();
  await expect(settingsScreen(page)).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(settingsScreen(page)).toBeHidden();
  await expect(librarySearch(page)).toBeVisible();
});

test('the backup is exported and restored from Settings', async ({ page }, testInfo) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Kept Safe', author: 'Archivist' })], 1);
  await librarySettings(page);
  const download = page.waitForEvent('download');
  await settingsButton(page, 'Export backup').click();
  const d = await download;
  expect(d.suggestedFilename()).toBe('quire-backup.json');
  const backup = JSON.parse(readFileSync(await d.path(), 'utf8'));
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
  await settingsButton(page, 'Done').click();
  await libraryMenu(page);
  await menuItem(page, 'Reading statistics').click();
  const stats = dialog(page, 'Reading statistics').getByRole('group', { name: 'Daily goal' });
  await expect(stats.getByRole('button', { name: '30 min' })).toHaveAttribute('aria-pressed', 'true');
});

test('Reset settings and Factory reset, from Settings, each with its Undo', async ({ page }) => {
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
  await settingsButton(page, 'Reset settings').click();
  await expect(page.getByRole('status').filter({ hasText: 'Settings reset' })).toBeVisible();
  await undo(page).click();
  await settingsButton(page, 'Done').click();
  await expect.poll(() => bg(page)).toBe(sepia);
  await librarySettings(page);
  await settingsButton(page, 'Reset settings').click();
  await settingsButton(page, 'Done').click();
  await expect.poll(() => bg(page)).toBe(plain);
  await undo(page).click();
  await expect.poll(() => bg(page)).toBe(sepia);
  // the factory reset: Settings closes on the library, emptied
  await librarySettings(page);
  await settingsButton(page, 'Factory reset').click();
  await expect(settingsScreen(page)).toBeHidden();
  await expect(cards(page)).toHaveCount(0);
  await expect.poll(() => bg(page)).toBe(plain);
  await undo(page).click();
  await expect(card(page, 'Reset Book')).toHaveCount(1);
  await expect.poll(() => bg(page)).toBe(sepia);
});
