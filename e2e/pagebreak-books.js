// Small EPUB 3 books whose page breaks (epub:type pagebreak, role
// doc-pagebreak) hold text or sit inside words (#421). Each is checked by
// epubcheck (e2e/epubcheck.spec.js).

const filler = 'lorem ipsum dolor sit amet '.repeat(10);
const pages = [1, 2].map(i => ({ href: `chapter1.xhtml#p${i}0`, label: `${i}0` }));

export const pagebreakBooks = {
  /** Real words inside a page-break span (as the print edition's
      first word of a page) */
  textInside: { valid: true, opts: {
    title: 'Text in a page break', author: 'Breaks', toc: [{ label: 'Chapter', href: 'chapter1.xhtml' }],
    rawChapters: [{ body:
      '<h1>Text inside</h1>\n' +
      '<p><span epub:type="pagebreak" id="p10" title="10">‘But</span> of course!’ said the first. ' + filler + '</p>\n' +
      Array.from({ length: 24 }, (_, k) => `<p>Between ${k}. ${filler}</p>`).join('\n') + '\n' +
      '<p><span role="doc-pagebreak" epub:type="pagebreak" id="p20" title="20" aria-label="Page 20">Wait</span> what? asked the second. ' + filler + '</p>' }],
    pageList: pages } },

  /** The same words with nothing between: a short chapter, read aloud */
  textInsideShort: { valid: true, opts: {
    title: 'Text in a page break, short', author: 'Breaks', toc: [{ label: 'Chapter', href: 'chapter1.xhtml' }],
    rawChapters: [{ body:
      '<h1>Text inside</h1>\n' +
      '<p><span epub:type="pagebreak" id="p10" title="10">\u2018But</span> of course!\u2019 said the first.</p>\n' +
      '<p><span role="doc-pagebreak" epub:type="pagebreak" id="p20" title="20" aria-label="Page 20">Wait</span> what? asked the second.</p>' }] } },

  /** The page number is the span's own text */
  numberText: { valid: true, opts: {
    title: 'Number in a page break', author: 'Breaks', toc: [{ label: 'Chapter', href: 'chapter1.xhtml' }],
    rawChapters: [{ body:
      '<h1>Numbers</h1>\n' +
      '<p>Page ten ends here. ' + filler + '<span epub:type="pagebreak" id="p10" title="10">10</span> And page eleven begins.</p>\n' +
      '<p>Second paragraph. <span epub:type="pagebreak" id="p20">20</span> After the number twenty. ' + filler + '</p>' }],
    pageList: pages } },

  /** A block-level break between paragraphs, one inside a word and one
      inside an inline element */
  structure: { valid: true, opts: {
    title: 'Breaks inside words', author: 'Breaks', toc: [{ label: 'Chapter', href: 'chapter1.xhtml' }],
    rawChapters: [{ body:
      '<h1>Structure</h1>\n' +
      '<p>Before the block break. ' + filler + '</p>\n' +
      '<div epub:type="pagebreak" id="p10" title="10"></div>\n' +
      '<p>After the block break. ' + filler + '</p>\n' +
      '<p>An un<span epub:type="pagebreak" id="p20" title="20"></span>believable word. ' + filler + '</p>\n' +
      '<p>An <em>emph<span epub:type="pagebreak" id="p30" title="30"></span>asis</em> inside. ' + filler + '</p>\n' +
      '<p>The needle after every break. ' + filler + '</p>' }],
    pageList: [{ href: 'chapter1.xhtml#p10', label: '10' }, { href: 'chapter1.xhtml#p20', label: '20' }, { href: 'chapter1.xhtml#p30', label: '30' }] } },
};
