// Small EPUBs for the selection specs (e2e/touch-selection.spec.js). Each is
// checked by epubcheck (e2e/epubcheck.spec.js) and must be valid.

import { solidPng } from './create-epub.js';

const words = 'lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor ';
const filler = Array.from({ length: 12 }, (_, k) => `<p>Filler ${k} ${words.repeat(10)}</p>`).join('');

export const selectionBooks = {
  /** Plain prose, long enough for several pages: words to press on, lines
      to extend over, and a page whose last line can be reached */
  prose: { valid: true, opts: {
    title: 'Selection Prose', author: 'Selection Tests',
    rawChapters: [
      { body: '<h1>Prose</h1>' + Array.from({ length: 14 }, (_, k) => `<p>Prose ${k} ${words.repeat(9)}</p>`).join('') },
      { body: '<h1>More</h1>' + filler },
    ], toc: [{ label: 'Prose', href: 'chapter1.xhtml' }, { label: 'More', href: 'chapter2.xhtml' }] } },

  /** A picture between two paragraphs on one page: a selection from the
      one to the other crosses the image */
  picture: { valid: true, opts: {
    title: 'Selection Picture', author: 'Selection Tests',
    rawChapters: [
      { body: '<h1>Picture</h1><p>Before the picture there are some words to start a selection in.</p>' +
          '<p><img src="images/map.png" alt="the map"/></p>' +
          '<p>After the picture there are some more words to end a selection in.</p>' + filler },
    ],
    toc: [{ label: 'Picture', href: 'chapter1.xhtml' }],
    extraImages: [{ name: 'images/map.png', data: solidPng(120, 120) }] } },

  /** A note reference, and the footnote it opens in a popup */
  footnote: { valid: true, opts: {
    title: 'Selection Footnote', author: 'Selection Tests',
    rawChapters: [
      { body: '<h1>Footnote</h1><p>A claim<a epub:type="noteref" href="#n1">1</a> with words after it to press on.</p>' + filler +
          '<aside epub:type="footnote" id="n1"><p>The note has several words that a reader may select inside it.</p></aside>' },
    ], toc: [{ label: 'Footnote', href: 'chapter1.xhtml' }] } },
};
