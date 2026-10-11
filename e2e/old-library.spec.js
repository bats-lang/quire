// A library written by an earlier build opens in this one with every book (#506, #497).
// e2e/old-libraries/<commit>.json is the whole IndexedDB of a build, made by importing three books
// through it (one hidden, one read a page into, a highlight made); never regenerated, so that no
// later change to the records, the imports or the reader can break an old reader's library unseen.
// 9ce1ae3 is the build just before #434: its records hold `prog` and `tdir` but no `snum`.

import { test, expect } from './fixtures.js';
import { readFileSync } from 'node:fs';
import { store, put, bookKey } from './legacy-library.js';
import {
  start, card, cards, reload, librarySettings, settingsButton, openBook, bookPage, openShelf, marks, toLibrary, bookMenu, menuItem,
} from './helpers.js';

const old = JSON.parse(readFileSync(new URL('./old-libraries/9ce1ae3.json', import.meta.url), 'utf8'));
const alert = page => page.getByRole('alert');

/** The app started with exactly the keys of the old build's store */
async function startWithOld(page) {
  await start(page);
  for (const key of Object.keys(await store(page))) await put(page, key, null);
  for (const [key, bytes] of Object.entries(old)) await put(page, key, bytes);
  await reload(page);
}

const tagsOf = record => {
  const tags = [];
  for (let at = 7; at + 8 <= record.length;) {
    tags.push(String.fromCharCode(...record.slice(at + 4, at + 8)));
    at += 12 + record[at] + record[at + 1] * 256 + record[at + 2] * 65536 + record[at + 3] * 16777216;
  }
  return tags;
};

test('a library written by build 9ce1ae3 opens with every book, nothing said, and nothing to set aside', async ({ page }) => {
  const bookKeys = Object.keys(old).filter(key => key.startsWith('library/book/'));
  expect(bookKeys).toHaveLength(3);
  for (const key of bookKeys) expect(tagsOf(old[key])).not.toContain('snum');
  await startWithOld(page);
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

test('a book of build 9ce1ae3 opens, its chapters read, its highlight and place are there, and a save writes the group it lacked', async ({ page }) => {
  await startWithOld(page);
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
  const gamma = Object.keys(old).find(key => key.startsWith('library/book/') && tagsOf(saved[key]).length && !tagsOf(old[key]).includes('snum') && JSON.stringify(saved[key]) !== JSON.stringify(old[key]));
  expect(gamma, 'a record was saved').toBeDefined();
  expect(tagsOf(saved[gamma])).toEqual(expect.arrayContaining(['prog', 'snum', 'tdir']));
  expect(Object.keys(saved).filter(key => key.startsWith('library/damaged/'))).toHaveLength(0);
  await expect(alert(page)).toBeHidden();
});
