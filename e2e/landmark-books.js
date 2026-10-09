// Small EPUBs whose landmarks (EPUB 3.3 5.4.1.2, or EPUB 2's <guide>) say
// where reading starts. Each is checked by epubcheck (e2e/epubcheck.spec.js):
// `valid` ones must pass it; an invalid one is invalid on purpose, and
// `errors` names the only messages it may give.

const section = (id, text) => ({ body: `<h1 id="${id}">${text}</h1>\n<p>${text} ` + 'lorem ipsum dolor sit amet '.repeat(8) + '</p>' });

// a cover, a contents page and a copyright page, then the body: the
// spine items are chapter1 to chapter5.xhtml
const chapters = [
  section('cover', 'Cover page'),
  section('contents', 'Contents page'),
  section('copyright', 'Copyright page'),
  section('begin', 'Body begins here'),
  section('second', 'Second chapter'),
];
const toc = [
  { label: 'Cover', href: 'chapter1.xhtml' },
  { label: 'Contents', href: 'chapter2.xhtml' },
  { label: 'Copyright', href: 'chapter3.xhtml' },
  { label: 'Body begins here', href: 'chapter4.xhtml' },
  { label: 'Second chapter', href: 'chapter5.xhtml' },
];
const frontLandmarks = [
  { type: 'cover', label: 'Cover', href: 'chapter1.xhtml' },
  { type: 'toc', label: 'Table of Contents', href: 'chapter2.xhtml' },
];
const book = (title, more) => ({ title, author: 'Landmarks', rawChapters: chapters, toc, ...more });

export const landmarkBooks = {
  /** A landmarks nav names the body matter: the book opens there first */
  startsAtBody: { valid: true, opts: book('Starts at the body', {
    landmarks: [...frontLandmarks, { type: 'bodymatter', label: 'Start of Content', href: 'chapter4.xhtml#begin' }] }) },

  /** A landmarks nav that names no body matter: the first spine item */
  noBodyMatter: { valid: true, opts: book('No body matter', { landmarks: frontLandmarks }) },

  /** An EPUB 2 book (an NCX and a guide) whose guide names the text */
  guideText: { valid: true, opts: book('Guide text', {
    epub2: true,
    guide: [
      { type: 'cover', title: 'Cover', href: 'chapter1.xhtml' },
      { type: 'toc', title: 'Contents', href: 'chapter2.xhtml' },
      { type: 'text', title: 'Start of Content', href: 'chapter4.xhtml' },
    ] }) },

  /** The body matter's landmark has no href (an <a> without one is valid) */
  startWithoutHref: { valid: true, opts: book('Start without href', {
    landmarks: [...frontLandmarks, { type: 'bodymatter', label: 'Start of Content' }] }) },

  /** The body matter's landmark names a file the book does not have */
  startMissing: { valid: false, errors: ['RSC-007'], opts: book('Start missing', {
    landmarks: [...frontLandmarks, { type: 'bodymatter', label: 'Start of Content', href: 'missing.xhtml' }] }) },

  /** The body matter's landmark names a place outside the book */
  startOutside: { valid: false, errors: ['RSC-007', 'RSC-026'], opts: book('Start outside', {
    landmarks: [...frontLandmarks, { type: 'bodymatter', label: 'Start of Content', href: '../../outside.xhtml' }] }) },
};
