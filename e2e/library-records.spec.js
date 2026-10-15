// The library is kept as a record for each book and one for the
// collections (#354): the old whole-library record "lib" is converted to
// them once and never changed; a change is saved in the records it
// concerns, in the groups it changed; a record that is damaged or newer
// is never shown wrong and never written over.

import { test, expect } from './fixtures.js';
import { legacyLibrary, hex7, bookKey, store, put, forgetRecords, syncEnded, reloadSettled } from './legacy-library.js';
import {
  start, epubFile, importFiles, card, cards, titles, bookMenu, menuItem, dialog, reload,
  librarySettings, settingsButton, settingsScreen, openShelf, emptyTrash,
} from './helpers.js';
import { seriesBooks } from './series-books.js';

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
  await syncEnded(page);
  await forgetRecords(page);
  await put(page, 'lib', [...legacyLibrary(version, ['To read', 'Shared'], library)]);
  await reloadSettled(page);
  await recordsWritten(page, library);
}

/** The records the conversion of "lib" makes are in the store */
async function recordsWritten(page, library) {
  for (const book of library) await expect.poll(async () => (await store(page))[bookKey(book)] !== undefined, { message: `the record of ${book.title} is written` }).toBe(true);
}

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const bookId = `${hex7(books[0].idHigh)}${hex7(books[0].idLow)}`;

for (let version = 1; version <= 6; version++) {
  test(`a library kept as QLB${version} is converted to records, and its record is not changed`, async ({ page }) => {
    await startWithLegacy(page, version);
    // the books on the shelf are shown (Beta Notes is hidden)
    await expect(cards(page)).toHaveCount(2);
    expect(await titles(page)).toEqual(expect.arrayContaining(['Alpha Tales', 'Gamma Days']));
    await expect(card(page, 'Alpha Tales')).toContainText('Ann Writer');
    if (version >= 2) await expect(card(page, 'Alpha Tales')).toContainText('First Series · 2');
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
  // the book's record, the version of it before (#510) and when it was written: nothing of any other book
  expect(changed.sort()).toEqual([bookKey(books[0]), `library/previous/${bookId}`, `library/stamp/${bookId}`].sort());
  expect(same(after[`library/previous/${bookId}`], before[bookKey(books[0])])).toBe(true);
  expect(same(after.lib, before.lib)).toBe(true);
  // the other records are the very bytes that were there
  expect(same(after[bookKey(books[2])], before[bookKey(books[2])])).toBe(true);
  expect(same(after['library/index'], before['library/index'])).toBe(true);
});

test('removing the Trash\'s books deletes their records', async ({ page }) => {
  await startWithLegacy(page, 6, [books[0], { ...books[1], shelf: 3 }, books[2]]);
  await expect(cards(page)).toHaveCount(2);
  await emptyTrash(page);
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
  await reloadSettled(page);
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
  await reloadSettled(page);
  await librarySettings(page);
  await expect(setAside(page)).toBeHidden();
  expect(same((await store(page))[bookKey(books[0])], newer)).toBe(true);
});

// #515: the row is offered for a record that cannot be read as a record at all, and only for one
for (const [how, spoil] of [
  ['is not Quire\'s (its first four bytes are not QREC)', record => { const bytes = record.slice(); bytes[0] ^= 0x5a; return bytes; }],
  ['is cut short in its framing', record => record.slice(0, 11)],
]) {
  test(`a book record that ${how} is offered to be set aside, its bytes kept, and the other book is untouched (#515)`, async ({ page }) => {
    await startWithLegacy(page, 6);
    await expect(cards(page)).toHaveCount(2);
    const spoiled = spoil((await store(page))[bookKey(books[0])]);
    await put(page, bookKey(books[0]), spoiled);
    await reloadSettled(page);
    await expect(card(page, 'Alpha Tales')).toHaveCount(0);
    await expect(card(page, 'Gamma Days')).toBeVisible();
    // snapshot once the sync the app makes as it opens has ended (it renumbers the books' ORDR once a record is missing)
    const before = await store(page);
    await librarySettings(page);
    await expect(setAside(page)).toBeVisible();
    await setAside(page).click();
    await expect(setAside(page)).toBeHidden();
    const after = await store(page);
    expect(after[bookKey(books[0])]).toBeUndefined();
    const copies = damagedKeys(after, `${hex7(books[0].idHigh)}${hex7(books[0].idLow)}`);
    expect(copies).toHaveLength(1);
    expect(same(after[copies[0]], spoiled)).toBe(true);
    expect(same(after[bookKey(books[1])], before[bookKey(books[1])])).toBe(true);
  });
}

test('a set aside that is aborted midway leaves the old record byte for byte, and can be tried again', async ({ page }) => {
  await startWithLegacy(page, 6);
  await expect(cards(page)).toHaveCount(2);
  const damaged = (await store(page))[bookKey(books[0])].slice();
  damaged[10] ^= 0x5a;
  await put(page, bookKey(books[0]), damaged);
  await reloadSettled(page);
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

// The chunks of a record, by tag: "QREC", the kind, the version and the
// oldest that reads it, then each chunk as a u32 length, its tag, its
// data and a CRC-32 (a record's layout is in CLAUDE.md)
function chunks(record) {
  const out = [];
  for (let at = 7; at + 8 <= record.length;) {
    const length = record[at] + record[at + 1] * 256 + record[at + 2] * 65536 + record[at + 3] * 16777216;
    const tag = String.fromCharCode(...record.slice(at + 4, at + 8));
    out.push({ tag, start: at, end: at + 8 + length + 4, data: record.slice(at + 8, at + 8 + length) });
    at += 8 + length + 4;
  }
  return out;
}
const u32 = bytes => bytes[0] + bytes[1] * 256 + bytes[2] * 65536 + bytes[3] * 16777216;

test('a series position of 2.5 is kept in a group of its own, and the whole number in the group an older Quire reads (#434)', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile(seriesBooks['epub3 volume 2.5'].opts), epubFile(seriesBooks['written two point zero'].opts), epubFile(seriesBooks['written zero'].opts)], 3);
  await reload(page);
  const kept = await store(page);
  const records = Object.keys(kept).filter(key => key.startsWith('library/book/'));
  expect(records).toHaveLength(3);
  const found = [];
  for (const key of records) {
    const groups = chunks(kept[key]);
    const series = groups.find(g => g.tag === 'SERI').data;
    // the name (a length byte and its bytes), then the whole number
    const whole = u32(series.slice(series.length - 4));
    const snum = groups.find(g => g.tag === 'snum');
    found.push({ key, whole, snum: snum ? u32(snum.data) : 0, groups });
  }
  // 2.5: the whole number 2 for an older Quire, 250 plus the zero's 10000001 for this one
  expect(found.map(f => [f.whole, f.snum]).sort()).toEqual([[0, 10000001], [2, 10000251], [2, 0]].sort());
  // the card says 2.5 from the snum group, and a Quire that knows no snum keeps it (lower case: ancillary) and reads SERI's 2
  await expect(card(page, 'Three A Novella')).toContainText('Foundation · 2.5');
  // an older Quire, which knows no snum group, wrote the record without it (#497: the step dropped from #434):
  // it reads as numbered 2, whole, with nothing said, set aside or copied, and the 2.5 is not there
  const novella = found.find(f => f.snum === 10000251);
  const snumChunk = novella.groups.find(g => g.tag === 'snum');
  const older = Uint8Array.from([...kept[novella.key].slice(0, snumChunk.start), ...kept[novella.key].slice(snumChunk.end)]);
  await put(page, novella.key, older);
  await reload(page);
  await expect(card(page, 'Three A Novella')).toContainText('Foundation · 2');
  await expect(card(page, 'Three A Novella')).not.toContainText('2.5');
  await expect(alert(page)).toBeHidden();
  const opened = await store(page);
  expect(same(opened[novella.key], [...older])).toBe(true);
  expect(Object.keys(opened).filter(key => key.startsWith('library/damaged/'))).toHaveLength(0);
});

// A record written by a Quire before a group existed lacks it (#497): that is no loss and no damage. The
// groups that were added to the format after records were first written (record_tables.py, "added").
const addedGroups = ['prog', 'snum', 'tdir'];
const without = (record, tags) => {
  const cut = chunks(record).filter(g => tags.includes(g.tag));
  expect(cut.map(g => g.tag).sort(), 'the record holds the groups to cut').toEqual([...tags].sort());
  return Uint8Array.from([...record].filter((_, i) => !cut.some(g => i >= g.start && i < g.end)));
};
const tagsOf = record => chunks(record).map(g => g.tag);

for (const missing of [['prog'], ['snum'], ['tdir'], ['prog', 'snum'], ['prog', 'snum', 'tdir']]) {
  test(`a record written before ${missing.join(', ')} existed opens whole with nothing said, and its save writes ${missing.length > 1 ? 'them' : 'it'} (#497)`, async ({ page }) => {
    await startWithLegacy(page, 6);
    await expect(cards(page)).toHaveCount(2);
    const stored = await store(page);
    expect(addedGroups.every(tag => tagsOf(stored[bookKey(books[0])]).includes(tag))).toBe(true);
    const older = without(stored[bookKey(books[0])], missing);
    await put(page, bookKey(books[0]), older);
    await reload(page);
    // every book is shown with its details, there is no banner and no row to set anything aside
    await expect(cards(page)).toHaveCount(2);
    await expect(card(page, 'Alpha Tales')).toContainText('Ann Writer');
    await expect(card(page, 'Alpha Tales')).toContainText('First Series · 2');
    await expect(card(page, 'Gamma Days')).toBeVisible();
    await expect(alert(page)).toBeHidden();
    await librarySettings(page);
    await expect(setAside(page)).toBeHidden();
    // opening changed nothing and copied nothing
    const opened = await store(page);
    expect(same(opened[bookKey(books[0])], [...older])).toBe(true);
    expect(Object.keys(opened).filter(key => key.startsWith('library/damaged/'))).toHaveLength(0);
    // a change to the book saves its record with the groups it lacked, and its details are as they were
    await page.keyboard.press('Escape');
    await bookMenu(page, 'Alpha Tales');
    await menuItem(page, 'Hide').click();
    await reload(page);
    const saved = await store(page);
    for (const tag of addedGroups) expect(tagsOf(saved[bookKey(books[0])]), `${tag} is written`).toContain(tag);
    expect(Object.keys(saved).filter(key => key.startsWith('library/damaged/'))).toHaveLength(0);
    await openShelf(page, 'Hidden');
    await expect(card(page, 'Alpha Tales')).toContainText('First Series · 2');
    await expect(alert(page)).toBeHidden();
  });
}

test('a group that is there and damaged is still lost: the book opens with its defaults, and its save keeps the old bytes (#497)', async ({ page }) => {
  await startWithLegacy(page, 6);
  await expect(cards(page)).toHaveCount(2);
  const stored = await store(page);
  const damaged = stored[bookKey(books[0])].slice();
  const snum = chunks(damaged).find(g => g.tag === 'snum');
  // a byte of its data: the chunk's CRC no longer holds
  damaged[snum.start + 8] ^= 0x5a;
  await put(page, bookKey(books[0]), damaged);
  await reload(page);
  await expect(card(page, 'Alpha Tales')).toContainText('Ann Writer');
  // unlike a group that was never there, this is said
  await expect(alert(page)).toContainText('Some details of your library were damaged and show as defaults');
  expect(Object.keys(await store(page)).filter(key => key.startsWith('library/damaged/'))).toHaveLength(0);
  await bookMenu(page, 'Alpha Tales');
  await menuItem(page, 'Hide').click();
  await reload(page);
  const saved = await store(page);
  const copies = damagedKeys(saved, bookId);
  expect(copies).toHaveLength(1);
  expect(same(saved[copies[0]], damaged)).toBe(true);
  expect(tagsOf(saved[bookKey(books[0])])).toContain('snum');
});

// ---- a record is a set of chunks looked up by tag (#510) ----

/** The chunks of a record, each with its bytes whole (length, tag, data, CRC); the last is the end chunk */
const partsOf = record => chunks(record).map(one => ({ tag: one.tag, bytes: record.slice(one.start, one.end) }));
/** The record with the header of record and these parts */
const assemble = (record, parts) => [...record.slice(0, 7), ...parts.flatMap(part => part.bytes)];
/** The parts with extra ones put before the end chunk */
const before_end = (parts, extra) => [...parts.slice(0, -1), ...extra, parts[parts.length - 1]];
/** A seeded shuffle (the same orders on every run) */
function shuffled(items, seed) {
  const out = items.slice();
  let state = seed;
  for (let i = out.length - 1; i > 0; i--) {
    state = (state * 1103515245 + 12345) % 2147483648;
    const j = state % (i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}
/** A chunk of tag with data: length, tag, data and CRC-32 */
function makeChunk(tag, data) {
  const body = [...tag].map(c => c.charCodeAt(0)).concat(data);
  let crc = 0xffffffff;
  for (const b of body) { crc ^= b; for (let k = 0; k < 8; k++) crc = crc & 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1; }
  crc = (crc ^ 0xffffffff) >>> 0;
  const le = n => [n & 255, (n >>> 8) & 255, (n >>> 16) & 255, (n >>> 24) & 255];
  return { tag, bytes: [...le(data.length), ...body, ...le(crc)] };
}
const ascending = tags => tags.every((tag, i) => i === 0 || tags[i - 1] < tag);

test('a record with its chunks in any order opens as the same book, unchanged, and a save writes them in ascending order (#510)', async ({ page }) => {
  await startWithLegacy(page, 6);
  await expect(cards(page)).toHaveCount(2);
  const record = (await store(page))[bookKey(books[0])];
  const all = partsOf(record);
  const known = all.slice(0, -1);
  expect(all[all.length - 1].tag).toBe('IEND');
  const orders = [known.slice().reverse(), [...known.slice(1), known[0]], [known[known.length - 1], ...known.slice(0, -1)],
    ...[1, 2, 3, 4, 5, 6].map(seed => shuffled(known, seed))];
  for (const order of orders) {
    const reordered = assemble(record, [...order, all[all.length - 1]]);
    await put(page, bookKey(books[0]), reordered);
    await reloadSettled(page);
    await expect(card(page, 'Alpha Tales')).toContainText('Ann Writer');
    await expect(card(page, 'Alpha Tales')).toContainText('First Series · 2');
    await expect(alert(page)).toBeHidden();
    const opened = await store(page);
    // opening wrote nothing: no record changed, no copy kept
    expect(same(opened[bookKey(books[0])], reordered), order.map(part => part.tag).join()).toBe(true);
    expect(damagedKeys(opened, bookId)).toHaveLength(0);
  }
  // a save writes the chunks in ascending order, as one book, and nothing was damaged
  await put(page, bookKey(books[0]), assemble(record, [...known.slice().reverse(), all[all.length - 1]]));
  await reloadSettled(page);
  await bookMenu(page, 'Alpha Tales');
  await menuItem(page, 'Hide').click();
  await reload(page);
  const saved = await store(page);
  const tags = tagsOf(saved[bookKey(books[0])]);
  expect(ascending(tags.slice(0, -1))).toBe(true);
  expect(tags[tags.length - 1]).toBe('IEND');
  expect(tags).toEqual(tagsOf(record));
  expect(damagedKeys(saved, bookId)).toHaveLength(0);
  await expect(alert(page)).toBeHidden();
  await openShelf(page, 'Hidden');
  await expect(card(page, 'Alpha Tales')).toContainText('Ann Writer');
});

test('a group twice: the last whole chunk is used, the record is read with a loss, and a save writes one chunk and keeps the old bytes (#510)', async ({ page }) => {
  await startWithLegacy(page, 6);
  await expect(cards(page)).toHaveCount(2);
  const stored = await store(page);
  const record = stored[bookKey(books[0])];
  const parts = partsOf(record);
  // Beta's shelf chunk says hidden (shelf 1), Alpha's own says the main shelf
  const betaShelf = partsOf(stored[bookKey(books[1])]).find(part => part.tag === 'SHLF');
  const ownShelf = parts.find(part => part.tag === 'SHLF');
  expect(same(betaShelf.bytes, ownShelf.bytes)).toBe(false);

  // the own chunk after the other: the own is used
  const own_last = assemble(record, before_end(parts.filter(part => part.tag !== 'SHLF'), [betaShelf, ownShelf]));
  await put(page, bookKey(books[0]), own_last);
  await reloadSettled(page);
  await expect(card(page, 'Alpha Tales')).toContainText('Ann Writer');
  await expect(cards(page)).toHaveCount(2);
  // said, as a loss is
  await expect(alert(page)).toContainText('Some details of your library were damaged');
  expect(damagedKeys(await store(page), bookId)).toHaveLength(0);

  // the other chunk after the own: the other is used, and the book is on the hidden shelf
  const other_last = assemble(record, before_end(parts.filter(part => part.tag !== 'SHLF'), [ownShelf, betaShelf]));
  await put(page, bookKey(books[0]), other_last);
  await reloadSettled(page);
  await expect(cards(page)).toHaveCount(1);
  await expect(card(page, 'Alpha Tales')).toHaveCount(0);
  await expect(alert(page)).toContainText('Some details of your library were damaged');
  await openShelf(page, 'Hidden');
  await expect(card(page, 'Alpha Tales')).toBeVisible();
  expect(damagedKeys(await store(page), bookId)).toHaveLength(0);

  // a later copy that is damaged does not hide an earlier whole one
  const damagedShelf = { tag: 'SHLF', bytes: betaShelf.bytes.slice() };
  damagedShelf.bytes[8] ^= 0x5a;
  const bad_last = assemble(record, before_end(parts, [damagedShelf]));
  await put(page, bookKey(books[0]), bad_last);
  await reloadSettled(page);
  await expect(cards(page)).toHaveCount(2);
  await expect(card(page, 'Alpha Tales')).toContainText('Ann Writer');
  await expect(alert(page)).toContainText('Some details of your library were damaged');

  // a save writes the record whole, one chunk of each tag, and keeps the old bytes
  await put(page, bookKey(books[0]), own_last);
  await reloadSettled(page);
  await bookMenu(page, 'Alpha Tales');
  await menuItem(page, 'Hide').click();
  await reload(page);
  const saved = await store(page);
  const tags = tagsOf(saved[bookKey(books[0])]);
  expect(tags.filter(tag => tag === 'SHLF')).toHaveLength(1);
  expect(tags).toEqual(tagsOf(record));
  const copies = damagedKeys(saved, bookId);
  expect(copies).toHaveLength(1);
  expect(same(saved[copies[0]], own_last)).toBe(true);
});

test('a chunk this version does not know is kept whole, twice if it was there twice, and written after the groups (#510)', async ({ page }) => {
  await startWithLegacy(page, 6);
  await expect(cards(page)).toHaveCount(2);
  const record = (await store(page))[bookKey(books[0])];
  const parts = partsOf(record);
  // a newer Quire's chunk (a lower case first letter), once before the groups and twice among them
  const later = (tag, text) => makeChunk(tag, [...text].map(c => c.charCodeAt(0)));
  const first = later('newa', 'first'), second = later('newa', 'second');
  const mixed = assemble(record, [first, ...parts.slice(0, 3), second, ...parts.slice(3)]);
  await put(page, bookKey(books[0]), mixed);
  await reloadSettled(page);
  await expect(card(page, 'Alpha Tales')).toContainText('Ann Writer');
  await expect(alert(page)).toBeHidden();
  expect(same((await store(page))[bookKey(books[0])], mixed)).toBe(true);
  await bookMenu(page, 'Alpha Tales');
  await menuItem(page, 'Hide').click();
  await reload(page);
  const saved = await store(page);
  const tags = tagsOf(saved[bookKey(books[0])]);
  // the groups ascending, then both copies of the unknown chunk in the order they were in, then the end
  expect(tags.slice(0, -3)).toEqual(tagsOf(record).slice(0, -1));
  expect(tags.slice(-3)).toEqual(['newa', 'newa', 'IEND']);
  const kept = chunks(saved[bookKey(books[0])]).filter(one => one.tag === 'newa').map(one => String.fromCharCode(...one.data));
  expect(kept).toEqual(['first', 'second']);
  expect(damagedKeys(saved, bookId)).toHaveLength(0);
});

// ---- a group the record needs, lost (#510): the record is used, with the group's substitute ----

const le32 = bytes => bytes[0] + bytes[1] * 256 + bytes[2] * 65536 + bytes[3] * 16777216;

for (const group of ['AUTH', 'BOOK', 'TITL']) {
  for (const how of ['absent', 'damaged']) {
    test(`a record whose ${group} group is ${how} is used with the group's substitute, said once, and its save writes the group and keeps the old bytes (#510)`, async ({ page }) => {
      await startWithLegacy(page, 6);
      await expect(cards(page)).toHaveCount(2);
      const record = (await store(page))[bookKey(books[0])];
      const variant = assemble(record, partsOf(record).flatMap(part => {
        if (part.tag !== group) return [part];
        if (how === 'absent') return [];
        const bytes = part.bytes.slice();
        bytes[8] ^= 0x5a;
        return [{ tag: part.tag, bytes }];
      }));
      await put(page, bookKey(books[0]), variant);
      await reloadSettled(page);
      // the title is lost with its group: the word the contents panel uses for a label with none
      const shown = group === 'TITL' ? 'Untitled' : 'Alpha Tales';
      await expect(card(page, shown)).toBeVisible();
      if (group === 'AUTH') await expect(card(page, shown)).not.toContainText('Ann Writer');
      else await expect(card(page, shown)).toContainText('Ann Writer');
      await expect(cards(page)).toHaveCount(2);
      await expect(alert(page)).toContainText('Some details of your library were damaged');
      // nothing is unreadable: nothing to set aside, no copy yet, nothing written by opening
      await librarySettings(page);
      await expect(setAside(page)).toBeHidden();
      const opened = await store(page);
      // opening writes nothing; but on the android project the app syncs as it opens, and the save that makes
      // (the library's own) repairs a record that lost a group at once, keeping the bytes it had
      if (test.info().project.name !== 'android') {
        expect(same(opened[bookKey(books[0])], variant)).toBe(true);
        expect(damagedKeys(opened, bookId)).toHaveLength(0);
      }
      // a save writes the record whole, with the ids it is under, and keeps the bytes it had
      await reload(page);
      await bookMenu(page, shown);
      await menuItem(page, 'Hide').click();
      await reload(page);
      const saved = await store(page);
      const savedRecord = saved[bookKey(books[0])];
      expect(tagsOf(savedRecord)).toEqual(tagsOf(record));
      const ids = chunks(savedRecord).find(one => one.tag === 'BOOK').data;
      expect([le32(ids.slice(0, 4)), le32(ids.slice(4, 8))]).toEqual([books[0].idHigh, books[0].idLow]);
      const copies = damagedKeys(saved, bookId);
      expect(copies).toHaveLength(1);
      expect(same(saved[copies[0]], variant)).toBe(true);
    });
  }
}

test('a record under the key of another book than the ids it holds is the key\'s book, and its save writes the ids of the key (#510)', async ({ page }) => {
  await startWithLegacy(page, 6);
  await expect(cards(page)).toHaveCount(2);
  const record = (await store(page))[bookKey(books[0])];
  // the ids of a book that is not there
  const wrong = makeChunk('BOOK', [1, 0, 0, 0, 2, 0, 0, 0]);
  const variant = assemble(record, partsOf(record).map(part => (part.tag === 'BOOK' ? wrong : part)));
  await put(page, bookKey(books[0]), variant);
  await reloadSettled(page);
  await expect(card(page, 'Alpha Tales')).toContainText('Ann Writer');
  await expect(cards(page)).toHaveCount(2);
  await expect(alert(page)).toContainText('Some details of your library were damaged');
  expect(same((await store(page))[bookKey(books[0])], variant)).toBe(true);
  await bookMenu(page, 'Alpha Tales');
  await menuItem(page, 'Hide').click();
  await reload(page);
  const saved = await store(page);
  const ids = chunks(saved[bookKey(books[0])]).find(one => one.tag === 'BOOK').data;
  expect([le32(ids.slice(0, 4)), le32(ids.slice(4, 8))]).toEqual([books[0].idHigh, books[0].idLow]);
  const copies = damagedKeys(saved, bookId);
  expect(copies).toHaveLength(1);
  expect(same(saved[copies[0]], variant)).toBe(true);
});

// ---- the version before: a record is kept as it was before a save, once in a minute at most (#510) ----

/** The seconds since 2025 now, as a stamp's four bytes (little-endian) say them, minus ago seconds */
const stampBytes = ago => {
  const seconds = Math.floor(Date.now() / 1000) - 1735689600 - ago;
  return [seconds & 255, (seconds >>> 8) & 255, (seconds >>> 16) & 255, (seconds >>> 24) & 255];
};
const stampSeconds = bytes => bytes[0] + bytes[1] * 256 + bytes[2] * 65536 + bytes[3] * 16777216;

for (const [ago, rotates] of [[5, false], [600, true]]) {
  test(`a save ${rotates ? 'keeps the record as it was' : 'leaves the version before it as it was'} when the record was written ${ago} seconds ago (#510)`, async ({ page }) => {
    await startWithLegacy(page, 6);
    await expect(cards(page)).toHaveCount(2);
    const stored = await store(page);
    const record = stored[bookKey(books[0])];
    // a version before it that is some other record's bytes, and the time the record was written
    const marker = stored[bookKey(books[2])];
    await put(page, `library/previous/${bookId}`, marker);
    const written = stampBytes(ago);
    await put(page, `library/stamp/${bookId}`, written);
    await reloadSettled(page);
    await bookMenu(page, 'Alpha Tales');
    await menuItem(page, 'Hide').click();
    await expect.poll(async () => stampSeconds((await store(page))[`library/stamp/${bookId}`])).toBeGreaterThan(stampSeconds(written) + 1);
    const saved = await store(page);
    expect(same(saved[`library/previous/${bookId}`], rotates ? record : marker)).toBe(true);
    // the record is the new one
    expect(same(saved[bookKey(books[0])], record)).toBe(false);
    // nothing was damaged
    expect(damagedKeys(saved, bookId)).toHaveLength(0);
  });
}

test('a book whose record is broken beyond recovery is read from its previous version, and its save writes the record anew and keeps the bytes (#510)', async ({ page }) => {
  await startWithLegacy(page, 6);
  await expect(cards(page)).toHaveCount(2);
  // a save makes the previous version: the record as it was
  const record = (await store(page))[bookKey(books[0])];
  await bookMenu(page, 'Alpha Tales');
  await menuItem(page, 'Hide').click();
  await expect.poll(async () => (await store(page))[`library/previous/${bookId}`] !== undefined).toBe(true);
  await openShelf(page, 'Hidden');
  await bookMenu(page, 'Alpha Tales');
  await menuItem(page, 'Unhide').click();
  await expect.poll(async () => same((await store(page))[bookKey(books[0])], record)).toBe(false);
  // its record is broken so that it is no record (a length past the end)
  const current = (await store(page))[bookKey(books[0])].slice();
  const broken = current.slice();
  broken[10] ^= 0x5a;
  await put(page, bookKey(books[0]), broken);
  await reloadSettled(page);
  // the book is there, from the version before; nothing is offered to be set aside
  await expect(card(page, 'Alpha Tales')).toContainText('Ann Writer');
  await expect(cards(page)).toHaveCount(2);
  await expect(alert(page)).toContainText('Some details of your library were damaged');
  await librarySettings(page);
  await expect(setAside(page)).toBeHidden();
  // a save writes the record anew, and keeps the bytes it was
  await reload(page);
  await bookMenu(page, 'Alpha Tales');
  await menuItem(page, 'Hide').click();
  await expect.poll(async () => damagedKeys(await store(page), bookId).length).toBe(1);
  const saved = await store(page);
  expect(same(saved[damagedKeys(saved, bookId)[0]], broken)).toBe(true);
  expect(tagsOf(saved[bookKey(books[0])])).toEqual(tagsOf(record));
  await reload(page);
  await expect(alert(page)).toBeHidden();
  await openShelf(page, 'Hidden');
  await expect(card(page, 'Alpha Tales')).toContainText('Ann Writer');
});

test('emptying the Trash deletes the version before and the time written with the record (#510)', async ({ page }) => {
  await startWithLegacy(page, 6, [books[0], { ...books[1], shelf: 3 }, books[2]]);
  await expect(cards(page)).toHaveCount(2);
  const betaId = `${hex7(books[1].idHigh)}${hex7(books[1].idLow)}`;
  await put(page, `library/previous/${betaId}`, (await store(page))[bookKey(books[1])]);
  await put(page, `library/stamp/${betaId}`, stampBytes(5));
  await reloadSettled(page);
  await emptyTrash(page);
  await reload(page);
  const after = await store(page);
  expect(after[bookKey(books[1])]).toBeUndefined();
  expect(after[`library/previous/${betaId}`]).toBeUndefined();
  expect(after[`library/stamp/${betaId}`]).toBeUndefined();
  expect(after[bookKey(books[0])]).toBeDefined();
});
