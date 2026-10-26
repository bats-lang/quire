// The words looked up are kept with their sentence and can be reviewed (quire#565, keyword: vocabulary): a lookup adds a
// row to the Words screen, a second lookup of the word counts, the setting turns it off, Go to opens the book at the place,
// a word is mastered, learned again, deleted with Undo, and reviewed on KOReader's schedule by a fake clock; the backup and
// sync carry the list, and it is shared as a CSV file.

import { test, expect } from './fixtures.js';
import AxeBuilder from '@axe-core/playwright';
import { readFileSync } from 'node:fs';
import {
  importFiles, epubFile, start, readBook, toLibrary, openBook, selectText, dialog, libraryMenu, menuItem, reload, rawFile, bookPage,
  librarySettings, settingsButton, settingsScreen, exportedBackup, restoreInput, place, indicator,
} from './helpers.js';
import { createStardict } from './create-stardict.js';
import { book as sharedBook, NOON, minutesLater, stores, sync, clockFixed, unexpected, closeSync } from './sync-devices.js';

const english = {
  name: 'Pocket English',
  entries: [
    { word: 'ephemeral', article: 'lasting a very short time' },
    { word: 'serendipity', article: 'a happy accident found by chance' },
    { word: 'perspicacious', article: 'having keen insight' },
  ],
};

const FIRST = 'Ephemeral things end.';
const SECOND = 'Serendipity found me today.';
const THIRD = 'The unknownword stays here.';
const text = `${FIRST} ${SECOND} ${THIRD}`;
const at = word => [text.indexOf(word), text.indexOf(word) + word.length];
const novel = (title, extra = {}) => ({
  title, author: 'Vocabulary Tests', language: 'en',
  rawChapters: [
    { body: `<p>${text}</p>` + '<p>lorem ipsum dolor sit amet</p>'.repeat(10) },
    { body: `<p>Perspicacious readers keep notes.</p>` + '<p>lorem ipsum dolor sit amet</p>'.repeat(10) },
  ],
  ...extra,
});

const wordsScreen = page => dialog(page, 'Words');
const reviewScreen = page => dialog(page, 'Review');
const entry = page => dialog(page, 'Dictionary');
const selection = page => page.getByRole('toolbar', { name: 'Selection' });
const lookUpHere = page => selection(page).getByRole('button', { name: 'Look up', exact: true });
const lookUpOnline = page => selection(page).getByRole('link', { name: 'Look up online', exact: true });
const row = (page, word) => wordsScreen(page).getByRole('group', { name: word, exact: true });
const keepSwitch = page => settingsScreen(page).getByRole('button', { name: 'Keep the words I look up', exact: true });

/** Imports the dictionary for language through Settings' Dictionaries, and returns to the library */
async function importDictionary(page, dict, language) {
  await librarySettings(page);
  await settingsButton(page, 'Dictionaries').click();
  await dialog(page, 'Dictionaries').getByRole('combobox', { name: 'Dictionary language' }).selectOption(language);
  const made = createStardict(dict);
  await page.getByLabel('Import dictionary').setInputFiles([
    rawFile('test.ifo', made.ifo), rawFile('test.idx', made.idx), rawFile('test.dict', made.dict)]);
  await expect(dialog(page, 'Dictionaries').getByRole('status')).toHaveText('Dictionary added.', { timeout: 30000 });
  await dialog(page, 'Dictionaries').getByRole('button', { name: 'Back' }).click();
  await page.keyboard.press('Escape');
  await expect(settingsScreen(page)).toBeHidden();
}

/** Selects word in the first paragraph, and looks it up in the dictionary (closing its panel) */
async function lookUp(page, word) {
  const [from, to] = at(word);
  await selectText(page, from, to);
  await expect(selection(page)).toBeVisible();
  await lookUpHere(page).click();
  await expect(entry(page)).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(entry(page)).toBeHidden();
}

async function openWords(page) {
  await libraryMenu(page);
  await menuItem(page, 'Words').click();
  await expect(wordsScreen(page)).toBeVisible();
}

async function closeWords(page) {
  await wordsScreen(page).getByRole('button', { name: 'Back' }).click();
  await expect(wordsScreen(page)).toBeHidden();
}

const audit = async page => {
  const r = await new AxeBuilder({ page }).analyze();
  return r.violations.map(v => `${v.id}: ${v.nodes.map(n => n.target.join(' ')).join(', ')}`);
};

test('a lookup adds a row with its sentence, the word marked, its book and its state; a second lookup counts and adds none', async ({ page }) => {
  const errors = await start(page);
  await importDictionary(page, english, 'en');
  await readBook(page, novel('Vocabulary One'));
  await lookUp(page, 'Ephemeral');
  await lookUp(page, 'Serendipity');
  await toLibrary(page);
  await openWords(page);
  const first = row(page, 'Ephemeral');
  await expect(first).toBeVisible();
  await expect(first).toContainText(FIRST);
  await expect(first.locator('.mk')).toHaveText('Ephemeral');
  await expect(first.locator('.mk')).toHaveCSS('font-weight', '700');
  await expect(first).toContainText('Vocabulary One');
  await expect(first).toContainText('Learning, due now');
  await expect(first).toContainText('Looked up once');
  await expect(row(page, 'Serendipity')).toContainText(SECOND);
  await expect(wordsScreen(page).getByRole('status')).toContainText('2 due, 2 learning, 0 mastered');
  expect(await audit(page)).toEqual([]);
  // a second lookup of the same word is the same entry: counted, not added
  await closeWords(page);
  await openBook(page, 'Vocabulary One');
  await lookUp(page, 'Ephemeral');
  await toLibrary(page);
  await openWords(page);
  await expect(wordsScreen(page).getByRole('group', { name: /^(Ephemeral|Serendipity)$/ })).toHaveCount(2);
  await expect(first).toContainText('Looked up 2 times');
  // kept across a reload
  await reload(page);
  await openWords(page);
  await expect(first).toContainText('Looked up 2 times');
  await expect(first).toContainText(FIRST);
  // the dictionary panel opens for a row, with the article read again: nothing of it was stored
  await first.getByRole('button', { name: /Ephemeral/ }).first().click();
  await expect(entry(page)).toBeVisible();
  await expect(entry(page)).toContainText('lasting a very short time');
  await expect(entry(page)).toContainText('Pocket English');
  await page.keyboard.press('Escape');
  expect(errors).toEqual([]);
});

test('Look up online keeps the word and its sentence, and a word with no dictionary is a row with no definition', async ({ page, context }) => {
  await context.route('https://en.wiktionary.org/**', route => route.fulfill({ status: 200, contentType: 'text/html', body: '<p>wiktionary</p>' }));
  const errors = await start(page);
  await readBook(page, novel('Vocabulary Two'));
  const [from, to] = at('unknownword');
  await selectText(page, from, to);
  await expect(lookUpOnline(page)).toBeVisible();
  const popup = context.waitForEvent('page');
  await lookUpOnline(page).click();
  await (await popup).close();
  await toLibrary(page);
  await openWords(page);
  await expect(row(page, 'unknownword')).toContainText(THIRD);
  await expect(row(page, 'unknownword').locator('.mk')).toHaveText('unknownword');
  // a row opens the dictionary panel even where no dictionary has the word: it says so and looks it up online
  await row(page, 'unknownword').getByRole('button', { name: /unknownword/ }).first().click();
  await expect(entry(page)).toBeVisible();
  await expect(entry(page)).toContainText('unknownword');
  await expect(entry(page)).toContainText('No dictionary you added has this word');
  await expect(entry(page).getByRole('link', { name: 'Look up online' })).toHaveAttribute('href', 'https://en.wiktionary.org/wiki/Special:Search?search=unknownword');
  expect(errors).toEqual([]);
});

test('with the setting off nothing is kept; the setting is a switch beside Dictionaries, kept across a reload and by the backup', async ({ page }) => {
  await start(page);
  await importDictionary(page, english, 'en');
  await librarySettings(page);
  const keep = keepSwitch(page);
  await expect(keep).toHaveAttribute('aria-pressed', 'true');
  await keep.click();
  await expect(keep).toHaveAttribute('aria-pressed', 'false');
  // the backup says it
  const backup = JSON.parse(await exportedBackup(page));
  expect(backup.settings.wordsKept).toBe(false);
  await page.keyboard.press('Escape');
  await readBook(page, novel('Vocabulary Three'));
  await lookUp(page, 'Ephemeral');
  await toLibrary(page);
  await openWords(page);
  await expect(wordsScreen(page).getByText('No words yet')).toBeVisible();
  await expect(wordsScreen(page).getByRole('group', { name: 'Ephemeral' })).toHaveCount(0);
  await closeWords(page);
  await reload(page);
  await librarySettings(page);
  await expect(keepSwitch(page)).toHaveAttribute('aria-pressed', 'false');
  await keepSwitch(page).click();
  await expect(keepSwitch(page)).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');
  await openBook(page, 'Vocabulary Three');
  await lookUp(page, 'Ephemeral');
  await toLibrary(page);
  await openWords(page);
  await expect(row(page, 'Ephemeral')).toBeVisible();
});

test('Go to opens the book at the place of the lookup', async ({ page }) => {
  await start(page);
  await importDictionary(page, { name: 'Pocket English', entries: [{ word: 'perspicacious', article: 'having keen insight' }] }, 'en');
  await readBook(page, novel('Vocabulary Four'));
  // on to the second chapter, where the word is the first of its paragraph
  for (let turn = 0; turn < 40 && (await place(page)).ch !== 2; turn++) await page.keyboard.press('ArrowRight');
  expect((await place(page)).ch).toBe(2);
  await selectText(page, 0, 'Perspicacious'.length);
  await lookUpHere(page).click();
  await expect(entry(page)).toBeVisible();
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await reload(page);
  await openBook(page, 'Vocabulary Four');
  await openWordsFromReader(page);
  // (the reader is where it was left; the screen is over the library, so go there)
  await expect(wordsScreen(page)).toBeVisible();
  await row(page, 'Perspicacious').getByRole('button', { name: 'Go to' }).click();
  await expect(bookPage(page)).toBeVisible();
  await expect(bookPage(page)).toContainText('Perspicacious readers keep notes.');
  expect((await place(page)).ch).toBe(2);
});

/** The Words screen from a book: back to the library, then the screen */
async function openWordsFromReader(page) {
  await toLibrary(page);
  await openWords(page);
}

test('a word is marked mastered, learned again, and deleted with Undo; the tabs and the book filter list the right words', async ({ page }) => {
  const errors = await start(page);
  await importDictionary(page, english, 'en');
  await readBook(page, novel('Vocabulary Five'));
  await lookUp(page, 'Ephemeral');
  await lookUp(page, 'Serendipity');
  await toLibrary(page);
  await importFiles(page, [epubFile({ title: 'Other Book', author: 'O', rawChapters: [{ body: '<p>Perspicacious readers keep notes.</p>' }] })], 2);
  await openBook(page, 'Other Book');
  await selectText(page, 0, 'Perspicacious'.length);
  await lookUpHere(page).click();
  await expect(entry(page)).toBeVisible();
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await openWords(page);
  await expect(wordsScreen(page).getByRole('group', { name: /^(Ephemeral|Serendipity|Perspicacious)$/ })).toHaveCount(3);
  // the book filter
  await wordsScreen(page).getByRole('combobox', { name: 'Book' }).selectOption({ label: 'Other Book' });
  await expect(wordsScreen(page).getByRole('group', { name: /^(Ephemeral|Serendipity|Perspicacious)$/ })).toHaveCount(1);
  await expect(row(page, 'Perspicacious')).toContainText('Other Book');
  await wordsScreen(page).getByRole('combobox', { name: 'Book' }).selectOption({ label: 'All books' });
  await expect(wordsScreen(page).getByRole('group', { name: /^(Ephemeral|Serendipity|Perspicacious)$/ })).toHaveCount(3);
  await wordsScreen(page).getByRole('combobox', { name: 'Book' }).selectOption({ label: 'Vocabulary Five' });
  await expect(wordsScreen(page).getByRole('group', { name: /^(Ephemeral|Serendipity|Perspicacious)$/ })).toHaveCount(2);

  // mastered: out of Learning, into Mastered
  await row(page, 'Serendipity').getByRole('button', { name: 'Mark as mastered' }).click();
  await expect(row(page, 'Serendipity')).toBeHidden();
  await wordsScreen(page).getByRole('button', { name: 'Mastered', exact: true }).click();
  await expect(wordsScreen(page).getByRole('button', { name: 'Mastered', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await expect(row(page, 'Serendipity')).toBeVisible();
  await expect(row(page, 'Serendipity')).toContainText('Mastered');
  await expect(row(page, 'Ephemeral')).toBeHidden();
  // learned again
  await row(page, 'Serendipity').getByRole('button', { name: 'Learn again' }).click();
  await expect(row(page, 'Serendipity')).toBeHidden();
  await wordsScreen(page).getByRole('button', { name: 'Learning', exact: true }).click();
  await expect(row(page, 'Serendipity')).toContainText('Learning, due now');

  // delete, with Undo
  await row(page, 'Serendipity').getByRole('button', { name: 'Delete' }).click();
  await expect(row(page, 'Serendipity')).toBeHidden();
  const toast = page.getByRole('status').filter({ hasText: 'Word deleted' });
  await expect(toast).toBeVisible();
  await toast.getByRole('button', { name: 'Undo' }).click();
  await expect(row(page, 'Serendipity')).toBeVisible();
  await expect(row(page, 'Serendipity')).toContainText(SECOND);
  // and deleted for good once the offer is dismissed
  await row(page, 'Serendipity').getByRole('button', { name: 'Delete' }).click();
  await expect(toast).toBeVisible();
  await toast.getByRole('button', { name: 'Dismiss' }).click();
  await reload(page);
  await openWords(page);
  await expect(row(page, 'Serendipity')).toBeHidden();
  expect(errors).toEqual([]);
});

test('Review shows the words due one at a time, the definition after Show definition; Got it three times is a day, Forgot five minutes', async ({ page }) => {
  await page.clock.install({ time: new Date('2026-06-01T12:00:00Z') });
  const errors = await start(page);
  await importDictionary(page, english, 'en');
  await readBook(page, novel('Vocabulary Six'));
  await lookUp(page, 'Ephemeral');
  await lookUp(page, 'Serendipity');
  await toLibrary(page);
  await openWords(page);
  await wordsScreen(page).getByRole('button', { name: 'Review', exact: true }).click();
  await expect(reviewScreen(page)).toBeVisible();
  await expect(reviewScreen(page).getByRole('status')).toHaveText('2 words are due');
  // the sentence with the word marked; the definition hidden until Show definition
  await expect(reviewScreen(page).locator('.mk')).toHaveCount(1);
  const word = (await reviewScreen(page).locator('.mk').textContent());
  await expect(reviewScreen(page)).toContainText(word === 'Ephemeral' ? FIRST : SECOND);
  await expect(reviewScreen(page).getByRole('button', { name: 'Got it', exact: true })).toBeHidden();
  await expect(reviewScreen(page).getByRole('button', { name: 'Forgot', exact: true })).toBeHidden();
  await expect(entry(page)).toBeHidden();
  expect(await audit(page)).toEqual([]);
  await reviewScreen(page).getByRole('button', { name: 'Show definition' }).click();
  await expect(entry(page)).toBeVisible();
  await expect(entry(page)).toContainText(word === 'Ephemeral' ? 'lasting a very short time' : 'a happy accident');
  await page.keyboard.press('Escape');
  // Forgot: due in five minutes
  await reviewScreen(page).getByRole('button', { name: 'Forgot', exact: true }).click();
  await expect(reviewScreen(page).getByRole('status')).toHaveText('1 word is due');
  const other = (await reviewScreen(page).locator('.mk').textContent());
  expect(other).not.toBe(word);
  // Got it three times, a streak of three, one day: after each wait the word is due again
  await reviewScreen(page).getByRole('button', { name: 'Show definition' }).click();
  await page.keyboard.press('Escape');
  await reviewScreen(page).getByRole('button', { name: 'Got it', exact: true }).click();
  await expect(reviewScreen(page).getByText('No words are due.')).toBeVisible();
  await page.clock.fastForward('31:00');
  await reviewScreen(page).getByRole('button', { name: 'Back' }).click();
  await wordsScreen(page).getByRole('button', { name: 'Review', exact: true }).click();
  await expect(reviewScreen(page).getByRole('status')).toHaveText('2 words are due');
  await reviewScreen(page).getByRole('button', { name: 'Back' }).click();
  expect(errors).toEqual([]);
});

test('the intervals after Got it and Forgot are KOReader\'s, read from the Words screen', async ({ page }) => {
  await page.clock.install({ time: new Date('2026-06-01T12:00:00Z') });
  await start(page);
  await importDictionary(page, english, 'en');
  await readBook(page, novel('Vocabulary Seven'));
  await lookUp(page, 'Ephemeral');
  await toLibrary(page);
  await openWords(page);
  const ephemeral = row(page, 'Ephemeral');
  const reviewOnce = async answer => {
    await wordsScreen(page).getByRole('button', { name: 'Review', exact: true }).click();
    await reviewScreen(page).getByRole('button', { name: 'Show definition' }).click();
    await page.keyboard.press('Escape');
    await reviewScreen(page).getByRole('button', { name: answer, exact: true }).click();
    await expect(reviewScreen(page).getByText('No words are due.')).toBeVisible();
    await reviewScreen(page).getByRole('button', { name: 'Back' }).click();
  };
  const intervals = [['Got it', '30 minutes', 31 * 60000], ['Got it', '12 hours', 12 * 3600000 + 60000], ['Got it', '1 day', 24 * 3600000 + 60000]];
  for (const [answer, shown, wait] of intervals) {
    await reviewOnce(answer);
    await expect(ephemeral).toContainText(`Learning, due in ${shown}`);
    await page.clock.fastForward(wait);
    await wordsScreen(page).getByRole('button', { name: 'Review', exact: true }).click();
    await expect(reviewScreen(page)).toBeVisible();
    await reviewScreen(page).getByRole('button', { name: 'Back' }).click();
  }
  await reviewOnce('Got it');
  await expect(ephemeral).toContainText('Learning, due in 2 days');
  await page.clock.fastForward(2 * 24 * 3600000 + 60000);
  await reviewOnce('Forgot');
  await expect(ephemeral).toContainText('Learning, due in 5 minutes');
});

test('the backup carries the list, and restoring it brings the words back', async ({ page, browser }) => {
  await start(page);
  await importDictionary(page, english, 'en');
  const eight = epubFile(novel('Vocabulary Eight'));
  await importFiles(page, [eight], 1);
  await openBook(page, 'Vocabulary Eight');
  await lookUp(page, 'Ephemeral');
  await lookUp(page, 'Serendipity');
  await toLibrary(page);
  await openWords(page);
  await row(page, 'Serendipity').getByRole('button', { name: 'Mark as mastered' }).click();
  await expect(row(page, 'Serendipity')).toBeHidden();
  await closeWords(page);
  await librarySettings(page);
  const backup = JSON.parse(await exportedBackup(page));
  expect(backup.words.map(w => w.word).sort()).toEqual(['Ephemeral', 'Serendipity']);
  const ephemeral = backup.words.find(w => w.word === 'Ephemeral');
  expect(ephemeral).toMatchObject({ sentence: FIRST, language: 'en', lookups: 1, mastered: 0, deleted: 0 });
  expect(ephemeral.id).toMatch(/^[0-9a-f]{14}$/);
  expect(backup.words.find(w => w.word === 'Serendipity').mastered).toBe(1);
  expect(Object.keys(ephemeral)).not.toContain('definition');
  await page.keyboard.press('Escape');

  // a device that has nothing: the book is imported, the backup restored
  const context = await browser.newContext();
  const other = await context.newPage();
  await start(other);
  await importFiles(other, [eight], 1);
  await librarySettings(other);
  await restoreInput(other).setInputFiles(rawFile('quire-backup.json', JSON.stringify(backup)));
  await expect(dialog(other, 'Backup restored')).toBeVisible();
  await dialog(other, 'Backup restored').getByRole('button', { name: 'Done' }).click();
  await other.keyboard.press('Escape');
  await openWords(other);
  await expect(row(other, 'Ephemeral')).toContainText(FIRST);
  await expect(row(other, 'Ephemeral')).toContainText('Vocabulary Eight');
  await other.getByRole('button', { name: 'Mastered', exact: true }).click();
  await expect(row(other, 'Serendipity')).toBeVisible();
  // Undo puts back what the restore replaced: here, no words at all
  await context.close();
});

test('sync carries the list: a word, its state and its deletion, by the latest change of each', async ({ browser }) => {
  const store = stores.webdav;
  const server = store.make();
  const a = await store.device(browser, server, NOON);
  const b = await store.device(browser, server, minutesLater(NOON, 1));
  for (const d of [a, b]) {
    await importFiles(d.page, [epubFile(novel('Vocabulary Nine'))], 1);
    await importDictionary(d.page, english, 'en');
    await store.join(d, server);
  }
  await openBook(a.page, 'Vocabulary Nine');
  await lookUp(a.page, 'Ephemeral');
  await toLibrary(a.page);
  await sync(store, server, a);
  await sync(store, server, b);
  expect(server.json().words.map(w => w.word)).toEqual(['Ephemeral']);
  // B has the word, with its sentence, and nothing of the definition
  await openWords(b.page);
  await expect(row(b.page, 'Ephemeral')).toContainText(FIRST);
  // B marks it mastered; A, after a sync, lists it as mastered
  await row(b.page, 'Ephemeral').getByRole('button', { name: 'Mark as mastered' }).click();
  await expect(row(b.page, 'Ephemeral')).toBeHidden();
  await closeWords(b.page);
  await sync(store, server, b);
  await sync(store, server, a);
  await openWords(a.page);
  await expect(row(a.page, 'Ephemeral')).toBeHidden();
  await a.page.getByRole('button', { name: 'Mastered', exact: true }).click();
  await expect(row(a.page, 'Ephemeral')).toContainText('Mastered');
  // A deletes it: a tombstone, which B takes
  await row(a.page, 'Ephemeral').getByRole('button', { name: 'Delete' }).click();
  await expect(row(a.page, 'Ephemeral')).toBeHidden();
  await a.page.getByRole('status').filter({ hasText: 'Word deleted' }).getByRole('button', { name: 'Dismiss' }).click();
  await closeWords(a.page);
  await sync(store, server, a);
  const kept = server.json().words;
  expect(kept).toHaveLength(1);
  expect(kept[0]).toMatchObject({ deleted: expect.any(Number) });
  expect(kept[0].deleted).toBeGreaterThan(0);
  expect(kept[0]).not.toHaveProperty('sentence');
  await sync(store, server, b);
  await openWords(b.page);
  await b.page.getByRole('button', { name: 'Mastered', exact: true }).click();
  await expect(row(b.page, 'Ephemeral')).toBeHidden();
  expect(unexpected(a)).toEqual([]);
  expect(unexpected(b)).toEqual([]);
  await a.context.close();
  await b.context.close();
});

test('the list is shared as a CSV file: word, sentence, book and language, quoted', async ({ page }, testInfo) => {
  if (testInfo.project.name === 'android') await page.addInitScript(() => { delete Navigator.prototype.share; delete navigator.share; });
  else await page.addInitScript(() => {
    window.shared = [];
    navigator.canShare = d => !!d.files;
    navigator.share = async d => {
      const files = await Promise.all((d.files || []).map(async f => ({ name: f.name, type: f.type, text: await f.text() })));
      window.shared.push({ text: d.text, files });
    };
  });
  await start(page);
  await importDictionary(page, english, 'en');
  await readBook(page, novel('Vocabulary "Ten"'));
  await lookUp(page, 'Ephemeral');
  await lookUp(page, 'Serendipity');
  await toLibrary(page);
  await openWords(page);
  await wordsScreen(page).getByRole('button', { name: 'Share as CSV' }).click();
  let csv;
  if (testInfo.project.name === 'android') {
    const calls = plugin => page.evaluate(name => window.__android.calls.filter(c => c.plugin === name), plugin);
    await expect.poll(async () => (await calls('Share')).length).toBe(1);
    const written = (await calls('Filesystem')).find(c => c.method === 'writeFile' && c.options.path === 'quire-words.csv');
    expect(written.options.directory).toBe('CACHE');
    expect((await calls('Share'))[0].options).toEqual({ title: 'quire-words.csv', files: ['file:///quire-words.csv'] });
    csv = Buffer.from(written.options.data, 'base64').toString();
  } else {
    await expect.poll(() => page.evaluate(() => window.shared.length)).toBe(1);
    const [file] = await page.evaluate(() => window.shared[0].files);
    expect(file).toMatchObject({ name: 'quire-words.csv', type: 'text/csv' });
    csv = file.text;
  }
  const lines = csv.trimEnd().split('\n');
  expect(lines[0]).toBe('word,sentence,book,language');
  expect(lines.slice(1).sort()).toEqual([
    `"Ephemeral","${FIRST}","Vocabulary ""Ten""","en"`,
    `"Serendipity","${SECOND}","Vocabulary ""Ten""","en"`,
  ]);
});

test('the Words screen and the Review screen are screens: Back and Escape leave them one step at a time', async ({ page }) => {
  await start(page);
  await openWords(page);
  await expect(wordsScreen(page).getByText('No words yet')).toBeVisible();
  await wordsScreen(page).getByRole('button', { name: 'Review', exact: true }).click();
  await expect(reviewScreen(page).getByText('No words are due.')).toBeVisible();
  await expect(reviewScreen(page).getByRole('button', { name: 'Show definition' })).toBeHidden();
  await page.keyboard.press('Escape');
  await expect(reviewScreen(page)).toBeHidden();
  await expect(wordsScreen(page)).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(wordsScreen(page)).toBeHidden();
});

// Bounds, each said when reached (quire#565, keyword: vocabulary): a sentence cut at a character, the rows the screen draws,
// the words the store holds, a write that fails.

const STAMP = 1780000020000;
const STAMP_MINUTE = STAMP / 60000;

/** A backup file holding count words named name0.. (their ids are 1.. in 14 hex digits), all due, each with a short sentence */
const wordsBackup = (count, name) => JSON.stringify({
  quire: 1,
  words: Array.from({ length: count }, (_, i) => ({
    id: (i + 1).toString(16).padStart(14, '0'), word: `${name}${i}`, language: 'en', sentence: `A sentence with ${name}${i} in it.`,
    lookups: 1, mastered: 0, streak: 0, due: STAMP_MINUTE, first: STAMP_MINUTE, last: STAMP_MINUTE, modified: STAMP, deleted: 0,
    chapter: 0, node: 0, offset: 0,
  })),
});

/** Restores the words of a backup file and returns to the library */
async function restoreWords(page, json) {
  await librarySettings(page);
  await restoreInput(page).setInputFiles(rawFile('quire-backup.json', json));
  await expect(dialog(page, 'Backup restored')).toBeVisible({ timeout: 200000 });
  await dialog(page, 'Backup restored').getByRole('button', { name: 'Done' }).click();
  await page.keyboard.press('Escape');
  await expect(settingsScreen(page)).toBeHidden();
}

/** The Words screen, opened again until it lists count words (the restore puts them into the store after it has reported) */
async function openWordsHolding(page, count) {
  await expect(async () => {
    await openWords(page);
    await expect(wordsScreen(page).getByRole('status')).toContainText(`${count} due, ${count} learning, 0 mastered`, { timeout: 2000 });
  }).toPass({ timeout: 300000, intervals: [1000, 2000, 5000] });
}

const ALERT_TIMEOUT = { timeout: 30000 };

test('a sentence longer than the list keeps is cut at a character: the word is in it, no character is broken', async ({ page }) => {
  const errors = await start(page);
  await importDictionary(page, english, 'en');
  const long = `${'café '.repeat(200)}Ephemeral ${'café '.repeat(200)}end.`;
  await readBook(page, {
    title: 'Vocabulary Long', author: 'Vocabulary Tests', language: 'en',
    rawChapters: [{ body: `<p>${long}</p>` + '<p>lorem ipsum dolor sit amet</p>'.repeat(10) }],
  });
  const from = long.indexOf('Ephemeral');
  await selectText(page, from, from + 'Ephemeral'.length);
  await expect(selection(page)).toBeVisible();
  await lookUpHere(page).click();
  await expect(entry(page)).toBeVisible();
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await openWords(page);
  const sentence = row(page, 'Ephemeral').locator('.snip');
  await expect(sentence).toBeVisible();
  const kept = (await sentence.innerText()).trim();
  expect(Buffer.byteLength(kept)).toBeLessThanOrEqual(510);
  expect(Buffer.byteLength(kept)).toBeGreaterThan(400);
  expect(kept).toContain('Ephemeral');
  expect(kept).not.toContain('�');
  expect(kept.length).toBeLessThan(long.length);
  expect(kept.replace(/\s+/g, ' ')).toMatch(/^(café )*(café)?\s?(café )*Ephemeral( café)*/);
  expect(errors).toEqual([]);
});

test('past 500 words the screen draws the newest 500 and says the rest are not shown, until a book is chosen', async ({ page }) => {
  test.setTimeout(240000);
  await start(page);
  await restoreWords(page, wordsBackup(501, 'many'));
  await openWordsHolding(page, 501);
  const rows = wordsScreen(page).locator('.hrow');
  await expect(rows).toHaveCount(500);
  await expect(wordsScreen(page).getByText('More words are not shown here. Choose a book to see them.')).toBeVisible();
});

test('500 words or fewer are all drawn, with no line about words not shown', async ({ page }) => {
  test.setTimeout(240000);
  await start(page);
  await restoreWords(page, wordsBackup(500, 'few'));
  await openWordsHolding(page, 500);
  await expect(wordsScreen(page).locator('.hrow')).toHaveCount(500);
  await expect(wordsScreen(page).getByText('More words are not shown here')).toBeHidden();
});

test('when 10000 words are kept a new word is not kept, and the reader is told what to do', async ({ page }) => {
  test.setTimeout(600000);
  await start(page);
  await importDictionary(page, english, 'en');
  await importFiles(page, [epubFile(novel('Vocabulary Full'))], 1);
  await restoreWords(page, wordsBackup(10000, 'full'));
  await openWordsHolding(page, 10000);
  await closeWords(page);
  await openBook(page, 'Vocabulary Full');
  await lookUp(page, 'Ephemeral');
  await expect(page.getByRole('alert').filter({ hasText: 'This word was not kept: your words are full' })).toContainText(
    'Delete words you no longer need in Words, then look it up again.', ALERT_TIMEOUT);
  await toLibrary(page);
  await librarySettings(page);
  const backup = JSON.parse(await exportedBackup(page));
  expect(backup.words.length).toBe(10000);
  expect(backup.words.some(w => w.word === 'Ephemeral')).toBe(false);
});

test('a lookup that cannot be written is said, and the word is not listed', async ({ page }) => {
  await start(page);
  await importDictionary(page, english, 'en');
  await readBook(page, novel('Vocabulary Unwritten'));
  await page.evaluate(() => {
    IDBObjectStore.prototype.put = function () {
      this.transaction.abort();
      return {};
    };
  });
  const [from, to] = at('Ephemeral');
  await selectText(page, from, to);
  await expect(selection(page)).toBeVisible();
  await lookUpHere(page).click();
  await expect(page.getByRole('alert').filter({ hasText: 'This word could not be kept in your words' })).toContainText(
    'Reopen Quire to try again.', ALERT_TIMEOUT);
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await openWords(page);
  await expect(wordsScreen(page).getByText('No words yet')).toBeVisible();
});
