// A failure to read stored data or a book offers Copy details and a
// Report link in its notice, as an unexpected error does, and keeps the
// details for About's Copy last error details (#507). The details hold
// Quire's version, the platform, the failure's name and, for records,
// their ids, sizes and first bytes, and no book text: no title, no
// author, no file name.

import { test, expect } from './fixtures.js';
import { legacyLibrary, hex7, bookKey, store, put, forgetRecords } from './legacy-library.js';
import {
  start, epubFile, importFiles, readBook, toLibrary, openBook, chapters, reload, libraryMenu, menuItem, cards,
} from './helpers.js';
import { failReads, stubReads } from './storage-stub.js';

const alert = page => page.getByRole('alert');
const clipboard = page => page.evaluate(() => navigator.clipboard.readText());

const books = [
  { idHigh: 0x1234567, idLow: 0x0abcdef, title: 'Alpha Tales', author: 'Ann Writer' },
  { idHigh: 0x2345678, idLow: 0x1bcdef0, title: 'Beta Notes', author: 'Bo Author' },
];
// nothing that is a reader's own words
const OWN_WORDS = ['Alpha Tales', 'Ann Writer', 'Beta Notes', 'Bo Author', 'Kept Safe', 'Notice Details', 'Para 1'];

async function startWithRecords(page, damage) {
  await start(page);
  await forgetRecords(page);
  await put(page, 'lib', [...legacyLibrary(6, ['To read'], books)]);
  await reload(page);
  await expect(cards(page)).toHaveCount(2);
  const stored = await store(page);
  const record = stored[bookKey(books[0])].slice();
  damage(record);
  await put(page, bookKey(books[0]), record);
  await reload(page);
}

/** The notice offers Copy details and Report; the copy holds every text
    of contains and none of OWN_WORDS; and, the notice dismissed, About
    keeps the same details */
async function expectDetails(page, contains) {
  const banner = alert(page);
  await expect(banner).toBeVisible();
  await expect(banner.getByRole('button', { name: 'Copy details' })).toBeVisible();
  const report = banner.getByRole('link', { name: 'Report' });
  await expect(report).toBeVisible();
  await expect(report).toHaveAttribute('href', /github\.com\/bats-lang\/quire\/issues/);
  await page.evaluate(() => navigator.clipboard.writeText(''));
  await banner.getByRole('button', { name: 'Copy details' }).click();
  await expect.poll(() => clipboard(page)).toContain('Quire ');
  const copied = await clipboard(page);
  for (const text of contains) expect(copied, text).toContain(text);
  for (const words of OWN_WORDS) expect(copied, words).not.toContain(words);
  expect(copied).toContain('no book text, titles or passwords');
  await banner.getByRole('button', { name: 'Dismiss' }).click();
  await expect(banner).toBeHidden();
  await libraryMenu(page);
  await menuItem(page, 'About Quire').click();
  await page.evaluate(() => navigator.clipboard.writeText(''));
  await page.getByRole('button', { name: 'Copy last error details' }).click();
  await expect.poll(() => clipboard(page)).toBe(copied);
}

const id = `${hex7(books[0].idHigh)}${hex7(books[0].idLow)}`;

for (const [name, damage, failure, fault] of [
  ['a damaged', record => { record[10] ^= 0x5a; }, 'BooksNotReadCanSetAside', 'damaged'],
  ['a newer', record => { record[6] = 9; }, 'BooksNotRead', 'written by a newer Quire'],
  ['a not Quire\'s', record => { record[0] ^= 0x5a; }, 'BooksNotReadCanSetAside', 'not a Quire record'],
]) {
  test(`${name} book record is offered with its details: Copy details, Report, and About keeps them`, async ({ page, context }) => {
    await context.grantPermissions(['clipboard-read', 'clipboard-write']);
    await startWithRecords(page, damage);
    await expectDetails(page, [
      `Failure: ${failure}`, 'Platform: ',
      `Book record ${id}: ${fault}, `, ' bytes, first bytes ',
      'Records that could not be used in the last read: 1',
    ]);
  });
}

test('a damaged collections record is offered with its details', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await start(page);
  await forgetRecords(page);
  await put(page, 'lib', [...legacyLibrary(6, ['To read'], books)]);
  await reload(page);
  const stored = await store(page);
  const record = stored['library/index'].slice();
  record[10] ^= 0x5a;
  await put(page, 'library/index', record);
  await reload(page);
  await expectDetails(page, ['Failure: CollectionsNotReadCanSetAside', 'Collections record: damaged, ']);
});

test('annotations and settings that cannot be read are offered with their details', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await stubReads(page);
  await start(page);
  await readBook(page, { title: 'Notice Details', author: 'Detail Tests', rawChapters: chapters(2) });
  await toLibrary(page);
  await failReads(page, 'annotations');
  await reload(page);
  await openBook(page, 'Notice Details');
  await expectDetails(page, ['Failure: AnnotationsNotRead']);
  await toLibrary(page);
  await failReads(page, 'set');
  await reload(page);
  await expectDetails(page, ['Failure: SettingsNotRead']);
});
