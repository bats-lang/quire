// The library is kept as a record for each book and one for the
// collections (#354): the old whole-library record "lib" is converted to
// them once and never changed; a change is saved in the records it
// concerns, in the groups it changed; a record that is damaged or newer
// is never shown wrong and never written over.

import { test, expect } from './fixtures.js';
import {
  start, epubFile, importFiles, card, cards, titles, bookMenu, menuItem, dialog, reload,
} from './helpers.js';

const alert = page => page.getByRole('alert');
const shelf = page => page.getByRole('button', { name: /^(Library|Hidden|Archived|Trash)$/ });

/* ---------------- the old record, as each version of it wrote it ---------------- */

const int32 = n => { const b = new Uint8Array(4); new DataView(b.buffer).setInt32(0, n, true); return [...b]; };
const text = s => { const e = new TextEncoder().encode(s); return [e.length, ...e]; };

/** The bytes "lib" held at version 1 to 6: collections (from version 3) and books */
function legacyLibrary(version, collections, books) {
  const out = [...'QLB'].map(c => c.charCodeAt(0));
  out.push(48 + version);
  if (version >= 3) {
    out.push(collections.length);
    for (const name of collections) out.push(...text(name));
  }
  for (const b of books) {
    out.push(...int32(b.idHigh), ...int32(b.idLow), ...text(b.title), ...text(b.author));
    out.push(...int32(b.shelf ?? 0), ...int32(b.added ?? 100), ...int32(b.opened ?? 0), ...int32(b.chapter ?? 0),
      ...int32(b.chapters ?? 0), ...int32(b.page ?? 0), ...int32(b.pages ?? 0), ...int32(b.anchor ?? -1),
      ...int32(b.size ?? 1000), ...int32((b.cover ?? 0) + (b.done ? 256 : 0)));
    if (version >= 2) out.push(...text(b.series ?? ''), ...int32(b.number ?? 0));
    if (version >= 3) out.push(...int32(b.collections ?? 0));
    if (version >= 4) out.push(...int32(b.minutes ?? 0), ...int32(b.pagesRead ?? 0), ...int32(b.finished ?? 0));
    if (version >= 5) out.push(...int32(b.shelfModified ?? 0), ...int32(b.collectionsModified ?? 0),
      ...int32(b.finishedModified ?? 0), ...int32(b.minutesElsewhere ?? 0), ...int32(b.pagesElsewhere ?? 0));
    if (version >= 6) out.push(...int32(b.placeModified ?? 0), ...int32(b.placeDeclined ?? 0));
  }
  return Uint8Array.from(out);
}

const hex7 = n => n.toString(16).padStart(7, '0');
const bookKey = b => `library/book/${hex7(b.idHigh)}${hex7(b.idLow)}`;

const books = [
  { idHigh: 0x1234567, idLow: 0x0abcdef, title: 'Alpha Tales', author: 'Ann Writer', series: 'First Series', number: 2, chapters: 9, chapter: 3, pages: 40, page: 7 },
  { idHigh: 0x2345678, idLow: 0x1bcdef0, title: 'Beta Notes', author: 'Bo Author', shelf: 1 },
  { idHigh: 0x3456789, idLow: 0x2cdef01, title: 'Gamma Days', author: 'Cy Penn', done: true, collections: 1 },
];

/* ---------------- the store, seen from the page ---------------- */

/** Every key of the store with its bytes as numbers */
async function store(page) {
  return page.evaluate(async () => {
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open('bats');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const [keys, values] = await new Promise((resolve, reject) => {
      const tx = db.transaction('kv', 'readonly');
      const keysRequest = tx.objectStore('kv').getAllKeys();
      const valuesRequest = tx.objectStore('kv').getAll();
      tx.oncomplete = () => resolve([keysRequest.result, valuesRequest.result]);
      tx.onerror = () => reject(tx.error);
    });
    db.close();
    const records = {};
    keys.forEach((key, i) => {
      const value = values[i];
      const bytes = value instanceof ArrayBuffer ? new Uint8Array(value) : new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
      records[key] = [...bytes];
    });
    return records;
  });
}

/** Puts bytes under key (null: deletes the key) */
async function put(page, key, bytes) {
  await page.evaluate(async ({ key, bytes }) => {
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open('bats');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    await new Promise((resolve, reject) => {
      const tx = db.transaction('kv', 'readwrite');
      if (bytes === null) tx.objectStore('kv').delete(key);
      else tx.objectStore('kv').put(Uint8Array.from(bytes), key);
      tx.oncomplete = resolve;
      tx.onerror = () => reject(tx.error);
    });
    db.close();
  }, { key, bytes });
}

/** Removes every record of the library (as before it was converted) */
async function forgetRecords(page) {
  for (const key of Object.keys(await store(page))) if (key.startsWith('library/')) await put(page, key, null);
}

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
    await shelf(page).click();
    await expect(shelf(page)).toHaveText('Hidden');
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
  await shelf(page).click();
  await expect(shelf(page)).toHaveText('Hidden');
  await bookMenu(page, 'Shared Book');
  await menuItem(page, 'Collections').click();
  await expect(page.getByRole('dialog', { name: 'Collections' }).getByRole('button', { name: 'Both', exact: true })).toHaveAttribute('aria-pressed', 'true');
});
