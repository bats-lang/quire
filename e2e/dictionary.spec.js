// An offline dictionary for Look up: StarDict dictionaries imported from
// the Settings screen's Dictionaries, each for one language, looked up from
// the selection, removed with Undo, and kept across reloads.

import { test, expect } from './fixtures.js';
import AxeBuilder from '@axe-core/playwright';
import { readFileSync } from 'node:fs';
import {
  importFiles, epubFile, start, readBook, toLibrary, openBook, selectText, dialog, libraryMenu, menuItem, reload, rawFile, bookPage,
  librarySettings, settingsButton, settingsScreen, exportedBackup,
} from './helpers.js';
import { createStardict } from './create-stardict.js';

const english = {
  name: 'Pocket English',
  entries: [
    { word: 'ephemeral', article: 'lasting a very short time' },
    { word: 'Ephemeral', article: 'the capitalised headword: a brand of tea' },
    { word: 'serendipity', article: 'a happy accident\nfound by chance' },
    { word: 'color', article: 'the property of reflecting light of a certain wavelength' },
    { word: 'apple', article: 'a fruit' },
    { word: 'zebra', article: 'a striped animal' },
  ],
  synonyms: [{ word: 'colour', target: 'color' }],
};

// HTML articles, as dictzip: chunks of 64 bytes, so an article spans
// several of them
const french = {
  name: 'Petit Larousse',
  type: 'h',
  dz: true,
  entries: [
    { word: 'maison', article: '<p><b>maison</b> <i>n.f.</i></p><p>Une demeure &amp; un foyer, ' + 'où l\'on habite '.repeat(8) + '</p><div>Voir aussi&nbsp;: logis</div>' },
    { word: 'chat', article: '<b>chat</b><br>un animal' },
  ],
};

// The first paragraph's words, at these offsets: a word is selected
// from its offset to the next
const text = 'Ephemeral Serendipity colour unknownword maison chat';
const at = word => [text.indexOf(word), text.indexOf(word) + word.length];
const book = (title, language) => ({ title, author: 'Dictionary Tests', language,
  rawChapters: [{ body: `<p>${text}</p>` + '<p>lorem ipsum dolor sit amet</p>'.repeat(10) }] });

/** The dictionary's files, written: the .ifo, .idx, articles and .syn */
function files(dict, { without = [] } = {}) {
  const made = createStardict(dict);
  const paths = [];
  if (!without.includes('ifo')) paths.push(rawFile('test.ifo', made.ifo));
  if (!without.includes('idx')) paths.push(rawFile('test.idx', made.idx));
  if (!without.includes('dict')) paths.push(rawFile(made.dz ? 'test.dict.dz' : 'test.dict', made.dict));
  if (made.syn && !without.includes('syn')) paths.push(rawFile('test.syn', made.syn));
  return paths;
}

const dictionaries = page => dialog(page, 'Dictionaries');
const entry = page => dialog(page, 'Dictionary');
const selection = page => page.getByRole('toolbar', { name: 'Selection' });
const lookUpHere = page => selection(page).getByRole('button', { name: 'Look up', exact: true });
const lookUpOnline = page => selection(page).getByRole('link', { name: 'Look up' });

/** Opens the dictionaries from Settings (opened from the library menu
    unless it is open) */
async function openDictionaries(page) {
  if (!(await settingsScreen(page).isVisible())) await librarySettings(page);
  await settingsButton(page, 'Dictionaries').click();
  await expect(dictionaries(page)).toBeVisible();
}

/** Closes the dictionaries, then Settings, with Escape */
async function closeDictionaries(page) {
  await page.keyboard.press('Escape');
  await expect(dictionaries(page)).toBeHidden();
  await page.keyboard.press('Escape');
  await expect(settingsScreen(page)).toBeHidden();
}

/** Imports the dictionary's files for language (a code) from the
    library, and closes the panel */
async function importDictionary(page, dict, language, options) {
  await openDictionaries(page);
  await dictionaries(page).getByRole('combobox', { name: 'Dictionary language' }).selectOption(language);
  await page.getByLabel('Import dictionary').setInputFiles(files(dict, options));
  if (options && options.refused) return;
  await expect(dictionaries(page).getByRole('group', { name: new RegExp(dict.name) })).toBeVisible({ timeout: 30000 });
  await expect(dictionaries(page).getByRole('status')).toHaveText('Dictionary added.');
  await dictionaries(page).getByRole('button', { name: 'Done' }).click();
  await expect(dictionaries(page)).toBeHidden();
  await page.keyboard.press('Escape');
  await expect(settingsScreen(page)).toBeHidden();
}

/** Selects word in the first paragraph */
async function select(page, word) {
  const [from, to] = at(word);
  await selectText(page, from, to);
  await expect(selection(page)).toBeVisible();
}

const audit = async page => {
  const r = await new AxeBuilder({ page }).analyze();
  return r.violations.map(v => `${v.id}: ${v.nodes.map(n => n.target.join(' ')).join(', ')}`);
};

test('a word is looked up in an imported dictionary: as it is, in another case, and by another form', async ({ page }) => {
  const errors = await start(page);
  await openDictionaries(page);
  await expect(dictionaries(page).getByText('No dictionaries yet')).toBeVisible();
  // with no book open, a dictionary is for English unless chosen otherwise
  await expect(dictionaries(page).getByRole('combobox', { name: 'Dictionary language' })).toHaveValue('en');
  expect(await audit(page)).toEqual([]);
  await page.keyboard.press('Escape');
  await importDictionary(page, english, 'en');
  await openDictionaries(page);
  await expect(dictionaries(page).getByRole('group', { name: 'Pocket English · English' })).toBeVisible();
  await expect(dictionaries(page).getByText('No dictionaries yet')).toBeHidden();
  await closeDictionaries(page);

  await readBook(page, book('Words', 'en-GB'));
  // the headword as it is: "Ephemeral", not "ephemeral"
  await select(page, 'Ephemeral');
  await expect(lookUpHere(page)).toBeVisible();
  await expect(lookUpOnline(page)).toBeHidden();
  await lookUpHere(page).click();
  await expect(entry(page)).toBeVisible();
  await expect(entry(page)).toContainText('Ephemeral');
  await expect(entry(page)).toContainText('the capitalised headword: a brand of tea');
  await expect(entry(page)).toContainText('Pocket English');
  expect(await audit(page)).toEqual([]);
  await entry(page).getByRole('button', { name: 'Close' }).click();
  await expect(entry(page)).toBeHidden();

  // "Serendipity" is only in lower case: found with its case set aside
  await select(page, 'Serendipity');
  await lookUpHere(page).click();
  await expect(entry(page)).toContainText('serendipity');
  await expect(entry(page)).toContainText('a happy accident');
  await expect(entry(page)).toContainText('found by chance');
  await page.keyboard.press('Escape');
  await expect(entry(page)).toBeHidden();

  // "colour" is another form of "color" (the .syn)
  await select(page, 'colour');
  await lookUpHere(page).click();
  await expect(entry(page)).toContainText('color');
  await expect(entry(page)).toContainText('the property of reflecting light');
  // and the panel still looks it up online, in the book's language
  const online = entry(page).getByRole('link', { name: 'Look up online' });
  await expect(online).toHaveAttribute('href', 'https://en.wiktionary.org/wiki/Special:Search?search=colour');
  await expect(online).toHaveAttribute('target', '_blank');
  await expect(online).toHaveAttribute('rel', /noopener/);
  await page.keyboard.press('Escape');

  // a word the dictionary does not have is looked up online, as before
  await select(page, 'unknownword');
  await expect(lookUpOnline(page)).toHaveAttribute('href', 'https://en.wiktionary.org/wiki/Special:Search?search=unknownword');
  await expect(lookUpHere(page)).toBeHidden();
  expect(errors).toEqual([]);
});

test('a book in a language with no dictionary looks up online', async ({ page }) => {
  await start(page);
  await importDictionary(page, english, 'en');
  await readBook(page, book('Livre', 'fr'));
  await select(page, 'colour');
  await expect(lookUpOnline(page)).toHaveAttribute('href', 'https://fr.wiktionary.org/wiki/Special:Search?search=colour');
  await expect(lookUpHere(page)).toBeHidden();
});

test('an HTML article from a .dict.dz is shown as text, its tags dropped', async ({ page }) => {
  await start(page);
  await importDictionary(page, french, 'fr');
  await openDictionaries(page);
  await expect(dictionaries(page).getByRole('group', { name: 'Petit Larousse · French' })).toBeVisible();
  await closeDictionaries(page);
  await readBook(page, book('Livre', 'fr-CA'));
  await select(page, 'maison');
  await lookUpHere(page).click();
  const article = entry(page);
  await expect(article).toContainText('Une demeure & un foyer');
  await expect(article).toContainText('Voir aussi : logis');
  // the article's tags are text, not elements: no <b>, <i> or <p> is made
  await expect(article.locator('b, i, p, br')).toHaveCount(0);
  // block tags are line breaks
  const shown = await article.innerText();
  expect(shown).toMatch(/maison n\.f\.\s*\n\s*Une demeure/);
  expect(shown).not.toContain('<');
  await page.keyboard.press('Escape');
  // a short one, from the last chunk
  await select(page, 'chat');
  await lookUpHere(page).click();
  await expect(entry(page)).toContainText('un animal');
});

test('a dictionary is removed with Undo, and gone once the offer is dismissed', async ({ page }) => {
  await start(page);
  await importDictionary(page, english, 'en');
  await openDictionaries(page);
  const row = dictionaries(page).getByRole('group', { name: 'Pocket English · English' });
  await row.getByRole('button', { name: 'Remove' }).click();
  await expect(row).toBeHidden();
  const toast = page.getByRole('status').filter({ hasText: 'Dictionary removed' });
  await expect(toast).toBeVisible();
  await toast.getByRole('button', { name: 'Undo' }).click();
  await expect(row).toBeVisible();
  // put back, it is still there after a reload, and still looks words up
  await reload(page);
  await openDictionaries(page);
  await expect(row).toBeVisible();
  await closeDictionaries(page);
  await readBook(page, book('Words', 'en'));
  await select(page, 'colour');
  await expect(lookUpHere(page)).toBeVisible();
  // removed and the toast dismissed: out of Look up, in the Trash with its
  // files, until the Trash is emptied (quire#396)
  await toLibrary(page);
  await openDictionaries(page);
  await row.getByRole('button', { name: 'Remove' }).click();
  await expect(row).toBeHidden();
  await expect(toast).toBeVisible();
  await toast.getByRole('button', { name: 'Dismiss' }).click();
  await expect(toast).toBeHidden();
  await reload(page);
  await openDictionaries(page);
  await expect(dictionaries(page).getByText('No dictionaries yet')).toBeVisible();
  await closeDictionaries(page);
  await openBook(page, 'Words');
  await select(page, 'colour');
  await expect(lookUpOnline(page)).toBeVisible();
  await expect(lookUpHere(page)).toBeHidden();
  expect(await dictionaryFiles(page), 'its files are kept in the Trash').toBeGreaterThan(0);
});

/** How many of the dictionaries' files are stored ('I', 'D', 'S', 'X' and the number) */
const dictionaryFiles = page => page.evaluate(async () => {
  const db = await new Promise((resolve, reject) => {
    const request = indexedDB.open('bats');
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  const keys = await new Promise((resolve, reject) => {
    const tx = db.transaction('kv', 'readonly');
    const request = tx.objectStore('kv').getAllKeys();
    tx.oncomplete = () => resolve(request.result);
    tx.onerror = () => reject(tx.error);
  });
  db.close();
  return keys.filter(key => /^[IDSX]0000000[0-9a-f]{7}$/.test(key)).length;
});

/** The Trash's own screen, opened from the library menu (quire#404) */
async function showTrash(page) {
  await libraryMenu(page);
  await menuItem(page, 'Trash').click();
  await expect(page.locator('#shelf-title')).toHaveText('Trash');
}

test('a removed dictionary is in the Trash with Restore, and only Empty Trash deletes its files', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Beside Dictionaries', author: 'A' })], 1);
  await importDictionary(page, english, 'en');
  const files = await dictionaryFiles(page);
  expect(files).toBeGreaterThan(0);
  await openDictionaries(page);
  const row = dictionaries(page).getByRole('group', { name: 'Pocket English · English' });
  await row.getByRole('button', { name: 'Remove' }).click();
  await page.getByRole('status').filter({ hasText: 'Dictionary removed' }).getByRole('button', { name: 'Dismiss' }).click();
  await closeDictionaries(page);
  await showTrash(page);
  const listed = page.locator('#trash-dictionaries');
  await expect(listed).toContainText('Dictionaries in the Trash');
  await expect(listed.getByRole('group', { name: 'Pocket English · English' })).toBeVisible();
  expect(await dictionaryFiles(page)).toBe(files);
  // Restore puts it back, the same table
  await listed.getByRole('button', { name: 'Restore' }).click();
  await expect(listed).toBeHidden();
  await openDictionaries(page);
  await expect(row).toBeVisible();
  await row.getByRole('button', { name: 'Remove' }).click();
  await page.getByRole('status').filter({ hasText: 'Dictionary removed' }).getByRole('button', { name: 'Dismiss' }).click();
  await closeDictionaries(page);
  // Empty Trash asks, names the dictionaries, and deletes the files with the books'
  await libraryMenu(page);
  await menuItem(page, 'Empty Trash').click();
  const ask = dialog(page, 'Empty the Trash?');
  await expect(ask).toContainText('every dictionary in it, with its files');
  await ask.getByRole('button', { name: 'Cancel' }).click();
  expect(await dictionaryFiles(page), 'declined: nothing deleted').toBe(files);
  await libraryMenu(page);
  await menuItem(page, 'Empty Trash').click();
  await dialog(page, 'Empty the Trash?').getByRole('button', { name: 'Empty' }).click();
  await expect(listed).toBeHidden();
  expect(await dictionaryFiles(page)).toBe(0);
  await reload(page);
  await showTrash(page);
  await expect(page.locator('#trash-dictionaries')).toBeHidden();
});

test('a dictionary is kept across a reload', async ({ page }) => {
  await start(page);
  await importDictionary(page, french, 'fr');
  await reload(page);
  await readBook(page, book('Livre', 'fr'));
  await select(page, 'maison');
  await lookUpHere(page).click();
  await expect(entry(page)).toContainText('Une demeure');
});

test('a dictionary without its .idx, or whose .idx is not the size its .ifo gives, is refused', async ({ page }) => {
  await start(page);
  const refusal = dialog(page, 'Dictionary not imported');
  await importDictionary(page, english, 'en', { without: ['idx'], refused: true });
  await expect(refusal).toBeVisible();
  await expect(refusal).toContainText('.idx file is missing');
  await refusal.getByRole('button', { name: 'OK' }).click();
  await expect(dictionaries(page).getByText('No dictionaries yet')).toBeVisible();
  await page.keyboard.press('Escape');

  await importDictionary(page, { ...english, idxFileSize: 12345 }, 'en', { refused: true });
  await expect(refusal).toBeVisible();
  await expect(refusal).toContainText('not the size its .ifo gives');
  await refusal.getByRole('button', { name: 'OK' }).click();
  await page.keyboard.press('Escape');

  await importDictionary(page, { ...english, offsetBits: 64 }, 'en', { refused: true });
  await expect(refusal).toContainText('64-bit offsets');
  await refusal.getByRole('button', { name: 'OK' }).click();
  await page.keyboard.press('Escape');

  await importDictionary(page, english, 'en', { without: ['dict'], refused: true });
  await expect(refusal).toContainText('.dict or .dict.dz file is missing');
  await refusal.getByRole('button', { name: 'OK' }).click();
  await expect(dictionaries(page).getByText('No dictionaries yet')).toBeVisible();
});

test('the backup lists the dictionaries, by name and language', async ({ page }) => {
  await start(page);
  await importDictionary(page, english, 'en');
  await importDictionary(page, french, 'fr');
  await librarySettings(page);
  const backup = JSON.parse(await exportedBackup(page));
  expect(backup.dictionaries).toEqual([
    { name: 'Pocket English', language: 'en' },
    { name: 'Petit Larousse', language: 'fr' },
  ]);
});
