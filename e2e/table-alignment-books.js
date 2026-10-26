// A book whose style sheet aligns the cells of a plain table (#868), for the
// case that is not mathematics: a table of a ledger, its columns aligned by
// the book's sheet and by a style attribute. The mathematics is the real
// book, e2e/calculus101-mathml-test.epub (keyword: publisher alignment).

/** The sheet: the alignment of cells, and a rule for a paragraph, which stays unapplied (#411) */
export const alignmentSheet = [
  'table.ledger td.amount{text-align:right}',
  'table.ledger td.name{text-align:center}',
  'p.right{text-align:right}',
].join('\n');

const filler = 'lorem ipsum dolor sit amet '.repeat(6);

export const tableAlignmentBook = { valid: true, opts: {
  title: 'Ledger', author: 'Alignment Tests',
  toc: [{ label: 'Ledger', href: 'chapter1.xhtml' }],
  extraFiles: [{ name: 'ledger.css', data: alignmentSheet, mediaType: 'text/css' }],
  rawChapters: [
    { head: '<link rel="stylesheet" type="text/css" href="ledger.css"/>',
      body: '<h1>Ledger</h1>\n<table class="ledger"><tbody>' +
        '<tr><td class="amount">1</td><td class="name">Apples</td><td style="text-align:right">ok</td></tr>' +
        '<tr><td class="amount">1000000</td><td class="name">Pears and plums together</td><td style="text-align:right">in stock now</td></tr>' +
        `</tbody></table>\n<p class="right" id="right">sheet-paragraph ${filler}</p>` },
  ] } };
