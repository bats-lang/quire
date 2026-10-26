// A book whose style sheet aligns the cells of tables (#868): the columns of
// an aligned equation, the columns of a cases equation, and the cells of a
// plain table, each by a rule of the book's own sheet or a style attribute.
// Quire keeps the alignment of table parts only (keyword: publisher
// alignment); every other rule of the sheet stays unapplied (#411).

const MATHML = 'xmlns="http://www.w3.org/1998/Math/MathML"';

/** The sheet, as a Sphinx book's math sheet writes it: columns by their place in the row */
export const alignmentSheet = [
  'mtable.aligned mtd:nth-child(odd){text-align:right}',
  'mtable.aligned mtd:nth-child(even){text-align:left}',
  'mtable.cases mtd{text-align:left}',
  'table.ledger td.amount{text-align:right}',
  'table.ledger td.name{text-align:center}',
  'p.right{text-align:right}',
].join('\n');

const sheetLink = '<link rel="stylesheet" type="text/css" href="_static/sphinx-typst-math.css"/>';

const letters = (letter, count) => `<mi>${letter}</mi>`.repeat(count);

/** Two rows whose cells differ in width, so a cell's alignment shows in where its content sits */
const aligned = `<math ${MATHML} display="block"><mtable class="aligned">` +
  `<mtr><mtd>${letters('x', 1)}</mtd><mtd><mo>=</mo><mn>1</mn></mtd></mtr>` +
  `<mtr><mtd>${letters('y', 6)}</mtd><mtd><mo>=</mo><mn>222222</mn></mtd></mtr>` +
  '</mtable></math>';

const cases = `<math ${MATHML} display="block"><mrow><mo>{</mo><mtable class="cases">` +
  '<mtr><mtd><mn>1</mn></mtd><mtd><mtext>if x</mtext></mtd></mtr>' +
  '<mtr><mtd><mn>123456</mn></mtd><mtd><mtext>otherwise stated</mtext></mtd></mtr>' +
  '</mtable></mrow></math>';

const filler = 'lorem ipsum dolor sit amet '.repeat(6);

export const tableAlignmentBook = { valid: true, opts: {
  title: 'Table alignment', author: 'Alignment Tests',
  toc: [{ label: 'Equations', href: 'chapter1.xhtml' }, { label: 'Ledger', href: 'chapter2.xhtml' }],
  extraFiles: [{ name: '_static/sphinx-typst-math.css', data: alignmentSheet, mediaType: 'text/css' }],
  rawChapters: [
    { head: sheetLink, properties: 'mathml',
      body: `<h1>Equations</h1>\n<p>aligned-label ${filler}</p>\n${aligned}\n<p>cases-label ${filler}</p>\n${cases}\n<p>equations-after ${filler}</p>` },
    { head: sheetLink,
      body: '<h1>Ledger</h1>\n<table class="ledger"><tbody>' +
        '<tr><td class="amount">1</td><td class="name">Apples</td><td style="text-align:right">left over</td></tr>' +
        '<tr><td class="amount">1000000</td><td class="name">Pears and plums together</td><td style="text-align:right">in stock now</td></tr>' +
        `</tbody></table>\n<p class="right" id="right">sheet-paragraph ${filler}</p>` },
  ] } };
