// The library is kept as a record for each book and one for the
// collections (#354): the old whole-library record "lib" is converted to
// them once and never changed; a change is saved in the records it
// concerns, in the groups it changed; a record that is damaged or newer
// is never shown wrong and never written over.

import { test, expect } from './fixtures.js';
import { legacyLibrary, hex7, bookKey, store, put, forgetRecords } from './legacy-library.js';
import {
  start, epubFile, importFiles, card, cards, titles, bookMenu, menuItem, dialog, reload,
  librarySettings, settingsButton, settingsScreen, openShelf,
} from './helpers.js';

const alert = page => page.getByRole('alert');
const shelf = page => page.getByRole('button', { name: 'Sort and view' });

const books = [
  { idHigh: 0x1234567, idLow: 0x0abcdef, title: 'Alpha Tales', author: 'Ann Writer', series: 'First Series', number: 2, chapters: 9, chapter: 3, pages: 40, page: 7 },
  { idHigh: 0x2345678, idLow: 0x1bcdef0, title: 'Beta Notes', author: 'Bo Author', shelf: 1 },
  { idHigh: 0x3456789, idLow: 0x2cdef01, title: 'Gamma Days', author: 'Cy Penn', done: true, collections: 1 },
];

/** The app started with "lib" holding the library, version version */
async function startWithLegacy(page, version, library = books) {
  await start(page);
  await forgetRecords(page);
  await put(page, 'lib', [...legacyLibrary(version, ['To read', 'Shared'], library)]);
  await reload(page);
}

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

for (let version = 1; version <= 6; version++) {
  test(`a library kept as QLB${version} is converted to records, and its record is not changed`, async ({ page }) => {
    await startWithLegacy(page, version);
    // the books on the shelf are shown (Beta Notes is hidden)
    await expect(cards(page)).toHaveCount(2);
    expect(await titles(page)).toEqual(expect.arrayContaining(['Alpha Tales', 'Gamma Days']));
    await expect(card(page, 'Alpha Tales')).toContainText('Ann Writer');
    if (version >= 2) await expect(card(page, 'Alpha Tales')).toContainText('First Series');
    await openShelf(page, 'Hidden');
    await expect(card(page, 'Beta Notes')).toBeVisible();
    const kept = await store(page);
    // "lib" is what it was
    expect(same(kept.lib, [...legacyLibrary(version, ['To read', 'Shared'], books)])).toBe(true);
    // one record each, and the collections'
    for (const b of books) {
      expect(kept[bookKey(b)], bookKey(b)).toBeDefined();
      expect(String.fromCharCode(...kept[bookKey(b)].slice(0, 4))).toBe('QREC');
    }
    expect(String.fromCharCode(...kept['library/index'].slice(0, 4))).toBe('QREC');
    // the records are read the next time, "lib" is not looked at again
    await put(page, 'lib', [...legacyLibrary(version, [], [])]);
    await reload(page);
    await expect(cards(page)).toHaveCount(2);
    expect(await titles(page)).toEqual(expect.arrayContaining(['Alpha Tales', 'Gamma Days']));
  });
}

test('a change to a book is saved in its own record, only where it changed', async ({ page }) => {
  await startWithLegacy(page, 6);
  await expect(cards(page)).toHaveCount(2);
  const before = await store(page);
  await bookMenu(page, 'Alpha Tales');
  await menuItem(page, 'Hide').click();
  await expect(cards(page)).toHaveCount(1);
  await reload(page);
  const after = await store(page);
  const changed = Object.keys(after).filter(key => key.startsWith('library/') && !same(after[key], before[key]));
  expect(changed).toEqual([bookKey(books[0])]);
  expect(same(after.lib, before.lib)).toBe(true);
  // the other records are the very bytes that were there
  expect(same(after[bookKey(books[2])], before[bookKey(books[2])])).toBe(true);
  expect(same(after['library/index'], before['library/index'])).toBe(true);
});

test('removing the Trash\'s books deletes their records', async ({ page }) => {
  await startWithLegacy(page, 6, [books[0], { ...books[1], shelf: 3 }, books[2]]);
  await expect(cards(page)).toHaveCount(2);
  await page.getByRole('button', { name: 'More options' }).click();
  await menuItem(page, 'Empty Trash').click();
  await dialog(page, 'Empty the Trash?').getByRole('button', { name: /^Empty/ }).click();
  await reload(page);
  const after = await store(page);
  expect(after[bookKey(books[1])]).toBeUndefined();
  expect(after[bookKey(books[0])]).toBeDefined();
  expect(after[bookKey(books[2])]).toBeDefined();
});

test('a record damaged in any byte never shows another book\'s details, and is not written over by opening', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'the walk over every byte is run once');
  test.setTimeout(240000);
  await startWithLegacy(page, 6);
  await expect(cards(page)).toHaveCount(2);
  const pristine = await store(page);
  const record = pristine[bookKey(books[0])];
  const offsets = [];
  for (let at = 0; at < Math.min(record.length, 24); at++) offsets.push(at);
  for (let at = 24; at < record.length; at += 11) offsets.push(at);
  for (let at = Math.max(24, record.length - 12); at < record.length; at++) offsets.push(at);
  const known = new Set(['Alpha Tales', 'Untitled', 'Beta Notes', 'Gamma Days']);
  for (const at of [...new Set(offsets)]) {
    const damaged = record.slice();
    damaged[at] ^= 0x5a;
    await put(page, bookKey(books[0]), damaged);
    await reload(page);
    await expect(shelf(page)).toBeVisible();
    // the other book is whole whatever happened to this one
    await expect(card(page, 'Gamma Days')).toBeVisible();
    for (const title of await titles(page)) expect(known.has(title), `byte ${at}: ${title}`).toBe(true);
    // opening a library changes none of its records
    const now = await store(page);
    expect(same(now[bookKey(books[0])], damaged), `byte ${at} was written over`).toBe(true);
  }
});

test('a record a newer Quire wrote is not shown wrong, and is not written over', async ({ page }) => {
  await startWithLegacy(page, 6);
  await expect(cards(page)).toHaveCount(2);
  const stored = await store(page);
  const newer = stored[bookKey(books[0])].slice();
  // "QREC", the record's kind, the version that wrote it and the oldest that can read it
  newer[6] = 9;
  await put(page, bookKey(books[0]), newer);
  await reload(page);
  await expect(alert(page)).toBeVisible();
  await expect(card(page, 'Alpha Tales')).toHaveCount(0);
  await expect(card(page, 'Gamma Days')).toBeVisible();
  // a change to another book is saved, and the newer record stays as it is
  await bookMenu(page, 'Gamma Days');
  await menuItem(page, 'Hide').click();
  await reload(page);
  const after = await store(page);
  expect(same(after[bookKey(books[0])], newer)).toBe(true);
  expect(same(after[bookKey(books[2])], stored[bookKey(books[2])])).toBe(false);
});

test('two tabs changing different parts of a book keep both changes', async ({ page, context }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Shared Book', author: 'Two Tabs' }), epubFile({ title: 'Other Book', author: 'Two Tabs' })], 2);
  await reload(page);
  const other = await context.newPage();
  await other.goto('/');
  await expect(cards(other)).toHaveCount(2);
  // this tab hides the book
  await bookMenu(page, 'Shared Book');
  await menuItem(page, 'Hide').click();
  await expect(cards(page)).toHaveCount(1);
  await reload(page);
  // the other tab, which has not seen that, puts the book in a collection
  await bookMenu(other, 'Shared Book');
  await menuItem(other, 'Collections').click();
  const panel = other.getByRole('dialog', { name: 'Collections' });
  await panel.getByRole('button', { name: 'New collection' }).click();
  const name = dialog(other, 'New collection').getByRole('textbox', { name: 'Name' });
  await name.fill('Both');
  await name.press('Enter');
  await panel.getByRole('button', { name: 'Done' }).click();
  await reload(other);
  await other.close();
  await reload(page);
  // hidden (this tab's change) and in the collection (the other's)
  await expect(cards(page)).toHaveCount(1);
  await openShelf(page, 'Hidden');
  await bookMenu(page, 'Shared Book');
  await menuItem(page, 'Collections').click();
  await expect(page.getByRole('dialog', { name: 'Collections' }).getByRole('button', { name: 'Both', exact: true })).toHaveAttribute('aria-pressed', 'true');
});

/* ---------------- records that cannot be read are set aside (#374) ---------------- */

const damagedKeys = (records, id) => Object.keys(records).filter(key => key.startsWith(`library/damaged/${id}/`));
const setAside = page => settingsButton(page, 'Set aside unreadable records');

test('a damaged book record and a damaged collections record are set aside, their bytes kept, and the rest is untouched', async ({ page }) => {
  await startWithLegacy(page, 6);
  await expect(cards(page)).toHaveCount(2);
  const stored = await store(page);
  const damagedBook = stored[bookKey(books[0])].slice();
  damagedBook[10] ^= 0x5a;
  const damagedIndex = stored['library/index'].slice();
  damagedIndex[10] ^= 0x5a;
  await put(page, bookKey(books[0]), damagedBook);
  await put(page, 'library/index', damagedIndex);
  await reload(page);
  await expect(card(page, 'Alpha Tales')).toHaveCount(0);
  await expect(card(page, 'Gamma Days')).toBeVisible();
  const before = await store(page);
  await librarySettings(page);
  await expect(setAside(page)).toBeVisible();
  await setAside(page).click();
  // it is said, and the button goes: there is nothing left to set aside
  await expect(settingsScreen(page)).toContainText('Quire kept a copy of the records it could not read');
  await expect(setAside(page)).toBeHidden();
  const after = await store(page);
  // both records are gone from where they were, and each one's bytes are kept
  expect(after[bookKey(books[0])]).toBeUndefined();
  expect(after['library/index']).toBeUndefined();
  const bookCopies = damagedKeys(after, `${hex7(books[0].idHigh)}${hex7(books[0].idLow)}`);
  expect(bookCopies).toHaveLength(1);
  expect(same(after[bookCopies[0]], damagedBook)).toBe(true);
  const indexCopies = damagedKeys(after, '00000000000000');
  expect(indexCopies).toHaveLength(1);
  expect(same(after[indexCopies[0]], damagedIndex)).toBe(true);
  // the other books' records are as they were
  for (const book of [books[1], books[2]]) expect(same(after[bookKey(book)], before[bookKey(book)])).toBe(true);
  // after a reload nothing is said to be unreadable, and the book that read is shown
  await reload(page);
  await expect(alert(page)).toBeHidden();
  await expect(card(page, 'Gamma Days')).toBeVisible();
  await librarySettings(page);
  await expect(setAside(page)).toBeHidden();
});

test('a record a newer Quire wrote, or one that reads, is not offered to be set aside', async ({ page }) => {
  await startWithLegacy(page, 6);
  await expect(cards(page)).toHaveCount(2);
  const stored = await store(page);
  const newer = stored[bookKey(books[0])].slice();
  newer[6] = 9;
  await put(page, bookKey(books[0]), newer);
  await reload(page);
  await librarySettings(page);
  await expect(setAside(page)).toBeHidden();
  expect(same((await store(page))[bookKey(books[0])], newer)).toBe(true);
});

test('a set aside that is aborted midway leaves the old record byte for byte, and can be tried again', async ({ page }) => {
  await startWithLegacy(page, 6);
  await expect(cards(page)).toHaveCount(2);
  const damaged = (await store(page))[bookKey(books[0])].slice();
  damaged[10] ^= 0x5a;
  await put(page, bookKey(books[0]), damaged);
  await reload(page);
  await librarySettings(page);
  // the transaction is aborted after the copy is put and before the key is deleted
  await page.evaluate(() => {
    const del = IDBObjectStore.prototype.delete;
    window.__asideAbort = true;
    IDBObjectStore.prototype.delete = function (key) {
      if (window.__asideAbort && String(key).startsWith('library/book/')) {
        this.transaction.abort();
        return undefined;
      }
      return del.call(this, key);
    };
  });
  await setAside(page).click();
  await expect(alert(page)).toContainText('could not be set aside');
  const aborted = await store(page);
  expect(same(aborted[bookKey(books[0])], damaged)).toBe(true);
  expect(damagedKeys(aborted, `${hex7(books[0].idHigh)}${hex7(books[0].idLow)}`)).toHaveLength(0);
  // nothing was lost: with the abort lifted, it is set aside
  await page.evaluate(() => { window.__asideAbort = false; });
  await expect(setAside(page)).toBeVisible();
  await setAside(page).click();
  await expect(setAside(page)).toBeHidden();
  const done = await store(page);
  expect(done[bookKey(books[0])]).toBeUndefined();
  const copies = damagedKeys(done, `${hex7(books[0].idHigh)}${hex7(books[0].idLow)}`);
  expect(copies).toHaveLength(1);
  expect(same(done[copies[0]], damaged)).toBe(true);
});
