// The book the sync specs' devices hold (sync-idempotent.spec.js): checked
// by epubcheck (e2e/epubcheck.spec.js) as the landmark books are.

import { chapters } from './helpers.js';

/** Four chapters of paragraphs "Para 1.0" ... */
export const sharedBook = { title: 'Shared Book', author: 'Sync Tests', chapters: 4, rawChapters: chapters(4) };

export const syncBooks = {
  'shared book': { valid: true, opts: { storeChapters: true, ...sharedBook } },
};
