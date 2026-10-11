// The books the replace specs import (replace.spec.js and
// replace-corrected.spec.js, quire#425), all one book to the reader: the
// title "Replace Me" by "Replace Tests". Checked by epubcheck
// (e2e/epubcheck.spec.js) as the other fixture books are.
//
// The first is the book as it was first got: three chapters of sixty
// paragraphs, so the places in it are far apart, and a cover, so a
// replaced book has one to keep. The others are corrected files of it:
//
//  * corrected: chapter 2's text is another (the same paragraphs, their
//    words changed), chapter 3 is cut to its first twenty paragraphs, and
//    the cover is another picture;
//  * restructured: chapter 1 is gone, a foreword is added before the
//    others, and chapters 3 and 2 change places (their text is the same).

import { chapters, chapterBody } from './helpers.js';
import { solidPng } from './create-epub.js';

export const replaceBook = {
  title: 'Replace Me', author: 'Replace Tests', coverImage: true, rawChapters: chapters(3, 60),
};

/** The cover of the corrected book: another picture than the first's */
export const correctedCover = solidPng(8, 8, [200, 40, 40]);

export const correctedBook = {
  title: 'Replace Me', author: 'Replace Tests', coverImage: true, coverBytes: correctedCover,
  rawChapters: [
    { body: chapterBody(1, 60) },
    { body: chapterBody(2, 60, 'Fixed') },
    { body: chapterBody(3, 20) },
  ],
};

/** A chapter given its own file name, so it keeps its name wherever the
    book puts it */
const named = (file, body) => ({ file, body });

const restructuredChapters = [
  named('foreword.xhtml', chapterBody(0, 12, 'Intro')),
  named('chapter3.xhtml', chapterBody(3, 60)),
  named('chapter2.xhtml', chapterBody(2, 60)),
];

export const restructuredBook = {
  title: 'Replace Me', author: 'Replace Tests', coverImage: true,
  rawChapters: restructuredChapters,
  toc: [
    { label: 'Foreword', href: 'foreword.xhtml' },
    { label: 'Chapter 3', href: 'chapter3.xhtml' },
    { label: 'Chapter 2', href: 'chapter2.xhtml' },
  ],
};

export const replaceBooks = {
  'replace me': { valid: true, opts: { storeChapters: true, ...replaceBook } },
  'replace me corrected': { valid: true, opts: { storeChapters: true, ...correctedBook } },
  'replace me restructured': { valid: true, opts: { storeChapters: true, ...restructuredBook } },
};
