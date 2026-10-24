// A book's id is the SHA-256 of its file (its first 14 hex digits), and the same file
// always has the same id (keyword: book id, #834). The app hashes with sha256's proved
// code; this book is several MB, so the hash runs over several chunks and a partial
// last one, and its id is the one the fast code gave on the commit before the move.

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { test, expect } from './fixtures.js';
import { start, epubFile, importFiles, card } from './helpers.js';
import { randomBytes } from './create-epub.js';
import { store } from './legacy-library.js';

// The id of the book below that the fast API (sha256's hash, init, update and finish)
// gave on the base commit of #834, in the library's key `library/book/<id>`.
const FAST_ID = '74b6a0408d9787';

// 3 MiB and 345 bytes of padding: three full 1 MiB chunks and a tail
const PADDING = 3 * 1024 * 1024 + 345;

const bookKeys = async page => Object.keys(await store(page)).filter(key => key.startsWith('library/book/'));

test('a book of several MB has the id the fast SHA-256 gave it', async ({ page }) => {
  const path = epubFile({
    title: 'Large Book',
    identifier: 'urn:quire:book-id-834',
    extraFiles: [{ name: 'padding.bin', data: randomBytes(PADDING), mediaType: 'application/octet-stream', store: true }],
  });
  const file = readFileSync(path);
  expect(file.length).toBeGreaterThan(3 * 1024 * 1024);
  // the file is the one the fast code hashed
  expect(createHash('sha256').update(file).digest('hex').slice(0, 14)).toBe(FAST_ID);
  await start(page);
  await importFiles(page, [path], 1);
  await expect(card(page, 'Large Book')).toBeVisible();
  expect(await bookKeys(page)).toEqual([`library/book/${FAST_ID}`]);
});
