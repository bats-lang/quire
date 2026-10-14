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

const styleA = '<style>html{font-size:62.5%} p{font-size:1.6rem} h1{font-size:2em} h2{font-size:1.5em} small{font-size:.8em} .lead{font-size:1.25em}</style>';
const styleB = '<style>p{font-size:9pt} h1{font-size:18pt} h2{font-size:13.5pt} small{font-size:7.2pt} .lead{font-size:1.25em}</style>';

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
};
