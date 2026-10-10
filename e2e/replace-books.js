// The book the replace specs import twice (replace.spec.js, quire#425):
// three chapters of sixty paragraphs, so the places in it are far apart,
// and a cover, so a replaced book has one to keep. Checked by epubcheck
// (e2e/epubcheck.spec.js) as the other fixture books are.

import { chapters } from './helpers.js';

export const replaceBook = {
  title: 'Replace Me', author: 'Replace Tests', coverImage: true, rawChapters: chapters(3, 60),
};

export const replaceBooks = {
  'replace me': { valid: true, opts: { storeChapters: true, ...replaceBook } },
};
