// The books of e2e/w3c-epub-tests.spec.js: each a small EPUB made for one
// statement of the W3C's EPUB 3 test suite (https://github.com/w3c/epub-tests,
// quire#419), named by the suite's test it reproduces. A book is a valid
// EPUB (checked by epubcheck.spec.js) or invalid only in the way the test
// is about (`errors` names epubcheck's ids for it).
//
// create-epub.js makes the books whose package is Quire's own usual one;
// these need a package of their own (a manifest fallback, a package
// attribute, a title with a direction), so the package is written here.

import { createZip, solidPng, TINY_PNG } from './create-epub.js';

export const BOOK_ID = 'urn:uuid:3f2b7a52-0000-4000-8000-000000000419';

/** An XHTML content document: body in its body, head more of its head,
    attributes on its html element */
export const xhtml = (body, { head = '', attributes = '' } = {}) => `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"${attributes}>
<head><title>Test page</title>${head}</head>
<body>
${body}
</body>
</html>`;

/**
 * A package, as a zip. All of the book's files are under OEBPS/.
 *
 * - title, titles: the dc:title (more of them in titles, as XML text)
 * - creators: the dc:creator elements
 * - language, packageAttributes: the dc:language and the attributes of the
 *   package element
 * - titleAttributes, creatorAttributes: attributes of the first dc:title, of the first dc:creator
 * - items: [{ id, href, type, properties, fallback, data, store }]: the manifest's items and their files
 * - spine: [{ idref, properties }]
 * - toc: [{ href, label }] the navigation document's entries (label is XHTML), by default each
 *   XHTML item of the spine
 * - navBody: the navigation document's body, in place of the list made of toc
 * - archive: a function that is given the zip entries and returns them changed
 * - patch: a function that is given the zip's bytes and returns them changed
 */
export function packageEpub({
  title = 'W3C test', titles = '', creators = ['W3C Tests'], language = 'en', packageAttributes = '',
  titleAttributes = '', creatorAttributes = '', items = [], spine = [], toc = null, extraMetadata = '', navBody = null,
  archive = entries => entries, patch = bytes => bytes,
} = {}) {
  const manifest = items.map(i => `    <item id="${i.id}" href="${i.href}" media-type="${i.type}"` +
    `${i.properties ? ` properties="${i.properties}"` : ''}${i.fallback ? ` fallback="${i.fallback}"` : ''}/>\n`).join('');
  const entries = toc || spine.map(r => items.find(i => i.id === r.idref))
    .filter(i => i && i.type === 'application/xhtml+xml' && !i.properties?.includes('nav'))
    .map((i, k) => ({ href: i.href, label: `Entry ${k + 1}` }));
  const nav = xhtml(navBody || `<nav epub:type="toc"><ol>\n${entries.map(e => `<li><a href="${e.href}">${e.label}</a></li>`).join('\n')}\n</ol></nav>`);
  const opf = `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid"${packageAttributes ? ' ' + packageAttributes : ''}>
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">${BOOK_ID}</dc:identifier>
    <dc:title${titleAttributes ? ' ' + titleAttributes : ''}>${title}</dc:title>
${titles}${creators.map((c, k) => `    <dc:creator${k === 0 && creatorAttributes ? ' ' + creatorAttributes : ''}>${c}</dc:creator>\n`).join('')}    <dc:language>${language}</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
${extraMetadata}  </metadata>
  <manifest>
${manifest}    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
  </manifest>
  <spine>
${spine.map(r => `    <itemref idref="${r.idref}"${r.properties ? ` properties="${r.properties}"` : ''}/>\n`).join('')}  </spine>
</package>`;
  const container = `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>`;
  return patch(createZip(archive([
    { name: 'mimetype', data: 'application/epub+zip', store: true },
    { name: 'META-INF/container.xml', data: container, store: true },
    { name: 'OEBPS/content.opf', data: opf, store: true },
    { name: 'OEBPS/nav.xhtml', data: nav, store: true },
    ...items.filter(i => i.data !== undefined).map(i => ({ name: 'OEBPS/' + i.href, data: i.data, store: true })),
  ])));
}

/** An XHTML item of the package */
const page = (id, body, options = {}, more = {}) =>
  ({ id, href: `${id}.xhtml`, type: 'application/xhtml+xml', data: xhtml(body, options), ...more });

/** The archive's entries with the one named name marked as compressed with method (its bytes are
    not, and could not be inflated by it: the archive is read by its headers first) */
function withMethod(name, method) {
  return entries => {
    entries.find(e => e.name === name).method = method;
    return entries;
  };
}

/** The zip's end record changed to say the archive is the second of two segments (a split archive's
    last disk is not disk 0) */
function split(bytes) {
  const end = bytes.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  bytes.writeUInt16LE(1, end + 4); // number of this disk
  bytes.writeUInt16LE(1, end + 6); // disk where the central directory starts
  return bytes;
}

/** A book is { valid, errors, bytes() }: the epub's bytes made on demand */
const book = (make, { valid = true, errors = [] } = {}) => ({ valid, errors, bytes: make });

const PAGE_TEXT = 'The text of the page.';
const FALLBACK_TEXT = 'The fallback page is shown.';
const fallbackItem = page('fallback', `<p>${FALLBACK_TEXT}</p>`);
const closing = page('closing', '<p>The last page.</p>');

export const w3cBooks = {
  // Package Documents
  'two-titles': book(() => packageEpub({
    title: 'First title in the package', titles: '    <dc:title>Second title in the package</dc:title>\n    <dc:title>Third title in the package</dc:title>\n',
    items: [page('one', `<p>${PAGE_TEXT}</p>`)], spine: [{ idref: 'one' }],
  })),
  'two-creators': book(() => packageEpub({
    title: 'Creators in order', creators: ['First Creator', 'Second Creator', 'Third Creator'],
    items: [page('one', `<p>${PAGE_TEXT}</p>`)], spine: [{ idref: 'one' }],
  })),
  // Publication Resources and Manifest Fallbacks: a spine item of a type the reader does not show
  'json-spine': book(() => packageEpub({
    title: 'JSON in the spine',
    items: [
      { id: 'primary', href: 'novel.json', type: 'application/json', fallback: 'fallback', data: '{ "novel": [ { "para": "The JSON text, not shown." } ] }' },
      fallbackItem, closing,
    ],
    spine: [{ idref: 'primary' }, { idref: 'closing' }],
  })),
  'xml-spine': book(() => packageEpub({
    title: 'XML in the spine',
    items: [
      { id: 'primary', href: 'novel.xml', type: 'application/xml', fallback: 'fallback', data: '<?xml version="1.0"?><novel><para>The XML text, not shown.</para></novel>' },
      fallbackItem, closing,
    ],
    spine: [{ idref: 'primary' }, { idref: 'closing' }],
  })),
  'xml-suffix-spine': book(() => packageEpub({
    title: 'XML suffix in the spine',
    items: [
      { id: 'primary', href: 'novel.xml', type: 'application/x-novel+xml', fallback: 'fallback', data: '<?xml version="1.0"?><novel><para>The XML suffix text, not shown.</para></novel>' },
      fallbackItem, closing,
    ],
    spine: [{ idref: 'primary' }, { idref: 'closing' }],
  })),
  'image-spine': book(() => packageEpub({
    title: 'Image in the spine',
    items: [
      { id: 'primary', href: 'images/photograph.png', type: 'image/png', fallback: 'fallback', data: solidPng(1200, 900, [40, 90, 160], { noise: true }) },
      fallbackItem, closing,
    ],
    spine: [{ idref: 'primary' }, { idref: 'closing' }],
  })),
  'scripted-spine': book(() => packageEpub({
    title: 'Scripted page with a fallback',
    items: [
      page('primary', '<p id="state">The scripted page, not shown.</p>', { head: '<script>document.getElementById("state").textContent = "Scripted.";</script>' },
        { properties: 'scripted', fallback: 'fallback' }),
      fallbackItem, closing,
    ],
    spine: [{ idref: 'primary' }, { idref: 'closing' }],
  })),
  'unsupported-fallback': book(() => packageEpub({
    title: 'Both unsupported',
    items: [
      { id: 'primary', href: 'disk.dmg', type: 'application/x-apple-diskimage', fallback: 'second', data: 'BINARYMARK primary \u0000\u0001\u0002'.repeat(20) },
      { id: 'second', href: 'disk.psd', type: 'image/vnd.adobe.photoshop', data: 'BINARYMARK second \u0000\u0001\u0002'.repeat(20) },
      closing,
    ],
    spine: [{ idref: 'primary' }, { idref: 'closing' }],
  }), { valid: false, errors: ['OPF-044'] }),
  'foreign-image': book(() => packageEpub({
    title: 'Photoshop image with a fallback',
    items: [
      page('one', '<p>The snowflake below.</p><p><img src="snowflake.psd" alt="A snowflake"/></p>'),
      { id: 'photoshop', href: 'snowflake.psd', type: 'image/vnd.adobe.photoshop', fallback: 'snowflake', data: 'PSD, not an image Quire shows' },
      { id: 'snowflake', href: 'snowflake.png', type: 'image/png', data: solidPng(64, 64) },
    ],
    spine: [{ idref: 'one' }],
  })),
  // XML that is not well formed: the reader must report it
  'unclosed-tag': book(() => packageEpub({
    title: 'Unclosed tag',
    items: [page('one', '<p>This paragraph has an unclosed tag.</p><p>Another paragraph')],
    spine: [{ idref: 'one' }],
  }), { valid: false, errors: ['RSC-016'] }),
  'double-colon-name': book(() => packageEpub({
    title: 'Invalid element name',
    items: [page('one', '<p>This page has an element with an invalid name.</p><a::b>text</a::b>')],
    spine: [{ idref: 'one' }],
  }), { valid: false, errors: ['RSC-016'] }),
  'odd-markup': book(() => packageEpub({
    title: 'Odd but well formed markup',
    items: [page('one', '<!-- a <comment> with <tags> and no end tags --><p title="a > b">Both paragraphs<br/> are <![CDATA[ <b> ]]>shown.</p><?pi <x> ?>')],
    spine: [{ idref: 'one' }],
  })),
  // Internationalization: a title and a creator with a direction of their own, or the package's
  'directed-title': book(() => packageEpub({
    title: 'CSS: הרפתקה חדשה!', titleAttributes: 'dir="rtl" xml:lang="he"',
    creators: ['דוד קרמר'], creatorAttributes: 'dir="rtl" xml:lang="he"',
    items: [page('one', `<p>${PAGE_TEXT}</p>`)], spine: [{ idref: 'one' }],
  })),
  'root-directed-title': book(() => packageEpub({
    title: 'CSS: הרפתקה חדשה!', packageAttributes: 'dir="rtl"', language: 'ar',
    creators: ['דוד קרמר'],
    items: [page('one', `<p>${PAGE_TEXT}</p>`)], spine: [{ idref: 'one' }],
  })),
  'own-direction-over-root': book(() => packageEpub({
    title: 'CSS: הרפתקה חדשה!', titleAttributes: 'dir="ltr"', packageAttributes: 'dir="rtl"', language: 'ar',
    creators: ['דוד קרמר'], creatorAttributes: 'dir="ltr"',
    items: [page('one', `<p>${PAGE_TEXT}</p>`)], spine: [{ idref: 'one' }],
  })),
  // Publication Resources: addresses
  'path-absolute-image': book(() => packageEpub({
    title: 'Image by an absolute path',
    items: [
      page('one', '<p>The photograph below.</p><p><img src="/OEBPS/images/photograph.png" alt="A photograph"/></p>'),
      { id: 'photograph', href: 'images/photograph.png', type: 'image/png', data: solidPng(80, 80) },
    ],
    spine: [{ idref: 'one' }],
  }), { valid: false, errors: ['RSC-026'] }),
  'data-url-image': book(() => packageEpub({
    title: 'Image as a data URL',
    items: [page('one', `<p>The image below is a data URL.</p><p><img src="data:image/png;base64,${TINY_PNG.toString('base64')}" alt="A pixel" width="40" height="40"/></p>`)],
    spine: [{ idref: 'one' }],
  })),
  // Navigation Documents
  'nav-image-label': book(() => packageEpub({
    title: 'Image in a navigation label',
    items: [page('one', '<p>First page.</p>'), page('two', '<p>Second page.</p>'),
      { id: 'abbey', href: 'abbey.png', type: 'image/png', data: solidPng(64, 64) }],
    spine: [{ idref: 'one' }, { idref: 'two' }],
    toc: [{ href: 'one.xhtml', label: 'Start page' }, { href: 'two.xhtml', label: '<img src="abbey.png" alt="Description of the Abbey" title="The Abbey"/>' }],
  })),
  'nav-in-spine-hidden': book(() => packageEpub({
    title: 'Navigation document in the spine, an entry hidden',
    items: [page('one', '<p>First page.</p>'), page('two', '<p>Second page.</p>')],
    spine: [{ idref: 'nav' }, { idref: 'one' }, { idref: 'two' }],
    navBody: '<h1>Contents</h1><nav epub:type="toc"><ol>\n<li><a href="one.xhtml">The first link</a></li>\n<li hidden="hidden"><a href="two.xhtml">The second link</a></li>\n</ol></nav>',
  })),
  // OCF: the zip container
  'zip-bzip2': book(() => packageEpub({
    title: 'Compressed with bzip2',
    items: [page('one', `<p>${PAGE_TEXT}</p>`)], spine: [{ idref: 'one' }],
    archive: withMethod('OEBPS/one.xhtml', 12),
  }), { valid: false, errors: ['PKG-027'] }),
  'zip-split': book(() => packageEpub({
    title: 'A split archive',
    items: [page('one', `<p>${PAGE_TEXT}</p>`)], spine: [{ idref: 'one' }],
    patch: split,
  })), // epubcheck does not see the end record's disk numbers: valid to it, a split archive to the test
};

/** The texts the books are made to show */
export const W3C_TEXT = { PAGE_TEXT, FALLBACK_TEXT };
