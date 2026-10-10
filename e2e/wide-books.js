// EPUB 3 books of wide and structured content (#413): tables wider and
// taller than the page, preformatted blocks and verse. Each is checked by
// epubcheck (e2e/epubcheck.spec.js).

const cell = (c, text = 'wide cell text') => `<td>Column ${c} ${text}</td>`;
const headRow = n => `<tr>${Array.from({ length: n }, (_, c) => `<th scope="col">Head ${c}</th>`).join('')}</tr>`;
const row = (r, n) => `<tr><th scope="row">Row ${r}</th>${Array.from({ length: n }, (_, c) => cell(c)).join('')}</tr>`;

export const wideBooks = {
  /** A table of 14 columns, wider than any window, and one of 90 rows,
      taller than any page */
  tables: { valid: true, opts: {
    title: 'Tables', author: 'Wide',
    toc: [{ label: 'Wide', href: 'chapter1.xhtml' }, { label: 'Tall', href: 'chapter2.xhtml' }, { label: 'Spans', href: 'chapter3.xhtml' }],
    rawChapters: [
      { body: `<h1>Wide</h1>\n<p>Before the table.</p>\n<table id="wide"><thead>${headRow(14)}</thead><tbody>${Array.from({ length: 6 }, (_, r) => row(r, 13)).join('')}</tbody></table>\n<p>After the table.</p>` },
      { body: `<h1>Tall</h1>\n<p>Before the table.</p>\n<table id="tall"><thead>${headRow(3)}</thead><tbody>${Array.from({ length: 90 }, (_, r) => row(r, 2)).join('')}</tbody></table>\n<p>After the table.</p>` },
      { body: '<h1>Spans</h1>\n<table id="spans"><caption>Spans</caption><thead><tr><th rowspan="2" scope="col">Name</th><th colspan="2" scope="colgroup">Scores</th></tr>' +
        '<tr><th scope="col">First</th><th scope="col">Second</th></tr></thead><tbody><tr><th scope="row">Ann</th><td>1</td><td>2</td></tr><tr><th scope="row">Bob</th><td>3</td><td>4</td></tr></tbody></table>' },
    ] } },

  /** A preformatted block with a very long line, preserved spaces and
      blank lines, and one taller than a page */
  code: { valid: true, opts: {
    title: 'Code', author: 'Wide', toc: [{ label: 'Code', href: 'chapter1.xhtml' }],
    rawChapters: [{ body: '<h1>Code</h1>\n<p>Before the code.</p>\n<pre id="code"><code>' +
      'const veryLongLine = ' + '"abcdefghij".repeat(30) + '.repeat(8) + '"x";\n    four spaces\n\n        eight spaces after a blank line\n\tTabbed\n' +
      Array.from({ length: 90 }, (_, k) => `line ${k}`).join('\n') + '</code></pre>\n<p>After the code.</p>' }] } },

  /** Verse with line breaks and no-break-space indents, one long line, and stanzas */
  verse: { valid: true, opts: {
    title: 'Verse', author: 'Wide', toc: [{ label: 'Verse', href: 'chapter1.xhtml' }],
    rawChapters: [{ body: '<h1>Verse</h1>\n' + Array.from({ length: 12 }, (_, k) =>
      `<div class="stanza" id="stanza${k}"><p>Roses are red ${k},<br/>&#160;&#160;&#160;&#160;violets are blue,<br/>` +
      '&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;sugar is sweet and so are you and you and you and you and you and you and you and you and you and you.</p></div>').join('\n') }] } },
};
