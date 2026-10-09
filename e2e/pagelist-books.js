// Small EPUB 3 books with print page lists (#415): duplicate and
// out-of-order labels, targets that are missing, very long lists, odd
// labels, and page breaks in the text with and without a list. Each is
// checked by epubcheck (e2e/epubcheck.spec.js): `valid` ones must pass; an
// invalid one is invalid on purpose, and `errors` names the only messages
// it may give.

const filler = 'lorem ipsum dolor sit amet '.repeat(12);
const para = (tag, k) => `<p>${tag} ${k} ${filler}</p>`;
const paras = (tag, n) => Array.from({ length: n }, (_, k) => para(tag, k)).join('\n');
/** A page break marker: an empty span titled with the page's label */
const brk = (id, label, type = 'epub:type="pagebreak"') => `<span ${type} id="${id}" title="${label}"></span>`;
const book = (title, more) => ({
  title, author: 'Pages',
  toc: more.rawChapters.map((_, k) => ({ label: `Chapter ${k + 1}`, href: `chapter${k + 1}.xhtml` })),
  ...more,
});

export const pagelistBooks = {
  /** Two entries labelled 12 (one in each chapter), each with its break */
  duplicates: { valid: true, opts: book('Duplicate labels', {
    rawChapters: [
      { body: `<h1>One</h1>\n${brk('a12', '12')}${paras('One', 14)}` },
      { body: `<h1>Two</h1>\n${brk('b12', '12')}${paras('Two', 14)}` },
    ],
    pageList: [{ label: '12', href: 'chapter1.xhtml#a12' }, { label: '12', href: 'chapter2.xhtml#b12' }] }) },

  /** i, ii, then 1, 2: in the book's order */
  romanThenArabic: { valid: true, opts: book('Roman then arabic', {
    rawChapters: [
      { body: `<h1>Front</h1>\n${brk('pi', 'i')}${paras('Front', 6)}${brk('pii', 'ii')}${paras('Front', 6)}` },
      { body: `<h1>Body</h1>\n${brk('p1', '1')}${paras('Body', 6)}${brk('p2', '2')}${paras('Body', 6)}` },
    ],
    pageList: [
      { label: 'i', href: 'chapter1.xhtml#pi' }, { label: 'ii', href: 'chapter1.xhtml#pii' },
      { label: '1', href: 'chapter2.xhtml#p1' }, { label: '2', href: 'chapter2.xhtml#p2' }] }) },

  /** One entry's target chapter and one's fragment are not in the book */
  missingTargets: { valid: false, errors: ['RSC-007', 'RSC-012'], opts: book('Missing targets', {
    rawChapters: [
      { body: `<h1>One</h1>\n${brk('p1', '1')}${paras('One', 10)}${brk('p2', '2')}${paras('One', 10)}` },
      { body: `<h1>Two</h1>\n${brk('p3', '3')}${paras('Two', 10)}` },
    ],
    pageList: [
      { label: '1', href: 'chapter1.xhtml#p1' },
      { label: '2', href: 'chapter9.xhtml#nowhere' },
      { label: '3', href: 'chapter1.xhtml#nothere' },
      { label: '4', href: 'chapter2.xhtml#p3' }] }) },

  /** A whole chapter as a page (no fragment) */
  wholeChapter: { valid: true, opts: book('Whole chapter target', {
    rawChapters: [
      { body: `<h1>One</h1>\n${paras('One', 8)}` },
      { body: `<h1>Two</h1>\n${paras('Two', 8)}` },
    ],
    pageList: [{ label: '1', href: 'chapter1.xhtml' }, { label: '9', href: 'chapter2.xhtml' }] }) },

  /** Entries out of reading order (a page list is the book's own order) */
  outOfOrder: { valid: true, opts: book('Out of order', {
    rawChapters: [
      { body: `<h1>One</h1>\n${brk('p5', '5')}${paras('One', 8)}${brk('p6', '6')}${paras('One', 8)}` },
      { body: `<h1>Two</h1>\n${brk('p1', '1')}${paras('Two', 8)}` },
    ],
    pageList: [
      { label: '6', href: 'chapter1.xhtml#p6' }, { label: '1', href: 'chapter2.xhtml#p1' }, { label: '5', href: 'chapter1.xhtml#p5' }] }) },

  /** Several hundred pages */
  long: { valid: true, opts: (() => {
    const count = 600;
    const body = Array.from({ length: count }, (_, k) => `${brk(`p${k + 1}`, String(k + 1))}<p>Page ${k + 1} text.</p>`).join('\n');
    return book('Six hundred pages', {
      rawChapters: [{ body: `<h1>Long</h1>\n${body}` }],
      pageList: Array.from({ length: count }, (_, k) => ({ label: String(k + 1), href: `chapter1.xhtml#p${k + 1}` })) });
  })() },

  /** A page-list nav with no entries (an empty <ol> is invalid) */
  emptyList: { valid: false, errors: ['RSC-005'], opts: book('Empty page list', {
    rawChapters: [{ body: `<h1>One</h1>\n${paras('One', 6)}` }], pageList: [], emptyPageNav: true }) },

  /** A Devanagari numeral, an empty label and one of 200 characters */
  oddLabels: { valid: true, opts: book('Odd labels', {
    rawChapters: [{ body: `<h1>One</h1>\n${brk('pa', '१')}${paras('One', 5)}${brk('pb', ' ')}${paras('One', 5)}${brk('pc', 'x')}${paras('One', 5)}` }],
    pageList: [
      { label: '१', href: 'chapter1.xhtml#pa' },
      { label: '&#160;', href: 'chapter1.xhtml#pb' },
      { label: 'Plate 12, the long label '.repeat(8).slice(0, 200).trim(), href: 'chapter1.xhtml#pc' }] }) },

  /** doc-pagebreak markers without epub:type, in a book with no page list */
  roleOnly: { valid: true, opts: book('Role only', {
    rawChapters: [{ body: `<h1>One</h1>\n${brk('p7', '7', 'role="doc-pagebreak"')}${paras('One', 14)}${brk('p8', '8', 'role="doc-pagebreak"')}${paras('One', 14)}` }] }) },

  /** A page list whose targets are ordinary elements, not page breaks */
  noBreaks: { valid: true, opts: book('No break elements', {
    rawChapters: [{ body: `<h1>One</h1>\n<p id="t1">Target one. ${filler}</p>${paras('One', 14)}<p id="t2">Target two. ${filler}</p>${paras('One', 10)}` }],
    pageList: [{ label: '1', href: 'chapter1.xhtml#t1' }, { label: '2', href: 'chapter1.xhtml#t2' }] }) },

  /** Two breaks in one paragraph, one at the very start of the chapter
      and one at its very end */
  twoOnScreen: { valid: true, opts: book('Two on a screen', {
    rawChapters: [{ body: `${brk('p1', '1')}<h1>One</h1>\n<p>Short ${brk('p2', '2')} paragraph ${brk('p3', '3')} with three breaks.</p>${paras('One', 14)}${brk('p4', '4')}` }],
    pageList: [
      { label: '1', href: 'chapter1.xhtml#p1' }, { label: '2', href: 'chapter1.xhtml#p2' },
      { label: '3', href: 'chapter1.xhtml#p3' }, { label: '4', href: 'chapter1.xhtml#p4' }] }) },
};
