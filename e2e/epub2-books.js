// Small EPUB 2 books (OPF 2.0, XHTML 1.1, an NCX, no nav document), made
// by create-epub.js's `epub2`. Each is checked by epubcheck
// (e2e/epubcheck.spec.js): `valid` ones must pass it; an invalid one is
// invalid on purpose, and `errors` names the only messages it may give.

const filler = 'lorem ipsum dolor sit amet '.repeat(10);
const part = (i, extra = '') => ({ body: `<h1 id="part${i}">Part ${i}</h1>\n<p>Part ${i} text. ${extra}${filler}</p>` });
const parts = [part(1), part(2), part(3)];
const toc = [
  { label: 'First part', href: 'chapter1.xhtml' },
  { label: 'Second part', href: 'chapter2.xhtml', children: [{ label: 'Deep in two', href: 'chapter2.xhtml#part2' }] },
  { label: 'Third part', href: 'chapter3.xhtml' },
];
const book = (title, more) => ({ title, author: 'Ann Author', epub2: true, rawChapters: parts, toc, ...more });

const navPoint = (order, label, src) =>
  `<navPoint id="np${order}" playOrder="${order}"><navLabel><text>${label}</text></navLabel>${src === null ? '' : `<content src="${src}"/>`}</navPoint>\n`;

const dtbook = `<?xml version="1.0" encoding="UTF-8"?>
<dtbook xmlns="http://www.daisy.org/z3986/2005/dtbook/" version="2005-2" xml:lang="en">
<head><meta name="dc:Title" content="A DTBook"/><meta name="dtb:uid" content="dtbook-1"/></head>
<book><bodymatter><level1><h1>DTBook heading</h1><p>DTBook paragraph. ${filler}</p></level1></bodymatter></book>
</dtbook>`;
const oeb1 = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "+//ISBN 0-9673008-1-9//DTD OEB 1.2 Document//EN" "http://openebook.org/dtds/oeb-1.2/oebdoc12.dtd">
<html><head><title>An OEB 1 document</title></head><body><h1>OEB1 heading</h1><p>OEB1 paragraph. ${filler}</p></body></html>`;

export const epub2Books = {
  /** dc:identifier, dc:language, an NCX and no nav: title, author, contents */
  plain: { valid: true, opts: book('Plain EPUB 2', {
    creatorXml: '<dc:creator opf:role="aut" opf:file-as="Author, Ann">Ann Author</dc:creator>' }) },

  /** The cover named the EPUB 2 way: <meta name="cover" content="id"/> */
  cover: { valid: true, opts: book('EPUB 2 with a cover', { coverImage: true, rawChapters: parts.slice(0, 2), toc: [
    { label: 'First part', href: 'chapter1.xhtml' }, { label: 'Second part', href: 'chapter2.xhtml' }] }) },

  /** Play orders out of document order, nested */
  ncxOutOfOrder: { valid: true, opts: book('NCX out of order', { ncxNavMap:
    `<navPoint id="np3" playOrder="3"><navLabel><text>Third part</text></navLabel><content src="chapter3.xhtml"/></navPoint>\n` +
    `<navPoint id="np1" playOrder="1"><navLabel><text>First part</text></navLabel><content src="chapter1.xhtml"/>` +
    navPoint(2, 'Inside the first', 'chapter1.xhtml#part1') + `</navPoint>\n` +
    navPoint(4, 'Second part', 'chapter2.xhtml') }) },

  /** A navPoint with no content (the NCX requires one) */
  ncxNoContent: { valid: false, errors: ['RSC-005'], opts: book('NCX no content', { ncxNavMap:
    navPoint(1, 'First part', 'chapter1.xhtml') + navPoint(2, 'Goes nowhere', null) + navPoint(3, 'Third part', 'chapter3.xhtml') }) },

  /** A navPoint whose label is empty */
  ncxEmptyLabel: { valid: true, opts: book('NCX empty label', { ncxNavMap:
    navPoint(1, 'First part', 'chapter1.xhtml') + navPoint(2, '', 'chapter2.xhtml') + navPoint(3, 'Third part', 'chapter3.xhtml') }) },

  /** XHTML 1.1's named entities, which the DOCTYPE brings */
  entities: { valid: true, opts: book('Named entities', { rawChapters: [
    { body: '<h1>Entities</h1>\n<p>Before&nbsp;after &mdash; dash &ldquo;quoted&rdquo; &copy; 2026 &eacute;t&eacute; &hellip; ' + filler + '</p>' },
    part(2), part(3)] }) },

  /** A package that says 2.0 and also has a nav document: the nav's
      `properties` is not in OPF 2.0 */
  declaredTwoWithNav: { valid: false, errors: ['RSC-005', 'HTM-004'], opts: book('Two with a nav', { alsoNav: true }) },

  /** A Hebrew book that says nothing of its page direction */
  hebrew: { valid: true, opts: book('Hebrew', { language: 'he', rawChapters: [
    { lang: 'he', body: '<h1 dir="rtl">פרק ראשון</h1>\n<p dir="rtl">זהו הטקסט הראשון של הספר. ' + 'שלום עולם '.repeat(40) + '</p>' },
    part(2), part(3)] }) },

  /** A DTBook spine item, with an XHTML fallback */
  dtbook: { valid: true, opts: book('A DTBook item', { rawChapters: [part(1), part(2)], toc: [
    { label: 'First part', href: 'chapter1.xhtml' }, { label: 'Second part', href: 'chapter2.xhtml' }],
    extraSpine: [{ id: 'dtb1', href: 'dtbook1.xml', mediaType: 'application/x-dtbook+xml', data: dtbook, fallback: 'ch2' }] }) },

  /** An OEB 1 document spine item, with an XHTML fallback */
  oeb1: { valid: true, opts: book('An OEB 1 item', { rawChapters: [part(1), part(2)], toc: [
    { label: 'First part', href: 'chapter1.xhtml' }, { label: 'Second part', href: 'chapter2.xhtml' }],
    extraSpine: [{ id: 'oeb1', href: 'oeb1.html', mediaType: 'text/x-oeb1-document', data: oeb1, fallback: 'ch2' }] }) },
};
