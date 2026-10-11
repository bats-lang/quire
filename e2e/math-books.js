// EPUB 3 books about mathematics (#408), each one concern, checked by
// epubcheck (e2e/epubcheck.spec.js) and read by the math specs
// (e2e/math-native.spec.js and the others named in tests/groups.json). A
// book is one chapter of one concern: how an equation sits in a line, how
// it stands in a paragraph of its own, how a wide one is held, what a
// fallback of it shows, an equation as a picture, and how one falls on a
// page and in a book read from the right.

import { blackOnTransparentPng, solidPng } from './create-epub.js';

const MATHML = 'xmlns="http://www.w3.org/1998/Math/MathML"';

/** Plain words that fill lines: n sentences, each numbered from tag so a spec can find it */
const words = (tag, n = 3) => Array.from({ length: n }, (_, k) =>
  `Sentence ${tag}${k} of the plain text that surrounds the mathematics in this chapter.`).join(' ');

/** n paragraphs of plain words */
const filler = (tag, n) => Array.from({ length: n }, (_, k) => `<p>${words(`${tag}${k}.`, 4)}</p>`).join('\n');

const one = (title, body, extra = {}, chapter = {}) => ({
  valid: true,
  opts: { title, author: 'Math Tests', chapters: 1, toc: [{ label: title, href: 'chapter1.xhtml' }], rawChapters: [{ body, ...chapter }], ...extra },
});

// ---- the equations ----

/** a over b, plus one: a fraction in a line */
const tallFraction = `<math ${MATHML}><mstyle displaystyle="true"><mfrac><mrow><mi>a</mi><mo>+</mo><mn>1</mn></mrow><mrow><mi>b</mi><mo>−</mo><mn>1</mn></mrow></mfrac></mstyle></math>`;
/** the sum of k squared from k = 1 to n, with its limits over and under */
const tallSum = `<math ${MATHML}><mstyle displaystyle="true"><munderover><mo>∑</mo><mrow><mi>k</mi><mo>=</mo><mn>1</mn></mrow><mi>n</mi></munderover><msup><mi>k</mi><mn>2</mn></msup></mstyle></math>`;
/** the quadratic formula, a root over a fraction */
const quadratic = (attrs = '') => `<math ${MATHML}${attrs}><mi>x</mi><mo>=</mo><mfrac><mrow><mo>−</mo><mi>b</mi><mo>±</mo><msqrt><mrow><msup><mi>b</mi><mn>2</mn></msup><mo>−</mo><mn>4</mn><mi>a</mi><mi>c</mi></mrow></msqrt></mrow><mrow><mn>2</mn><mi>a</mi></mrow></mfrac></math>`;
/** a sum of many terms, far wider than any column */
const wideSum = (attrs = '') => `<math ${MATHML}${attrs}><mrow>${Array.from({ length: 48 }, (_, k) =>
  `<msub><mi>a</mi><mn>${k + 1}</mn></msub>`).join('<mo>+</mo>')}<mo>=</mo><mi>S</mi></mrow></math>`;
/** a column of rows, as tall as a matrix */
const matrix = `<math ${MATHML} display="block"><mrow><mo>[</mo><mtable>${Array.from({ length: 4 }, (_, r) =>
  `<mtr>${Array.from({ length: 3 }, (_, c) => `<mtd><mn>${r * 3 + c + 1}</mn></mtd>`).join('')}</mtr>`).join('')}</mtable><mo>]</mo></mrow></math>`;

// ---- pictures ----

/** a stroke and a bar in black, with no ground: a typeset equation's picture */
const svg = (width, height) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 60 24"><path d="M2 21H28M44 2V22" stroke="#000000" stroke-width="3" fill="none"/></svg>`;

const png = (width, height) => blackOnTransparentPng(width, height);

/** the same equation as MathML and as its picture (altimg) */
const pictured = `<math ${MATHML} altimg="images/equation.png" altimg-width="60px" altimg-height="24px" alttext="x equals one half"><mi>x</mi><mo>=</mo><mfrac><mn>1</mn><mn>2</mn></mfrac></math>`;

export const mathBooks = {
  // ---- native MathML ----

  /** Inline math whose letter and the letters of the text around it stand on one baseline */
  'inline-baseline': one('Inline Baseline',
    '<h1>Inline Baseline</h1>\n' +
    `<p>baseline-row H <math ${MATHML} id="baseline-math"><mi mathvariant="normal">H</mi></math> H and the rest of this paragraph is plain text to fill a line or two with words.</p>\n` +
    `<p>solution The solution of <math ${MATHML}><mi>x</mi><mo>+</mo><mn>1</mn><mo>=</mo><mn>3</mn></math> is two, and <math ${MATHML}><mi>y</mi></math> is another letter.</p>\n` +
    filler('inline.', 8), {}, { properties: 'mathml' }),

  /** Inline fractions and sums with limits, one in each paragraph and several in a line */
  'inline-tall': one('Inline Tall',
    '<h1>Inline Tall</h1>\n' +
    `<p>tall-fraction ${words('first-', 2)} The ratio ${tallFraction} is a fraction in a line, and ${tallFraction} is another. ${words('second-', 2)}</p>\n` +
    `<p>tall-sum ${words('third-', 2)} The total ${tallSum} has its limits over and under the sign, and ${tallSum} again. ${words('fourth-', 3)}</p>\n` +
    `<p>tall-run Both ${tallFraction} and ${tallSum} and ${tallFraction} and ${tallSum} and ${tallFraction} in one run of words that wraps across several lines of the page.</p>\n` +
    filler('tall.', 8), { }, { properties: 'mathml' }),

  /** A display equation between two paragraphs */
  'display': one('Display Math',
    '<h1>Display Math</h1>\n' +
    '<p>display-before The paragraph before the equation, with a few plain words in it.</p>\n' +
    quadratic(' display="block" id="display-quadratic"') + '\n' +
    '<p>display-after The paragraph after the equation, with a few plain words in it.</p>\n' +
    `<p>display-inline An inline <math ${MATHML} display="inline" id="display-explicit-inline"><mi>y</mi></math> keeps to its line.</p>\n` +
    filler('display.', 6), {}, { properties: 'mathml' }),

  /** A display equation far wider than any column, among plain paragraphs */
  'display-wide': one('Display Wide',
    '<h1>Display Wide</h1>\n' + filler('wide-a.', 3) +
    wideSum(' display="block" id="wide-equation"') + '\n' + filler('wide-b.', 24), {}, { properties: 'mathml' }),

  /** The same paragraphs with a short equation where the wide one was: its pages are the wide one's */
  'display-wide-control': one('Equation Control',
    '<h1>Display Wide</h1>\n' + filler('wide-a.', 3) +
    quadratic(' display="block" id="wide-equation"') + '\n' + filler('wide-b.', 24), {}, { properties: 'mathml' }),

  // ---- fallbacks ----

  /** math with alttext, inline and as a display */
  'alttext': one('Alternative Text',
    '<h1>Alternative Text</h1>\n' +
    `<p>alttext-inline Before <math ${MATHML} alttext="the unseen words for the inline equation"><mi>x</mi><mo>=</mo><mfrac><mn>1</mn><mn>2</mn></mfrac></math> after.</p>\n` +
    `<math ${MATHML} display="block" alttext="the unseen words for the display equation"><mi>y</mi><mo>=</mo><msqrt><mn>2</mn></msqrt></math>\n` +
    '<p>alttext-after The paragraph after.</p>', {}, { properties: 'mathml' }),

  /** math with altimg, the picture in the book */
  'altimg': one('Alternative Image',
    '<h1>Alternative Image</h1>\n' +
    `<p>altimg-inline Before ${pictured} after.</p>\n` +
    `<p>altimg-after The paragraph after.</p>`,
    { extraImages: [{ name: 'images/equation.png', data: png(60, 24) }] }, { properties: 'mathml' }),

  /** Elements of MathML 3 that MathML Core leaves out, a fraction with one child and a mixed one, among good equations */
  'degraded': one('Degraded Math',
    '<h1>Degraded Math</h1>\n' +
    '<p>degraded-before The paragraph before the unsupported equations.</p>\n' +
    `<p>degraded-enclose Boxed: <math ${MATHML}><menclose notation="box"><mi>x</mi><mo>+</mo><mn>1</mn></menclose></math> ends here.</p>\n` +
    `<p>degraded-fenced Fenced: <math ${MATHML}><mfenced open="[" close="]"><mi>a</mi><mi>b</mi></mfenced></math> ends here.</p>\n` +
    `<p>degraded-stack Stacked: <math ${MATHML}><mstack><mn>12</mn><msrow><mo>+</mo><mn>34</mn></msrow></mstack></math> ends here.</p>\n` +
    `<p>degraded-glyph Glyph: <math ${MATHML}><mi><mglyph src="images/equation.png" alt="a glyph"/></mi></math> ends here.</p>\n` +
    `<p>degraded-good Good: <math ${MATHML}><mn>7</mn><mo>+</mo><mn>8</mn></math> ends here.</p>\n` +
    '<p>degraded-after The paragraph after the unsupported equations.</p>',
    { extraImages: [{ name: 'images/equation.png', data: png(24, 24) }] }, { properties: 'mathml' }),

  /** Valid MathML that makes nothing to draw or draws oddly: empty parts, a table with an empty row */
  'degenerate': one('Degenerate Math',
    '<h1>Degenerate Math</h1>\n' +
    '<p>degenerate-before The paragraph before the degenerate equations.</p>\n' +
    `<p>degenerate-empty Empty: <math ${MATHML}><mfrac><mrow/><mrow/></mfrac></math> ends here.</p>\n` +
    `<p>degenerate-table Table: <math ${MATHML}><mtable><mtr/></mtable></math> ends here.</p>\n` +
    `<p>degenerate-size Fraktur: <math ${MATHML}><mi mathsize="small" mathvariant="fraktur">q</mi></math> ends here.</p>\n` +
    `<p>degenerate-good Good: <math ${MATHML}><mn>7</mn><mo>+</mo><mn>8</mn></math> ends here.</p>\n` +
    '<p>degenerate-after The paragraph after the degenerate equations.</p>', {}, { properties: 'mathml' }),

  /** A math element with a broken tree (a fraction of one child, a root of three), valid XML, not valid MathML */
  'malformed': {
    valid: false, errors: ['RSC-005'],
    ...one('Malformed Math',
      '<h1>Malformed Math</h1>\n' +
      '<p>malformed-before The paragraph before the malformed equations.</p>\n' +
      `<p>malformed-fraction A fraction: <math ${MATHML}><mfrac><mn>1</mn></mfrac></math> ends here.</p>\n` +
      `<p>malformed-root A root: <math ${MATHML}><mroot><mn>1</mn><mn>2</mn><mn>3</mn></mroot></math> ends here.</p>\n` +
      `<p>malformed-unknown An unknown: <math ${MATHML}><mi>q</mi><mfoo><mn>5</mn></mfoo></math> ends here.</p>\n` +
      `<p>malformed-good Good: <math ${MATHML}><mn>7</mn><mo>+</mo><mn>8</mn></math> ends here.</p>\n` +
      '<p>malformed-after The paragraph after the malformed equations.</p>', {}, { properties: 'mathml' }),
  },

  // ---- equations as pictures ----

  /** PNG equations, in a line and in a paragraph of their own */
  'png': one('Picture PNG',
    '<h1>Picture PNG</h1>\n' +
    '<p>png-inline-row The ratio <img id="png-inline" src="images/inline.png" alt="a small equation" width="60" height="24"/> sits in this line of plain words.</p>\n' +
    '<p>png-block-row <img id="png-block" src="images/block.png" alt="a large equation" width="150" height="38"/></p>\n' +
    filler('png.', 4),
    { extraImages: [{ name: 'images/inline.png', data: png(60, 24) }, { name: 'images/block.png', data: png(150, 38) }] }),

  /** SVG equations: drawn in the page, and a file */
  'svg': one('Picture SVG',
    '<h1>Picture SVG</h1>\n' +
    `<p>svg-inline-row The ratio ${svg(60, 24).replace('<svg ', '<svg id="svg-inline" ')} sits in this line of plain words.</p>\n` +
    `<p>svg-block-row ${svg(150, 60).replace('<svg ', '<svg id="svg-block" ')}</p>\n` +
    '<p>svg-file-inline-row The ratio <img id="svg-file-inline" src="images/inline.svg" alt="a small equation" width="60" height="24"/> sits in this line of plain words.</p>\n' +
    '<p>svg-file-block-row <img id="svg-file-block" src="images/block.svg" alt="a large equation" width="150" height="60"/></p>\n' +
    filler('svg.', 4),
    { extraImages: [{ name: 'images/inline.svg', data: Buffer.from(svg(60, 24)) }, { name: 'images/block.svg', data: Buffer.from(svg(150, 60)) }] },
    { properties: 'svg' }),

  /** A photograph-like opaque picture next to a black-on-transparent one */
  'opaque-and-transparent': one('Picture Ground',
    '<h1>Picture Ground</h1>\n' +
    '<p>transparent-row <img id="transparent-picture" src="images/ink.png" alt="black ink on no ground" width="120" height="48"/></p>\n' +
    '<p>opaque-row <img id="opaque-picture" src="images/photo.png" alt="an opaque picture" width="120" height="48"/></p>\n' +
    '<p>transparent-svg-row <img id="transparent-svg" src="images/ink.svg" alt="black strokes on no ground" width="120" height="48"/></p>\n' +
    filler('ground.', 3),
    { extraImages: [{ name: 'images/ink.png', data: png(120, 48) }, { name: 'images/photo.png', data: solidPng(120, 48, [200, 60, 60]) }, { name: 'images/ink.svg', data: Buffer.from(svg(120, 48)) }] }),

  // ---- layout ----

  /** Display equations of two heights falling all down the pages, between paragraphs of different lengths */
  'page-boundary': one('Page Boundary',
    '<h1>Page Boundary</h1>\n' + Array.from({ length: 24 }, (_, k) =>
      `<p>${words(`boundary${k}-`, 1 + (k * 7) % 5)}</p>\n` + (k % 2 === 0 ? quadratic(` display="block" id="boundary-equation${k}"`) : matrix.replace('display="block"', `display="block" id="boundary-equation${k}"`))).join('\n'),
    {}, { properties: 'mathml' }),

  /** A Hebrew book: an equation in a line and as a display, and the same with dir="rtl" */
  'hebrew': one('Hebrew Math',
    '<h1>פרק ראשון</h1>\n' +
    `<p>hebrew-inline המשוואה <math ${MATHML} id="hebrew-math"><mi>x</mi><mo>=</mo><mn>1</mn><mo>+</mo><mn>2</mn></math> היא פשוטה מאוד.</p>\n` +
    `<math ${MATHML} display="block" id="hebrew-display"><mi>x</mi><mo>=</mo><mn>1</mn><mo>+</mo><mn>2</mn></math>\n` +
    `<math ${MATHML} display="block" dir="rtl" id="hebrew-rtl"><mi>x</mi><mo>=</mo><mn>1</mn><mo>+</mo><mn>2</mn></math>\n` +
    '<p>hebrew-after פסקה אחרי המשוואה, בעברית.</p>',
    { language: 'he', rtl: true }, { properties: 'mathml', lang: 'he' }),
};
