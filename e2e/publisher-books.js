// EPUB 3 books whose publisher styling fights the reader's settings
// (#411): the book's own CSS is dropped, and nothing in it, in a style
// attribute or in an obsolete presentational attribute may reach the page.
// Each is checked by epubcheck (e2e/epubcheck.spec.js); `valid` ones must
// pass, an invalid one (obsolete attributes, by its entry) may give only
// the errors it lists.

const filler = 'lorem ipsum dolor sit amet '.repeat(10);
const chapter = (head, body) => ({ head, body });

export const publisherBooks = {
  /** Sizes, colours, margins, alignment and font in <style>, in style
      attributes and with !important */
  styled: { valid: true, opts: {
    title: 'Publisher styling', author: 'Styling', toc: [
      { label: 'Sizes', href: 'chapter1.xhtml' }, { label: 'Colours', href: 'chapter2.xhtml' },
      { label: 'Margins', href: 'chapter3.xhtml' }, { label: 'Alignment', href: 'chapter4.xhtml' }, { label: 'Hidden', href: 'chapter5.xhtml' }],
    rawChapters: [
      chapter('<style>p.px{font-size:9px !important;} h1{font-size:6pt !important}</style>',
        `<h1>Sizes</h1>\n<p class="px" id="px">Pixel sized by the book's CSS. ${filler}</p>\n` +
        `<p id="pt" style="font-size:8pt">Point sized inline. ${filler}</p>\n<p id="imp" style="font-size:30px !important">Important inline. ${filler}</p>`),
      chapter('<style>body{color:#000 !important;background:#fff !important} p.dark{color:#000 !important; background-color:#ffffff}</style>',
        `<h1>Colours</h1>\n<p id="black" style="color:#000;">Black text. ${filler}</p>\n<p id="slab" class="dark" style="background:#fff">A white slab. ${filler}</p>\n` +
        `<div id="block" style="background-color:#f5f5f5;color:#111"><p>In a light block. ${filler}</p></div>`),
      chapter('<style>p.wide{margin-left:5em !important;width:600px !important}</style>',
        `<h1>Margins</h1>\n<p id="wide" class="wide" style="margin-left:5em;width:600px">Fixed margin and width. ${filler}</p>\n` +
        `<div id="padded" style="padding-left:200px;margin-right:-50px;width:900px"><p>Padded. ${filler}</p></div>`),
      chapter('<style>p.right{text-align:right !important;line-height:4;font-family:Courier,monospace}</style>',
        `<h1>Alignment</h1>\n<p id="right" class="right" style="text-align:right;line-height:3;font-family:'Courier New',monospace">Right aligned, spaced, Courier. ${filler}</p>`),
      chapter('<style>.gone{display:none} @media (min-width:1px){p.wide{display:none}}</style>',
        `<h1>Hidden</h1>\n<p id="shown">Shown text.</p>\n<p id="attr" hidden="">Hidden by attribute. ${filler}</p>\n` +
        `<p id="inline" style="display:none">Hidden inline. ${filler}</p>\n<p id="cls" class="gone">Hidden by class. ${filler}</p>\n<p id="media" class="wide">Media rule. ${filler}</p>`),
    ] } },

  /** Obsolete presentational attributes (not valid HTML 5) */
  legacy: { valid: false, errors: ['RSC-005'], opts: {
    title: 'Legacy styling', author: 'Styling', toc: [{ label: 'Legacy', href: 'chapter1.xhtml' }],
    rawChapters: [chapter('',
      `<h1>Legacy</h1>\n<p><font color="#000000" size="1" id="font">Font tag text. ${filler}</font></p>\n` +
      `<div id="bg" bgcolor="#ffffff" style="color:black">A bgcolor block. ${filler}</div>\n<table id="table" bgcolor="#eeeeee" width="900"><tr><td>Cell. ${filler}</td></tr></table>`)] } },
};
