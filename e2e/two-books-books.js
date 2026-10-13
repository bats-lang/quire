// Two small EPUB 3 books that differ in every feature the reader keeps per
// book (#435), so a test that opens one after the other can tell whose
// each thing shown is. Each is checked by epubcheck (e2e/epubcheck.spec.js).
//
// Alpha: five chapters, a nested contents, a page list with breaks in the
// text, a note, a ruby, a Media Overlays narration, left to right,
// Japanese. Beta: two chapters, a flat contents, no page list, no ruby,
// no narration, right to left, Hebrew. Gamma is a vertical Japanese book
// (right to left, Japanese): the one that must not leave a book after it
// set vertically; Delta is fixed-layout, the one that must not leave its
// page box. The words only one book has begin with its name.

import { readFileSync } from 'node:fs';
import { solidPng } from './create-epub.js';

/** A minute of silence as an mp3 (audio/mpeg is a core media type, which epubcheck requires of a narration's audio) */
const narrationAudio = readFileSync(new URL('./two-books-narration.mp3', import.meta.url));

const filler = 'lorem ipsum dolor sit amet '.repeat(12);
const paras = (tag, chapter, count) =>
  Array.from({ length: count }, (_, k) => `<p>${tag} ${chapter}.${k} ${filler}</p>`).join('\n');
const hebrew = 'שלום עולם זהו ספר קצר '.repeat(14);
const hebrewParas = (chapter, count) =>
  Array.from({ length: count }, (_, k) => `<p>Beta ${chapter}.${k} ${hebrew}</p>`).join('\n');
const pagebreak = (id, label) => `<span epub:type="pagebreak" id="${id}" title="${label}"></span>`;

/** Chapter 1's narration: two phrases of 30 s each (long enough for a test to switch books while it plays), the paragraphs a1 and a2 */
const overlay = `<?xml version="1.0" encoding="UTF-8"?>
<smil xmlns="http://www.w3.org/ns/SMIL" xmlns:epub="http://www.idpf.org/2007/ops" version="3.0">
<body>
<seq id="body1" epub:textref="chapter1.xhtml" epub:type="bodymatter chapter">
<par id="par1"><text src="chapter1.xhtml#a1"/><audio src="audio/narration.mp3" clipBegin="0:00:00.000" clipEnd="0:00:30.000"/></par>
<par id="par2"><text src="chapter1.xhtml#a2"/><audio src="audio/narration.mp3" clipBegin="0:00:30.000" clipEnd="0:01:00.000"/></par>
</seq>
</body>
</smil>`;

/** Chapter 3's: the chapter a test jumps to, so the narration goes on there (the paragraphs c1 and c2) */
const overlayThree = overlay
  .replace(/chapter1\.xhtml/g, 'chapter3.xhtml').replace('id="body1"', 'id="body3"')
  .replace('id="par1"', 'id="par3"').replace('id="par2"', 'id="par4"')
  .replace('#a1', '#c1').replace('#a2', '#c2');

export const twoBooks = {
  alpha: { valid: true, opts: {
    title: 'Alpha Ledger', author: 'Two Books', language: 'ja',
    toc: [
      { label: 'Alpha Chapter 1', href: 'chapter1.xhtml', children: [
        { label: 'Alpha Section 1.1', href: 'chapter1.xhtml#pb2' }] },
      { label: 'Alpha Chapter 2', href: 'chapter2.xhtml' },
      { label: 'Alpha Chapter 3', href: 'chapter3.xhtml', children: [
        { label: 'Alpha Section 3.1', href: 'chapter3.xhtml#s31' }] },
      { label: 'Alpha Chapter 4', href: 'chapter4.xhtml' },
      { label: 'Alpha Chapter 5', href: 'chapter5.xhtml' },
    ],
    pageList: [{ label: '101', href: 'chapter1.xhtml#pb1' }, { label: '102', href: 'chapter1.xhtml#pb2' }],
    metadata: '    <meta property="media:duration" refines="#mo1">0:01:00.000</meta>\n'
      + '    <meta property="media:duration" refines="#mo3">0:01:00.000</meta>\n'
      + '    <meta property="media:duration">0:02:00.000</meta>\n',
    rawChapters: [
      { overlay, body: `<h1>Alpha One</h1>\n${pagebreak('pb1', '101')}`
        + '<p id="a1">Alpha begins at <ruby>東京<rp>(</rp><rt>とうきょう</rt><rp>)</rp></ruby> with a note'
        + '<a epub:type="noteref" href="#fn1">1</a>. The Zebrafish is Alpha\'s own word.</p>\n'
        + '<p id="a2">Alpha goes on with its second phrase.</p>\n'
        + paras('Alpha', 1, 10) + `\n${pagebreak('pb2', '102')}\n` + paras('Alpha', 1, 10)
        + '\n<aside epub:type="footnote" id="fn1"><p>Alpha\'s note.</p></aside>' },
      { body: `<h1>Alpha Two</h1>\n${paras('Alpha', 2, 14)}` },
      { overlay: overlayThree, body: `<h1>Alpha Three</h1>\n<p id="c1">Alpha three begins here.</p>\n<p id="c2">Alpha three goes on.</p>\n${paras('Alpha', 3, 6)}<h2 id="s31">Alpha Section 3.1</h2>${paras('Alpha', 3, 8)}` },
      { body: `<h1>Alpha Four</h1>\n${paras('Alpha', 4, 14)}` },
      { body: `<h1>Alpha Five</h1>\n${paras('Alpha', 5, 14)}` },
    ],
    extraFiles: [{ name: 'audio/narration.mp3', data: narrationAudio, mediaType: 'audio/mpeg', store: true }],
  } },

  beta: { valid: true, opts: {
    title: 'Beta Ledger', author: 'Two Books', language: 'he', rtl: true,
    toc: [{ label: 'Beta Chapter 1', href: 'chapter1.xhtml' }, { label: 'Beta Chapter 2', href: 'chapter2.xhtml' }],
    rawChapters: [
      { body: `<h1>Beta One</h1>\n${hebrewParas(1, 16)}` },
      { body: `<h1>Beta Two</h1>\n${hebrewParas(2, 16)}` },
    ],
  } },

  /** Delta: three fixed pages (a page an image), the book whose page box must not be left behind */
  delta: { valid: true, opts: {
    title: 'Delta Ledger', author: 'Two Books', chapters: 3,
    metadata: '<meta property="rendition:layout">pre-paginated</meta>\n<meta property="rendition:spread">none</meta>\n',
    rawChapters: [1, 2, 3].map(k => ({
      head: '<meta name="viewport" content="width=600, height=800"/>',
      body: `<div><img src="images/page${k}.png" alt="Delta page ${k}"/></div>`,
    })),
    extraFiles: [1, 2, 3].map(k => ({ name: `images/page${k}.png`, data: solidPng(600, 800), mediaType: 'image/png', store: true })),
  } },

  gamma: { valid: true, opts: {
    title: 'Gamma Ledger', author: 'Two Books', language: 'ja', rtl: true,
    toc: [{ label: 'Gamma Chapter 1', href: 'chapter1.xhtml' }, { label: 'Gamma Chapter 2', href: 'chapter2.xhtml' }],
    rawChapters: [1, 2].map(i => ({
      body: `<h1>Gamma ${i}</h1>\n` + Array.from({ length: 24 }, (_, k) => `<p>ガンマ ${i}.${k} ${'吾輩は猫である。名前はまだ無い。'.repeat(6)}</p>`).join('\n'),
    })),
  } },
};
