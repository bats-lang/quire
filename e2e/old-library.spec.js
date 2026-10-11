// A library written by an earlier build opens in this one with every book (#506, #497, #515).
// e2e/old-libraries/<commit>.json is the whole IndexedDB of a build, made by importing three books
// through it (one hidden, one read a page into, a highlight made); never regenerated, so that no
// later change to the records, the imports or the reader can break an old reader's library unseen.
// 9ce1ae3 is the build just before #434: its records hold `prog` and `tdir` but no `snum`.
//
// Every table of the book record that ever shipped has a library here (SHAPES, one per prefix of
// RELEASES in scripts/record_tables.py, which tests/static/groups.py checks): the real one is cut
// of the groups a build before it did not write (a chunk's CRC covers its own tag and data only, so
// a record with chunks cut out is byte for byte what that build wrote), and a group a later table
// has is added the way the build wrote it (`prog` and `tdir` as the real library has them, `snum`
// with its default). The first table is a record of the twelve groups of #354.

import { test, expect } from './fixtures.js';
import { readFileSync } from 'node:fs';
import { store, put, bookKey, syncEnded, reloadSettled } from './legacy-library.js';
import {
  start, card, cards, reload, librarySettings, settingsButton, openBook, bookPage, openShelf, marks, toLibrary, bookMenu, menuItem,
} from './helpers.js';

// the groups each table added to the first one, in the order they were added
const SHAPES = [
  { name: 'the first table, twelve groups', groups: [] },
  { name: 'the table with prog (bb473e5)', groups: ['prog'] },
  { name: 'the table with prog and tdir (04dcf63, builds 9ce1ae3 and aaa5dce)', groups: ['prog', 'tdir'] },
  { name: 'the table with prog, tdir and snum (6002bcf, this build)', groups: ['prog', 'tdir', 'snum'] },
];
const ADDED = ['prog', 'snum', 'tdir'];

const real = JSON.parse(readFileSync(new URL('./old-libraries/9ce1ae3.json', import.meta.url), 'utf8'));
const alert = page => page.getByRole('alert');

const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc32 = bytes => {
  let c = 0xffffffff;
  for (const b of bytes) c = crcTable[(c ^ b) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
const le32 = n => [n & 255, (n >>> 8) & 255, (n >>> 16) & 255, (n >>> 24) & 255];

/** The chunks of a record: its tag and its bytes whole (length, tag, data, CRC) */
function chunksOf(record) {
  const out = [];
  for (let at = 7; at + 8 <= record.length;) {
    const length = record[at] + record[at + 1] * 256 + record[at + 2] * 65536 + record[at + 3] * 16777216;
    out.push({ tag: String.fromCharCode(...record.slice(at + 4, at + 8)), bytes: record.slice(at, at + 12 + length) });
    at += 12 + length;
  }
  return out;
}
const tagsOf = record => chunksOf(record).map(chunk => chunk.tag);

/** A chunk of tag with data */
const chunk = (tag, data) => {
  const body = [...tag].map(c => c.charCodeAt(0)).concat(data);
  return [...le32(data.length), ...body, ...le32(crc32(body))];
};

/** The record as the table with exactly these added groups wrote it: the real record (which has
    prog and tdir) without the added groups it does not have, with snum (its default, none) when it has it */
function asTable(record, groups) {
  const kept = chunksOf(record).filter(one => !ADDED.includes(one.tag) || groups.includes(one.tag));
  if (groups.includes('snum') && !kept.some(one => one.tag === 'snum')) kept.push({ tag: 'snum', bytes: chunk('snum', le32(0)) });
  const end = kept.filter(one => one.tag === 'IEND');
  const rest = kept.filter(one => one.tag !== 'IEND').sort((a, b) => (a.tag < b.tag ? -1 : 1));
  return [...record.slice(0, 7), ...[...rest, ...end].flatMap(one => one.bytes)];
}

/** The whole store of the real build, its book records as the table with groups wrote them */
const libraryOf = groups => Object.fromEntries(Object.entries(real).map(([key, bytes]) =>
  [key, key.startsWith('library/book/') ? asTable(bytes, groups) : bytes]));

/** The app started with exactly the keys of an old build's store */
async function startWithOld(page, old) {
  await start(page);
  await syncEnded(page);
  for (const key of Object.keys(await store(page))) await put(page, key, null);
  for (const [key, bytes] of Object.entries(old)) await put(page, key, bytes);
  await reloadSettled(page);
}

for (const { name, groups } of SHAPES) {
  const old = libraryOf(groups);
  const bookKeys = Object.keys(old).filter(key => key.startsWith('library/book/'));

  test(`a library written by ${name} opens with every book, nothing said, and nothing to set aside`, async ({ page }) => {
    expect(bookKeys).toHaveLength(3);
    if (groups.join() === 'prog,tdir') expect(old, 'the real build\'s library, cut and put back as it was').toEqual(real);
    for (const key of bookKeys) expect(tagsOf(old[key]).filter(tag => ADDED.includes(tag)).sort(), key).toEqual([...groups].sort());
    await startWithOld(page, old);
    await expect(cards(page)).toHaveCount(2);
    await expect(card(page, 'Old Alpha')).toContainText('Ann Old');
    await expect(card(page, 'Old Gamma')).toContainText('Cy Old');
    await openShelf(page, 'Hidden');
    await expect(card(page, 'Old Beta')).toBeVisible();
    await expect(alert(page)).toBeHidden();
    await librarySettings(page);
    await expect(settingsButton(page, 'Set aside unreadable records')).toBeHidden();
    // opening changed no record and kept no copy
    const opened = await store(page);
    for (const key of Object.keys(old)) expect(opened[key], key).toEqual(old[key]);
    expect(Object.keys(opened).filter(key => key.startsWith('library/damaged/'))).toHaveLength(0);
  });

  test(`a save of a library written by ${name} writes the current groups, and the books are as they were`, async ({ page }) => {
    await startWithOld(page, old);
    await expect(cards(page)).toHaveCount(2);
    await bookMenu(page, 'Old Gamma');
    await menuItem(page, 'Hide').click();
    await reload(page);
    const saved = await store(page);
    const changed = bookKeys.filter(key => JSON.stringify(saved[key]) !== JSON.stringify(old[key]));
    expect(changed, 'a record was saved').toHaveLength(1);
    expect(tagsOf(saved[changed[0]])).toEqual(expect.arrayContaining(ADDED));
    // the records not saved are as they were: opening and saving another book change none
    for (const key of bookKeys.filter(other => other !== changed[0])) expect(saved[key], key).toEqual(old[key]);
    expect(Object.keys(saved).filter(key => key.startsWith('library/damaged/'))).toHaveLength(0);
    await expect(alert(page)).toBeHidden();
    await expect(cards(page)).toHaveCount(1);
    await expect(card(page, 'Old Alpha')).toContainText('Ann Old');
    await librarySettings(page);
    await expect(settingsButton(page, 'Set aside unreadable records')).toBeHidden();
  });
}

const old = libraryOf(['prog', 'tdir']);

test('a book of build 9ce1ae3 opens, its chapters read, its highlight and place are there, and a save writes the group it lacked', async ({ page }) => {
  await startWithOld(page, old);
  await openBook(page, 'Old Alpha');
  await expect(bookPage(page)).toContainText('Para');
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'Para 1.0' });
  await expect(alert(page)).toBeHidden();
  await toLibrary(page);
  // a save of the book's record (a change to the book) writes every group
  await bookMenu(page, 'Old Gamma');
  await menuItem(page, 'Hide').click();
  await reload(page);
  const saved = await store(page);
  const gamma = Object.keys(old).find(key => key.startsWith('library/book/') && JSON.stringify(saved[key]) !== JSON.stringify(old[key]));
  expect(gamma, 'a record was saved').toBeDefined();
  expect(tagsOf(saved[gamma])).toEqual(expect.arrayContaining(['prog', 'snum', 'tdir']));
  expect(Object.keys(saved).filter(key => key.startsWith('library/damaged/'))).toHaveLength(0);
  await expect(alert(page)).toBeHidden();
});
