// The Settings screen: opened from the library menu and from the
// reader's bar, it holds what the library menu used to (sync, the
// dictionaries, the backup, the resets) and the daily reading goal.
// Each complex area is a screen of its own, opened from its row, and
// Escape closes the screen on top, then Settings.

import { test, expect } from './fixtures.js';
import { readFileSync, writeFileSync } from 'node:fs';
import {
  start, epubFile, importFiles, cards, card, openBook, readBook, toLibrary, chapters, dialog, menuItem, libraryMenu,
  openSettings, colours, showChrome, librarySearch, bookPage, reload,
  settingsScreen, settingsButton, librarySettings, restoreInput, readingSettings, openReadingSettings,
} from './helpers.js';

const bg = async page => (await colours(page)).bg.join(',');
const undo = page => page.getByRole('button', { name: 'Undo' });
const syncRow = page => settingsScreen(page).getByRole('group', { name: 'Sync' });
/** Opens Settings from the reader's top bar, bringing the bars up (they
    may hide again before the click: both are tried again together) */
async function readerSettings(page) {
  await expect(async () => {
    await showChrome(page);
    await page.getByRole('navigation', { name: 'Book' }).getByRole('button', { name: 'Settings', exact: true }).click({ timeout: 2000 });
  }).toPass({ timeout: 20000 });
  await expect(settingsScreen(page)).toBeVisible();
}
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
  await expect(restoreInput(page)).toHaveCount(1);
  await settingsButton(page, 'Done').click();
  await expect(settingsScreen(page)).toBeHidden();
  expect(errors).toEqual([]);
});

test('Settings opens from the reader top bar, and Escape closes it back to the page', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Settled', author: 'Reader', rawChapters: chapters(2) });
  await readerSettings(page);
  await expect(settingsScreen(page)).toBeVisible();
  await expect(syncRow(page)).toContainText('Off');
  await page.keyboard.press('Escape');
  await expect(settingsScreen(page)).toBeHidden();
  await expect(bookPage(page)).toBeVisible();
  // its sub-screens open over it from the reader too
  await readerSettings(page);
  await settingsButton(page, 'Dictionaries ›').click();
  await expect(dialog(page, 'Dictionaries')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(dialog(page, 'Dictionaries')).toBeHidden();
  await expect(settingsScreen(page)).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(settingsScreen(page)).toBeHidden();
  await expect(bookPage(page)).toBeVisible();
});

test('Sync opens from its row, and Escape closes Sync, then Settings', async ({ page }) => {
  await start(page);
  await librarySettings(page);
  await expect(syncRow(page)).toContainText('Off');
  await settingsButton(page, 'Sync ›').click();
  const sync = dialog(page, 'Sync');
  await expect(sync).toBeVisible();
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

test('a factory reset from the reader goes back to the library first', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Open Book', author: 'O', rawChapters: chapters(2) });
  await readerSettings(page);
  await settingsButton(page, 'Factory reset').click();
  await expect(librarySearch(page)).toBeVisible();
  await expect(cards(page)).toHaveCount(0);
  await undo(page).click();
  await expect(card(page, 'Open Book')).toHaveCount(1);
});

// The Reading screen (#289): the reading behaviour set once (where taps
// turn pages, the volume keys in the app, reading aloud's speed and
// voice), opened from Settings' Reading row, as the reading settings
// sheet's Turning and Read aloud tabs hold it while reading. The same
// controls, made by one function in each place with each place's own
// ids: a change in either is shown in the other

/** Speech the page can use: two English voices and a French one */
async function fakeVoices(page) {
  await page.addInitScript(() => {
    window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
    const voices = [
      { name: 'Reader', lang: 'en-US', voiceURI: 'reader-en', default: true },
      { name: 'Narrator', lang: 'en-GB', voiceURI: 'narrator-en', default: false },
      { name: 'Lecteur', lang: 'fr-FR', voiceURI: 'lecteur-fr', default: false },
    ];
    const synth = { getVoices: () => voices, speak() {}, cancel() {}, addEventListener() {} };
    Object.defineProperty(window, 'speechSynthesis', { value: synth });
  });
}
const readingScreen = page => page.getByRole('dialog', { name: 'Reading', exact: true });
const readingRow = page => settingsScreen(page).getByRole('group', { name: 'Reading', exact: true });
const tapChoice = (root, name) => root.getByRole('group', { name: 'Tap to turn pages' }).getByRole('button', { name: new RegExp(`^${name}`) });

test('Reading opens from its row, from the library and the reader, and says its state in short', async ({ page }) => {
  await fakeVoices(page);
  const errors = await start(page);
  await librarySettings(page);
  // the first row, and in focus as Settings opens
  await expect(settingsButton(page, 'Reading ›')).toBeFocused();
  await expect(readingRow(page)).toContainText('Taps: sides · read aloud 1×');
  await settingsButton(page, 'Reading ›').click();
  await expect(readingScreen(page)).toBeVisible();
  await expect(tapChoice(readingScreen(page), 'Sides')).toBeFocused();
  await expect(tapChoice(readingScreen(page), 'Sides')).toHaveAttribute('aria-pressed', 'true');
  await expect(tapChoice(readingScreen(page), 'Forward')).toHaveAccessibleName('Forward Anywhere forward, left side back, top shows the controls');
  // a browser does not give the page the volume keys
  await expect(readingScreen(page).getByRole('button', { name: 'Turn pages with volume keys' })).toBeHidden();
  // from the library: the voices of the language last read, English
  // before any book
  const voice = readingScreen(page).getByRole('combobox', { name: 'Voice' });
  await expect(voice.locator('option')).toHaveText(['Automatic', 'Reader', 'Narrator']);
  await tapChoice(readingScreen(page), 'One hand').click();
  await expect(tapChoice(readingScreen(page), 'One hand')).toHaveAttribute('aria-pressed', 'true');
  await expect(tapChoice(readingScreen(page), 'Sides')).toHaveAttribute('aria-pressed', 'false');
  // Escape goes back to Settings, its row saying the change
  await page.keyboard.press('Escape');
  await expect(readingScreen(page)).toBeHidden();
  await expect(settingsScreen(page)).toBeVisible();
  await expect(settingsButton(page, 'Reading ›')).toBeFocused();
  await expect(readingRow(page)).toContainText('Taps: one hand');
  // Done too
  await settingsButton(page, 'Reading ›').click();
  await readingScreen(page).getByRole('button', { name: 'Done', exact: true }).click();
  await expect(readingScreen(page)).toBeHidden();
  await expect(settingsButton(page, 'Reading ›')).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(settingsScreen(page)).toBeHidden();
  // from the reader
  await readBook(page, { title: 'Turned', author: 'Reader', rawChapters: chapters(2) });
  await readerSettings(page);
  await settingsButton(page, 'Reading ›').click();
  await expect(readingScreen(page)).toBeVisible();
  await expect(tapChoice(readingScreen(page), 'One hand')).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await expect(settingsScreen(page)).toBeHidden();
  await expect(bookPage(page)).toBeVisible();
  expect(errors).toEqual([]);
});

test("a change on the Reading screen shows in the sheet's tabs, and one in the sheet on the Reading screen", async ({ page }) => {
  await fakeVoices(page);
  await start(page);
  await readBook(page, { title: 'Both Ways', author: 'Reader', rawChapters: chapters(2) });
  // the Reading screen to the sheet
  await readerSettings(page);
  await settingsButton(page, 'Reading ›').click();
  await tapChoice(readingScreen(page), 'Forward').click();
  await readingScreen(page).getByRole('combobox', { name: 'Reading speed' }).selectOption('1.5');
  await readingScreen(page).getByRole('combobox', { name: 'Voice' }).selectOption({ label: 'Narrator' });
  await page.keyboard.press('Escape');
  await expect(readingRow(page)).toContainText('Taps: forward · read aloud 1.5×');
  await page.keyboard.press('Escape');
  await expect(settingsScreen(page)).toBeHidden();
  await openReadingSettings(page, 'Turning');
  await expect(tapChoice(readingSettings(page), 'Forward')).toHaveAttribute('aria-pressed', 'true');
  await expect(tapChoice(readingSettings(page), 'Sides')).toHaveAttribute('aria-pressed', 'false');
  await openReadingSettings(page, 'Read aloud');
  await expect(readingSettings(page).getByRole('combobox', { name: 'Reading speed' })).toHaveValue('1.5');
  await expect(readingSettings(page).getByRole('combobox', { name: 'Voice' }).locator('option:checked')).toHaveText('Narrator');
  // the sheet to the Reading screen
  await readingSettings(page).getByRole('combobox', { name: 'Reading speed' }).selectOption('2');
  await readingSettings(page).getByRole('combobox', { name: 'Voice' }).selectOption({ label: 'Automatic' });
  await openReadingSettings(page, 'Turning');
  await tapChoice(readingSettings(page), 'Sides').click();
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
  await readerSettings(page);
  await expect(readingRow(page)).toContainText('Taps: sides · read aloud 2×');
  await settingsButton(page, 'Reading ›').click();
  await expect(tapChoice(readingScreen(page), 'Sides')).toHaveAttribute('aria-pressed', 'true');
  await expect(tapChoice(readingScreen(page), 'Forward')).toHaveAttribute('aria-pressed', 'false');
  await expect(readingScreen(page).getByRole('combobox', { name: 'Reading speed' })).toHaveValue('2');
  await expect(readingScreen(page).getByRole('combobox', { name: 'Voice' }).locator('option:checked')).toHaveText('Automatic');
  // kept, as the sheet's are
  await reload(page);
  await readerSettings(page);
  await expect(readingRow(page)).toContainText('Taps: sides · read aloud 2×');
});

test('in the app, the volume keys are on the Reading screen too, the same switch as the sheet\'s', async ({ page }) => {
  // the app, where a page is given the volume keys (pwa's MainActivity)
  await page.addInitScript(() => {
    window.Capacitor = { isNativePlatform: () => true, Plugins: {} };
  });
  await start(page);
  await readBook(page, { title: 'Keys', author: 'Reader', rawChapters: chapters(2) });
  await readerSettings(page);
  await expect(readingRow(page)).toContainText('volume keys off');
  await settingsButton(page, 'Reading ›').click();
  const onScreen = readingScreen(page).getByRole('button', { name: 'Turn pages with volume keys', exact: true });
  await expect(onScreen).toHaveAttribute('aria-pressed', 'false');
  await onScreen.click();
  await expect(onScreen).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');
  await expect(readingRow(page)).toContainText('volume keys on');
  await page.keyboard.press('Escape');
  await openReadingSettings(page, 'Turning');
  const inSheet = readingSettings(page).getByRole('button', { name: 'Turn pages with volume keys', exact: true });
  await expect(inSheet).toHaveAttribute('aria-pressed', 'true');
  await inSheet.click();
  await expect(inSheet).toHaveAttribute('aria-pressed', 'false');
  await page.keyboard.press('Escape');
  await readerSettings(page);
  await expect(readingRow(page)).toContainText('volume keys off');
  await settingsButton(page, 'Reading ›').click();
  await expect(onScreen).toHaveAttribute('aria-pressed', 'false');
});
