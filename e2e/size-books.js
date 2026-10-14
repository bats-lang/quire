// EPUB 3 books whose publishers chose different sizes for the same text and
// structure (#431): the reader's Size setting means the reading size in every
// book, and every other size in a book keeps its proportion to its body text.
// Each is checked by epubcheck (e2e/epubcheck.spec.js); `valid` ones must
// pass, the legacy one (an obsolete <font size>, by its entry) may give only
// the errors it lists.
//
// Book A sets its body text in a two step relative chain, the usual "62.5%
// rem trick": html{font-size:62.5%} makes 1rem 10px and p{font-size:1.6rem}
// 16px. (The decision record on the issue wrote the 62.5% on body, where rem
// does not follow it: p would be 1.6 * 16px = 25.6px; rem is the root
// element's size, so the trick is on html.)
// Book B sets everything in points, with a class, and a caption in pixels
// inline. Proportions to the body text, the same in both: h1 2, h2 1.5, small
// 0.8 (B: 18pt, 13.5pt and 7.2pt over 9pt), the lead paragraph 1.25.

const filler = 'lorem ipsum dolor sit amet '.repeat(12);
const chapter = (head, body) => ({ head, body });

// the same text in both books; only the styles and the dedication's markup differ
const text = (dedication) =>
  `<h1 id="title">A Title</h1>\n<h2 id="subtitle">A Subtitle</h2>\n` +
  `<p id="dedication">${dedication}</p>\n` +
  `<p id="lead" class="lead">The opening paragraph. ${filler}</p>\n` +
  `<p id="body1">Body text of the first paragraph. ${filler}</p>\n` +
  `<p id="body2">Body text of the second paragraph. ${filler}</p>\n` +
  `<p id="caption" class="caption">A caption under a picture.</p>\n` +
  `<p id="body3">Body text after the caption. ${filler}${filler}</p>`;
const more = `<h1 id="title2">Another Title</h1>\n<p id="body4">Body text of the second chapter. ${filler}${filler}</p>\n<h2 id="subtitle2">Another Subtitle</h2>\n<p id="body5">More body text. ${filler}</p>`;

const toc = [{ label: 'First', href: 'chapter1.xhtml' }, { label: 'Second', href: 'chapter2.xhtml' }];

// book A's heading and lead sizes are in rem, because em would be of the body's
// 10px (html 62.5%): 3.2rem is 32px, 2 times the 16px of the text
const styleA = '<style>html{font-size:62.5%} p{font-size:1.6rem} h1{font-size:3.2rem} h2{font-size:2.4rem} small{font-size:.8em} .lead{font-size:2rem}</style>';
const styleB = '<style>p{font-size:9pt} h1{font-size:18pt} h2{font-size:13.5pt} small{font-size:7.2pt} .lead{font-size:11.25pt}</style>';

export const sizeBooks = {
  /** body text in a relative chain (html 62.5%, p 1.6rem: 16px) */
  relative: { valid: true, opts: {
    title: 'Relative sizes', author: 'Sizing', toc,
    rawChapters: [
      chapter(styleA, text('<small>For the reader, with thanks.</small>')),
      chapter(styleA, more)] } },

  /** body text in points, a lead paragraph in a class, a caption in pixels inline */
  absolute: { valid: true, opts: {
    title: 'Absolute sizes', author: 'Sizing', toc,
    rawChapters: [
      chapter(styleB, text('<small>For the reader, with thanks.</small>').replace('class="caption"', 'class="caption" style="font-size:8px"')),
      chapter(styleB, more)] } },

  /** the same, the dedication in an obsolete <font size="1"> (not valid HTML 5) */
  legacy: { valid: false, errors: ['RSC-005'], opts: {
    title: 'Legacy sizes', author: 'Sizing', toc,
    rawChapters: [
      chapter(styleB, text('<font size="1">For the reader, with thanks.</font>').replace('class="caption"', 'class="caption" style="font-size:8px"')),
      chapter(styleB, more)] } },

  // The size most of the text is set in, put in other places (quire#431): on
  // body alone, on a div of a class, by html and rem, and by calc() and
  // clamp(), which are not read (the text keeps the size of its parent)

  /** body{font-size:20px}: the paragraphs inherit it, h1 is 2em of it */
  onBody: { valid: true, opts: {
    title: 'Sizes on body', author: 'Sizing', toc,
    rawChapters: [
      chapter('<style>body{font-size:20px} h1{font-size:2em}</style>', text('For the reader.')),
      chapter('<style>body{font-size:20px} h1{font-size:2em}</style>', more)] } },

  /** div.chapter{font-size:13px}: the whole chapter is in one div */
  onDiv: { valid: true, opts: {
    title: 'Sizes on a div', author: 'Sizing', toc,
    rawChapters: [
      chapter('<style>div.chapter{font-size:13px} div.chapter h1{font-size:2em}</style>', `<div class="chapter">${text('For the reader.')}</div>`),
      chapter('<style>div.chapter{font-size:13px} div.chapter h1{font-size:2em}</style>', `<div class="chapter">${more}</div>`)] } },

  /** html{font-size:125%} with the text in 1rem (20px) */
  onHtml: { valid: true, opts: {
    title: 'Sizes by html and rem', author: 'Sizing', toc,
    rawChapters: [
      chapter('<style>html{font-size:125%} p{font-size:1rem} h1{font-size:2rem}</style>', text('For the reader.')),
      chapter('<style>html{font-size:125%} p{font-size:1rem} h1{font-size:2rem}</style>', more)] } },

  /** sizes calc() gives are not read: the text is the parent's 16px, h1 2em of it */
  onCalc: { valid: true, opts: {
    title: 'Sizes by calc', author: 'Sizing', toc,
    rawChapters: [
      chapter('<style>p{font-size:calc(1rem + 2px)} h1{font-size:2em}</style>', text('For the reader.')),
      chapter('<style>p{font-size:calc(1rem + 2px)} h1{font-size:2em}</style>', more)] } },

  /** a part title page, all headings, before the chapter: its sizes are the book's, not a scale of its own */
  partTitle: { valid: true, opts: {
    title: 'A part title page', author: 'Sizing', toc,
    rawChapters: [
      chapter('<style>p{font-size:10pt} h1{font-size:30pt} h2{font-size:20pt}</style>',
        '<h1 id="part">Part One</h1>\n<h2 id="partsub">In which things begin</h2>'),
      chapter('<style>p{font-size:10pt} h1{font-size:30pt} h2{font-size:20pt}</style>', more)] } },

  /** a 1px and a 400% rule: held to half and three times the text */
  extremes: { valid: true, opts: {
    title: 'Extreme sizes', author: 'Sizing', toc,
    rawChapters: [
      chapter('<style>p{font-size:12px} .tiny{font-size:1px} .huge{font-size:400%}</style>',
        `<p id="body1">Body text of the first paragraph. ${filler}${filler}</p>\n<p id="tiny" class="tiny">A tiny paragraph.</p>\n<p id="huge" class="huge">A huge one.</p>`),
      chapter('<style>p{font-size:12px}</style>', more)] } },

  /** a book that sets a size and every other thing: only the size is read */
  everything: { valid: true, opts: {
    title: 'Everything set', author: 'Sizing', toc,
    rawChapters: [
      chapter('<style>p{font-size:11pt;color:#ff0000;background-color:#00ff00;font-family:Courier,monospace;margin:40px;line-height:3 !important;text-align:right}</style>',
        text('For the reader.')),
      chapter('<style>p{font-size:11pt}</style>', more)] } },

  /** a book that sets no size at all */
  unsized: { valid: true, opts: {
    title: 'No sizes', author: 'Sizing', toc,
    rawChapters: [chapter('', text('For the reader.')), chapter('', more)] } },

  /** the text is in a linked sheet, a stored one and the chapter's own style on top */
  linked: { valid: true, opts: {
    title: 'A linked sheet', author: 'Sizing', toc,
    extraFiles: [{ name: 'sizes.css', data: 'p{font-size:9pt} h1{font-size:18pt}', mediaType: 'text/css', store: false }],
    rawChapters: [
      chapter('<link rel="stylesheet" type="text/css" href="sizes.css"/><style>h2{font-size:13.5pt}</style>', text('For the reader.')),
      chapter('<link rel="stylesheet" type="text/css" href="sizes.css"/>', more)] } },
};

