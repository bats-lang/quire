// Small EPUB 3 books whose files are in folders (#432): the package
// document, chapters, images, styles and navigation in different
// directories, hrefs with "./", "../", percent-encoding and non-ASCII
// names, links between chapters of different folders, and ids that two
// chapters share. Each is checked by epubcheck (e2e/epubcheck.spec.js):
// `valid` ones must pass; an invalid one is invalid on purpose, and
// `errors` names the only messages it may give.

import { TINY_PNG } from './create-epub.js';

const filler = 'lorem ipsum dolor sit amet '.repeat(12);
/** n paragraphs, each starting with a findable tag */
const paras = (tag, n) => Array.from({ length: n }, (_, k) => `<p>${tag} ${k} ${filler}</p>`).join('\n');
/** A page break marker: an empty span titled with the page's label */
const brk = (id, label) => `<span epub:type="pagebreak" id="${id}" title="${label}"></span>`;

export const folderBooks = {
  /** The IDPF samples' layout: EPUB/package.opf, text/, images/, css/, and the nav beside the package */
  idpf: { valid: true, opts: {
    title: 'IDPF layout', author: 'Folders',
    opfDir: 'EPUB', opfName: 'package.opf',
    rawChapters: [
      { file: 'text/ch1.xhtml', head: '<link rel="stylesheet" type="text/css" href="../css/style.css"/>',
        body: `<h1>Alpha</h1>\n<p><img src="../images/a.png" alt="picture"/></p>\n${brk('pg1', '1')}${paras('Alpha', 20)}\n<p id="x">Target x of alpha</p>\n${paras('Alpha more', 8)}` },
      { file: 'text/ch2.xhtml', head: '<link rel="stylesheet" type="text/css" href="../css/style.css"/>',
        body: `<h1>Beta</h1>\n${brk('pg2', '2')}${paras('Beta', 20)}\n<p id="y">Target y of beta</p>\n${paras('Beta more', 8)}` },
    ],
    extraImages: [{ name: 'images/a.png', data: TINY_PNG }],
    extraFiles: [{ name: 'css/style.css', data: 'p { margin: 0 0 1em 0; }', mediaType: 'text/css' }],
    toc: [{ label: 'Alpha', href: 'text/ch1.xhtml' }, { label: 'Alpha x', href: 'text/ch1.xhtml#x' },
      { label: 'Beta', href: 'text/ch2.xhtml' }, { label: 'Beta y', href: 'text/ch2.xhtml#y' }],
    pageList: [{ label: '1', href: 'text/ch1.xhtml#pg1' }, { label: '2', href: 'text/ch2.xhtml#pg2' }],
  } },

  /** The package two levels down: OPS/book/content.opf, chapters in xhtml/, images two levels up */
  deep: { valid: true, opts: {
    title: 'Deep package', author: 'Folders',
    opfDir: 'OPS/book',
    rawChapters: [
      { file: 'xhtml/ch1.xhtml',
        body: `<h1>Gamma</h1>\n<p><img src="../../images/a.png" alt="picture"/></p>\n${brk('pg1', '1')}${paras('Gamma', 20)}\n<p id="x">Target x of gamma</p>\n${paras('Gamma more', 8)}` },
      { file: 'xhtml/ch2.xhtml',
        body: `<h1>Delta</h1>\n${brk('pg2', '2')}${paras('Delta', 20)}\n<p id="y">Target y of delta</p>\n${paras('Delta more', 8)}` },
    ],
    extraImages: [{ name: '../images/a.png', data: TINY_PNG }],
    toc: [{ label: 'Gamma', href: 'xhtml/ch1.xhtml' }, { label: 'Gamma x', href: 'xhtml/ch1.xhtml#x' },
      { label: 'Delta', href: 'xhtml/ch2.xhtml' }, { label: 'Delta y', href: 'xhtml/ch2.xhtml#y' }],
    pageList: [{ label: '1', href: 'xhtml/ch1.xhtml#pg1' }, { label: '2', href: 'xhtml/ch2.xhtml#pg2' }],
  } },

  /** Chapter hrefs written as URLs: "./", an encoded space, a "+", an encoded and a raw non-ASCII name; the archive's entries are the decoded names */
  names: { valid: true, opts: {
    title: 'Names as URLs', author: 'Folders',
    rawChapters: [
      { file: 'plain.xhtml', body: `<h1>Plain</h1>\n${paras('Plain', 6)}` },
      { file: './dot.xhtml', body: `<h1>Dot</h1>\n${paras('Dot', 6)}\n<p id="t">Target t of dot</p>` },
      { file: 'my%20chapter.xhtml', body: `<h1>Space</h1>\n${paras('Space', 6)}\n<p id="t">Target t of space</p>` },
      { file: 'a+b.xhtml', body: `<h1>Plus</h1>\n${paras('Plus', 6)}` },
      { file: 'Kapitel%20%C3%BCber.xhtml', body: `<h1>Umlaut</h1>\n${paras('Umlaut', 6)}\n<p id="t">Target t of umlaut</p>` },
      { file: 'Straße.xhtml', body: `<h1>Raw</h1>\n${paras('Raw', 6)}` },
    ],
    toc: [{ label: 'Plain', href: 'plain.xhtml' }, { label: 'Dot', href: './dot.xhtml' }, { label: 'Dot t', href: './dot.xhtml#t' },
      { label: 'Space', href: 'my%20chapter.xhtml' }, { label: 'Space t', href: 'my%20chapter.xhtml#t' },
      { label: 'Plus', href: 'a+b.xhtml' }, { label: 'Umlaut', href: 'Kapitel%20%C3%BCber.xhtml' },
      { label: 'Umlaut t', href: 'Kapitel%20%C3%BCber.xhtml#t' }, { label: 'Raw', href: 'Straße.xhtml' }],
  } },

  /** A chapter whose href climbs out of the container, and one that is path-absolute (from the container's root) */
  outside: { valid: false, errors: ['RSC-001', 'RSC-026'], opts: {
    title: 'Outside the container', author: 'Folders',
    rawChapters: [
      { file: 'one.xhtml', body: `<h1>First</h1>\n${paras('First', 8)}` },
      { file: '../../etc/passwd', absent: true, body: '<h1>Lost</h1>' },
      { file: '/OEBPS/three.xhtml', entry: 'OEBPS/three.xhtml', body: `<h1>Third</h1>\n${paras('Third', 8)}` },
    ],
    toc: [{ label: 'First', href: 'one.xhtml' }, { label: 'Lost', href: '../../etc/passwd' }, { label: 'Third', href: '/OEBPS/three.xhtml' }],
  } },

  /** Links between chapters of different folders: ../, no fragment, local, and back into the same chapter; a noteref to a notes file in a third folder */
  links: { valid: true, opts: {
    title: 'Links across folders', author: 'Folders',
    rawChapters: [
      { file: 'text/ch1.xhtml', body:
        `<h1>Start</h1>\n<p>Go <a href="../text/ch2.xhtml#far">far</a>, <a href="ch2.xhtml">to two</a>, <a href="#local">local</a>, ` +
        `<a href="../text/ch1.xhtml#self">self</a> and a note<a epub:type="noteref" href="../notes/notes.xhtml#n1">1</a>.</p>\n` +
        paras('Start', 14) + '\n<p id="local">Local target</p>\n' + paras('Start middle', 14) + '\n<p id="self">Self target</p>\n' + paras('Start end', 8) },
      { file: 'text/ch2.xhtml', body:
        `<h1>Second</h1>\n${paras('Second', 14)}\n<p id="far">Far target</p>\n${paras('Second end', 8)}` },
      { file: 'notes/notes.xhtml', body:
        `<h1>Notes</h1>\n<aside epub:type="footnote" id="n1"><p>Note one lives in a folder of its own.</p></aside>` },
    ],
    toc: [{ label: 'Start', href: 'text/ch1.xhtml' }, { label: 'Second', href: 'text/ch2.xhtml' }, { label: 'Notes', href: 'notes/notes.xhtml' }],
  } },

  /** A link, and a noteref, to a notes file that the manifest lists and the spine does not */
  unlisted: { valid: false, errors: ['RSC-011'], opts: {
    title: 'Notes outside the spine', author: 'Folders',
    rawChapters: [
      { file: 'text/ch1.xhtml', body:
        `<h1>Only</h1>\n<p>See <a href="../notes/unlisted.xhtml#n1">the note</a>, a note<a epub:type="noteref" href="../notes/unlisted.xhtml#n1">1</a>.</p>\n${paras('Only', 14)}` },
    ],
    extraFiles: [{ name: 'notes/unlisted.xhtml', mediaType: 'application/xhtml+xml', data:
      '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">' +
      '<head><title>Unlisted</title></head><body><h1>Unlisted notes</h1><aside epub:type="footnote" id="n1"><p>An unlisted note.</p></aside></body></html>' }],
    toc: [{ label: 'Only', href: 'text/ch1.xhtml' }],
  } },

  /** Two chapters that both have ids n1 and t, and both the word "needle" */
  repeated: { valid: true, opts: {
    title: 'Repeated ids', author: 'Folders',
    rawChapters: [1, 2].map(i => ({ file: `text/ch${i}.xhtml`, body:
      `<h1>Number ${i}</h1>\n<p id="top">Top of ${i}</p>\n<p>A claim<a epub:type="noteref" href="#n1">1</a> in chapter ${i}.</p>\n` +
      paras(`Part${i}`, 14) + `\n<p id="t">Target t of chapter ${i}, a needle</p>\n` + paras(`Part${i} end`, 8) +
      `\n<aside epub:type="footnote" id="n1"><p>The note of chapter ${i}.</p></aside>` })),
    toc: [{ label: 'Number 1', href: 'text/ch1.xhtml' }, { label: 'Note 1', href: 'text/ch1.xhtml#n1' },
      { label: 'Number 2', href: 'text/ch2.xhtml' }, { label: 'Note 2', href: 'text/ch2.xhtml#n1' }],
  } },

  /** Chapter 1 links one stylesheet and has a <style>; chapter 2 links another */
  styles: { valid: true, opts: {
    title: 'Styles per chapter', author: 'Folders',
    rawChapters: [
      { file: 'text/ch1.xhtml', head: '<link rel="stylesheet" type="text/css" href="../css/one.css"/><style>.own { font-size: 60px; }</style>',
        body: `<h1>Styled one</h1>\n<p class="big own">Big in one</p>\n${paras('One', 6)}` },
      { file: 'text/ch2.xhtml', head: '<link rel="stylesheet" type="text/css" href="../css/two.css"/>',
        body: `<h1>Styled two</h1>\n<p class="big own">Big in two</p>\n${paras('Two', 6)}` },
    ],
    extraFiles: [
      { name: 'css/one.css', mediaType: 'text/css', data: '.big { font-size: 72px; color: red; }' },
      { name: 'css/two.css', mediaType: 'text/css', data: 'p { letter-spacing: 1px; }' },
    ],
    toc: [{ label: 'Styled one', href: 'text/ch1.xhtml' }, { label: 'Styled two', href: 'text/ch2.xhtml' }],
  } },
};
