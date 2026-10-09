// Small EPUBs for how far through the book the reader is (#426): chapters
// of equal and of very unequal length, back matter after the text, front
// matter before it, and fixed pages. Each is checked by epubcheck
// (e2e/epubcheck.spec.js) and read by e2e/progress.spec.js. A chapter's
// text is made of paragraphs of one size, so a chapter's bytes are a
// number of paragraphs, and the weights the reader uses (the entries'
// sizes in the archive; the specs store the chapters) are known.

import { solidPng } from './create-epub.js';

/** A paragraph of about 330 bytes, findable by its tag */
const paragraph = (tag, i, k) => `<p>${tag} ${i}.${k} ` + 'lorem ipsum dolor sit amet '.repeat(12) + '</p>';

/** Chapter i's body: a heading and count paragraphs */
export const textBody = (i, count, tag = 'Para') =>
  `<h1>Part ${i}</h1>\n` + Array.from({ length: count }, (_, k) => paragraph(tag, i, k)).join('\n');

/** A section of back matter (EPUB structural semantics: backmatter), of count paragraphs */
export const backBody = (i, kind, count) =>
  `<section xmlns:epub="http://www.idpf.org/2007/ops" epub:type="backmatter ${kind}">\n<h1>${kind} ${i}</h1>\n` +
  Array.from({ length: count }, (_, k) => paragraph(kind, i, k)).join('\n') + '\n</section>';

export const progressBooks = {
  /** Three chapters of one size: their ends are about a third, two thirds and all of the book */
  threeEqual: { valid: true, opts: {
    title: 'Three Equal', author: 'Progress Tests',
    rawChapters: [1, 2, 3].map(i => ({ body: textBody(i, 40) })) } },

  /** Three chapters of text, then notes, an index and a colophon, which the landmarks name as back matter */
  backMatter: { valid: true, opts: {
    title: 'Back Matter', author: 'Progress Tests',
    rawChapters: [
      ...[1, 2, 3].map(i => ({ body: textBody(i, 40) })),
      { body: backBody(4, 'notes', 40) }, { body: backBody(5, 'index', 40) }, { body: backBody(6, 'colophon', 40) },
    ],
    landmarks: [
      { type: 'bodymatter', label: 'Start of Content', href: 'chapter1.xhtml' },
      { type: 'backmatter', label: 'Notes', href: 'chapter4.xhtml' },
    ] } },

  /** A cover, a title page and a copyright page before three chapters of text, no landmarks */
  frontMatter: { valid: true, opts: {
    title: 'Front Matter', author: 'Progress Tests',
    rawChapters: [
      { body: textBody(0, 0, 'Cover') }, { body: textBody(0, 1, 'Title') }, { body: textBody(0, 1, 'Copyright') },
      ...[1, 2, 3].map(i => ({ body: textBody(i, 40) })),
    ] } },

  /** The same, its landmarks naming where the text starts, so that it opens there */
  frontMatterLandmarks: { valid: true, opts: {
    title: 'Front Landmarks', author: 'Progress Tests',
    rawChapters: [
      { body: textBody(0, 0, 'Cover') }, { body: textBody(0, 1, 'Title') }, { body: textBody(0, 1, 'Copyright') },
      ...[1, 2, 3].map(i => ({ body: textBody(i, 40) })),
    ],
    landmarks: [{ type: 'bodymatter', label: 'Start of Content', href: 'chapter4.xhtml' }] } },

  /** One chapter of about 100 KB, then nine of about 1 KB */
  unequal: { valid: true, opts: {
    title: 'Unequal Chapters', author: 'Progress Tests',
    rawChapters: [{ body: textBody(1, 300) }, ...Array.from({ length: 9 }, (_, k) => ({ body: textBody(k + 2, 3) }))] } },

  /** Five fixed pages, the first with 30 KB of comment in it: bytes would put the second page at 90% */
  fixedUnequal: { valid: true, opts: fixedBook('Fixed Unequal', 5, 30000) },
};

/** A fixed-layout book of count pages (a page an image of its own size) whose first page carries comment bytes of comment */
function fixedBook(title, count, comment) {
  return {
    title, author: 'Progress Tests', chapters: count,
    metadata: '<meta property="rendition:layout">pre-paginated</meta>\n<meta property="rendition:spread">none</meta>\n',
    rawChapters: Array.from({ length: count }, (_, k) => ({
      head: '<meta name="viewport" content="width=600, height=800"/>',
      body: `<div><img src="images/page${k + 1}.png" alt="Page ${k + 1}"/></div>` +
        (k === 0 ? `\n<!-- ${'filler '.repeat(Math.ceil(comment / 7))} -->` : ''),
    })),
    extraImages: Array.from({ length: count }, (_, k) => ({ name: `images/page${k + 1}.png`, data: solidPng(1200, 1600) })),
  };
}
