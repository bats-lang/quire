// Small EPUBs in the encodings a book's text may be in (#436): UTF-8 with
// a byte order mark, UTF-16 either way round, and the single-byte
// encodings EPUB 2 files are in (ISO-8859-1, windows-1252, windows-1255),
// with the faults those files have (no declaration, a wrong one), and the
// character references a text may hold. Each is checked by epubcheck
// (e2e/epubcheck.spec.js) where it is legal (EPUB 3 requires UTF-8 or
// UTF-16; the others are EPUB 2 files, as the old ones were) and read by
// e2e/encodings.spec.js. The first word of a chapter is its own, so that
// a search for it says the chapter was read.

import { Buffer } from 'node:buffer';

const PREFIX = '<?xml version="1.0" encoding="';
export const declaration = encoding => `${PREFIX}${encoding}"?>\n`;

/** A content document: its XML declaration (as given, or none), and a body */
export const document = (body, { declared = declaration('UTF-8'), epub2 = false, lang = '' } = {}) =>
  `${declared}${epub2
    ? '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">\n'
    : '<!DOCTYPE html>\n'}<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"${lang ? ` xml:lang="${lang}" lang="${lang}"` : ''}>\n` +
  `<head><title>Chapter 1</title></head>\n<body>\n${body}\n</body>\n</html>`;

// ---- the encodings, as bytes ----

export const utf16 = (text, order = 'le', bom = true) => {
  const le = Buffer.from(text, 'utf16le');
  const body = order === 'le' ? le : Buffer.from(le).swap16();
  return bom ? Buffer.concat([Buffer.from(order === 'le' ? [0xFF, 0xFE] : [0xFE, 0xFF]), body]) : body;
};

export const latin1 = text => Buffer.from(text, 'latin1');

const CP1252 = { '€': 0x80, '‚': 0x82, 'ƒ': 0x83, '„': 0x84, '…': 0x85, '†': 0x86, '‡': 0x87, 'ˆ': 0x88, '‰': 0x89, 'Š': 0x8A, '‹': 0x8B, 'Œ': 0x8C, 'Ž': 0x8E, '‘': 0x91, '’': 0x92, '“': 0x93, '”': 0x94, '•': 0x95, '–': 0x96, '—': 0x97, '˜': 0x98, '™': 0x99, 'š': 0x9A, '›': 0x9B, 'œ': 0x9C, 'ž': 0x9E, 'Ÿ': 0x9F };
export const windows1252 = text => Buffer.from([...text].map(c => CP1252[c] ?? c.charCodeAt(0)));

/** Hebrew letters are 0xE0 to 0xFA, the shekel sign 0xA4 */
export const windows1255 = text => Buffer.from([...text].map(c => {
  const code = c.charCodeAt(0);
  return code >= 0x5D0 && code <= 0x5EA ? code - 0x5D0 + 0xE0 : c === '₪' ? 0xA4 : code;
}));

/** こんにちは in Shift_JIS */
export const SHIFT_JIS_HELLO = Buffer.from([0x82, 0xB1, 0x82, 0xF1, 0x82, 0xC9, 0x82, 0xBF, 0x82, 0xCD]);

// ---- the books ----

const chapter2 = { body: '<h1>Second</h1>\n<p>Zanzibar second chapter, in UTF-8 as the first is not.</p>' };
const entry = 'OEBPS/chapter1.xhtml';

/** A book whose chapter 1 is the bytes given (a document whose first word is first) */
const withChapter = (title, bytes, extra = {}) => ({
  title, author: 'Encoding Tests', chapters: 2, rawChapters: [{ body: '<p>placeholder</p>' }, chapter2],
  entryBytes: { [entry]: bytes }, ...extra,
});

/** A book whose chapter 2 is the bytes given, after a chapter 1 of one short page: the chapter that is refused is
    turned to, and the reader stays on the page before it */
const withSecond = (title, bytes, extra = {}) => ({
  title, author: 'Encoding Tests', chapters: 2, rawChapters: [{ body: '<h1>One</h1>\n<p>Alpha, one short page.</p>' }, { body: '<p>placeholder</p>' }],
  entryBytes: { 'OEBPS/chapter2.xhtml': bytes }, ...extra,
});

const ordinary = word => `<h1>Part One</h1>\n<p>${word} is the first word of this chapter, and the rest is as plain as can be.</p>`;
const accents = word => `<h1>Part One</h1>\n<p>${word} café Zoë niño, Ångström and "quoted" text.</p>`;

export const encodingBooks = {
  /** A UTF-8 byte order mark on the chapter, the package and the navigation document */
  bom: { valid: true, opts: {
    title: 'Byte Order Mark', author: 'Encoding Tests', chapters: 2,
    rawChapters: [{ body: ordinary('Quillon') }, chapter2],
    bomEntries: ['OEBPS/content.opf', 'OEBPS/nav.xhtml', entry] } },

  /** A chapter in UTF-16 little endian with its byte order mark, declared UTF-16 (EPUB 3.3 allows UTF-16) */
  utf16le: { valid: false, errors: ['HTM_058'], opts: withChapter('Sixteen Little', utf16(document(ordinary('Quillon'), { declared: declaration('UTF-16') }), 'le')) },

  /** The same, big endian */
  utf16be: { valid: false, errors: ['HTM_058'], opts: withChapter('Sixteen Big', utf16(document(ordinary('Quillon'), { declared: declaration('UTF-16') }), 'be')) },

  /** A chapter of an EPUB 2 file declared ISO-8859-1, with accents in single bytes */
  latin1: { valid: false, errors: ['RSC-028'], opts: withChapter('Latin One', latin1(document(accents('Quillon'), { declared: declaration('ISO-8859-1'), epub2: true })),
    { epub2: true }) },

  /** A chapter declared windows-1252, with the characters it holds in 0x80 to 0x9F (curly quotes, a dash, the euro sign) */
  windows1252: { valid: false, errors: ['RSC-028'], opts: withChapter('Windows Twelve', windows1252(document('<h1>Part One</h1>\n<p>Quillon costs 5€ – “quoted” – and ‘single’.</p>', { declared: declaration('windows-1252'), epub2: true })),
    { epub2: true }) },

  /** A chapter declared windows-1255 holding Hebrew in single bytes */
  windows1255: { valid: false, errors: ['RSC-028'], opts: withChapter('Windows Hebrew', windows1255(document('<h1>Part One</h1>\n<p>Quillon שלום עולם, מה שלומך היום?</p>', { declared: declaration('windows-1255'), epub2: true })),
    { epub2: true, language: 'he' }) },

  /** A chapter with no declaration and no byte order mark whose bytes are Latin-1, not UTF-8 */
  undeclaredLatin1: { valid: true, opts: withSecond('Undeclared Latin', latin1(document(accents('Quillon'), { declared: '', epub2: true })),
    { epub2: true }) },

  /** A chapter declared UTF-8 whose bytes are Latin-1 */
  utf8DeclaredLatin1: { valid: true, opts: withSecond('Wrong Utf8', latin1(document(accents('Quillon'), { declared: declaration('UTF-8') }))) },

  /** A chapter declared ISO-8859-1 whose bytes are UTF-8: wrong about itself, read as UTF-8 */
  latin1DeclaredUtf8: { valid: false, errors: ['RSC-028'], opts: withChapter('Wrong Latin', Buffer.from(document(accents('Quillon'), { declared: declaration('ISO-8859-1'), epub2: true })), { epub2: true }) },

  /** A chapter declared Shift_JIS holding Japanese in it: an encoding Quire has no table for */
  shiftJis: { valid: false, errors: ['RSC-028'], opts: withSecond('Shift Jis', (() => {
    const [head, tail] = document('<h1>Part One</h1>\n<p>Quillon @@</p>', { declared: declaration('Shift_JIS'), epub2: true }).split('@@');
    return Buffer.concat([Buffer.from(head), SHIFT_JIS_HELLO, Buffer.from(tail)]);
  })(), { epub2: true }) },

  /** Character references that XML declares and numeric ones over the whole range: one past the BMP, Hebrew, the euro sign */
  references: { valid: true, opts: {
    title: 'Character References', author: 'Encoding Tests', chapters: 2,
    rawChapters: [{ body: '<h1>Part One</h1>\n<p id="refs">Quillon &#x1F600; &#1489; &#x200F;|&#x200D;| &#xE9; &#x5D0;&#x5D1; &amp; &lt; &gt; &quot; &apos; &#8364; &#xA0;end</p>' }, chapter2] } },

  /** HTML's named references in XHTML (nbsp, rlm, zwj, eacute, hellip, mdash), which XML does not declare: a fault books have */
  namedReferences: { valid: false, errors: ['RSC-016'], opts: {
    title: 'Named References', author: 'Encoding Tests', chapters: 2,
    rawChapters: [{ body: '<h1>Part One</h1>\n<p id="refs">Quillon &nbsp;|&rlm;|&zwj;| &eacute; &hellip; &mdash; &copy; end</p>' }, chapter2] } },
};

/** A text whose character of four bytes begins at byte offset at, in a paragraph of its own: a text node is
    passed on in pieces of 64 KiB, and an offset of 65533 to 65535 puts the cut inside the character */
export const emojiAt = (at, word) => `<p>${word}-${'a'.repeat(at - word.length - 1)}\u{1F600}END-${word}</p>`;

/** Three paragraphs whose emoji is cut at 64 KiB in its first, second and third byte */
encodingBooks.emojiCut = { valid: true, opts: {
  title: 'Emoji Cut', author: 'Encoding Tests', chapters: 1,
  rawChapters: [{ body: [emojiAt(65533, 'ALPHA'), emojiAt(65534, 'BRAVO'), emojiAt(65535, 'CHARLIE')].join('\n') }] } };

/** Titles and authors with non-ASCII letters and with references: how each is shown and where each sorts */
export const names = [
  // title (as the OPF writes it), what it is shown as, author as written, shown
  ['Zeta Book', 'Zeta Book', 'Anna', 'Anna'],
  ['Zo&#235; Book', 'Zoë Book', 'Zo&#235; Author', 'Zoë Author'],
  ['&#x141;ukasz Book', 'Łukasz Book', '&#x141;ukasz Author', 'Łukasz Author'],
  ['Lambda Book', 'Lambda Book', 'Ben', 'Ben'],
  ['Mu Book', 'Mu Book', 'Cora', 'Cora'],
  ['שלום עולם', 'שלום עולם', 'ישראל ישראלי', 'ישראל ישראלי'],
  ['日本語の本', '日本語の本', '夏目漱石', '夏目漱石'],
  ['Zoë Direct', 'Zoë Direct', 'Łukasz Direct', 'Łukasz Direct'],
];
names.forEach(([title, , author], k) => {
  encodingBooks[`name ${k}`] = { valid: true, opts: {
    title, author: 'Placeholder', creatorXml: `<dc:creator>${author}</dc:creator>`, chapters: 1,
    rawChapters: [{ body: `<h1>${title}</h1>\n<p>Name book ${k}.</p>` }] } };
});
