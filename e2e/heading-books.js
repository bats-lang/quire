// An EPUB 3 book of headings and relative sizes (#422), checked by
// epubcheck (e2e/epubcheck.spec.js).

const filler = 'lorem ipsum dolor sit amet '.repeat(8);

export const headingBooks = {
  /** h1 to h4, text, small, sub, sup, a caption and a footnote aside */
  hierarchy: { valid: true, opts: {
    title: 'Headings', author: 'Sizes', toc: [{ label: 'Headings', href: 'chapter1.xhtml' }],
    rawChapters: [{ body:
      '<h1>Heading one</h1>\n<h2>Heading two</h2>\n<h3>Heading three</h3>\n<h4>Heading four</h4>\n' +
      `<p>Body text. ${filler} <small>Small print.</small> Normal<sub>sub</sub> and<sup>sup</sup>.</p>\n` +
      `<figure><p>The figure</p><figcaption>A caption of the figure</figcaption></figure>\n` +
      `<aside epub:type="footnote" id="n1"><p>A footnote's text.</p></aside>\n` +
      `<p>${filler}</p>` }] } },

  /** The same headings with the book's own sizes in style attributes and in a rule */
  inlineSizes: { valid: true, opts: {
    title: 'Headings with sizes', author: 'Sizes', toc: [{ label: 'Headings', href: 'chapter1.xhtml' }],
    rawChapters: [{ head: '<style>h1{font-size:9px}h2{font-size:9px}</style>', body:
      '<h1 style="font-size:9px">Heading one</h1>\n<h2 style="font-size:9px">Heading two</h2>\n<h3 style="font-size:9px">Heading three</h3>\n' +
      `<p style="font-size:30px">Body text. ${filler}</p>` }] } },

  /** A heading that is one long word, at the largest size on a narrow window */
  longHeading: { valid: true, opts: {
    title: 'Long heading', author: 'Sizes', toc: [{ label: 'Headings', href: 'chapter1.xhtml' }],
    rawChapters: [{ body:
      '<h1>Pneumonoultramicroscopicsilicovolcanoconiosis</h1>\n<h2>An ordinary second heading that wraps over several lines of a narrow page at the largest size</h2>\n' +
      `<p>${filler}</p>` }] } },
};
