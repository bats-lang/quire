// Books with an embedded font, plain or masked by the two obfuscations the
// EPUB OCF names (section 4.1.2; quire#410), and books whose font cannot be
// had. The font (marker-font.ttf, made with fontTools) has one glyph no
// system or bundled font has, U+E000, 1.7 em wide, so a test tells the
// book's face from a fallback by measuring that one character. Each book is
// checked by epubcheck (e2e/epubcheck.spec.js).

import { readFileSync } from 'node:fs';
import { randomBytes } from './create-epub.js';

export const markerFont = readFileSync(new URL('./marker-font.ttf', import.meta.url));

const uuid = 'urn:uuid:3f2a9c1e-7b64-4d58-9a0e-5c1d2b8e6f47';

/** A one-chapter book whose text begins with the marker glyph, the font masked as algorithm says */
const book = (title, fonts, more = {}) => ({
  title, author: 'Font Tests', chapters: 1,
  rawChapters: [{ body: '<h1>Fonts</h1>\n<p id="marker"></p>\n<p>Plain words follow the marker.</p>' }],
  obfuscatedFonts: fonts, ...more,
});
const ttf = (algorithm, data = markerFont) => [{ name: 'fonts/marker.ttf', data, algorithm, mediaType: 'font/ttf' }];

export const fontBooks = {
  /** The font as it is, in no encryption.xml */
  plain: { valid: true, opts: { ...book('Plain Font Book', []), extraFiles: [{ name: 'fonts/marker.ttf', data: markerFont, mediaType: 'font/ttf', store: true }] } },
  /** IDPF's obfuscation, the key from the package's unique identifier (a UUID) */
  idpf: { valid: true, opts: book('Idpf Font Book', ttf('idpf'), { identifier: uuid }) },
  /** IDPF's again, the identifier written with white space in it, which the key leaves out */
  idpfSpaced: { valid: true, opts: book('Idpf Spaced Font Book', ttf('idpf'), { identifier: '\n   urn:isbn:978-3-16 148410-0\t \n' }) },
  /** Adobe's, the key from the UUID of the identifier */
  adobe: { valid: true, opts: book('Adobe Font Book', ttf('adobe'), { identifier: uuid }) },
  /** Adobe's with an identifier that is no UUID: the key cannot be made */
  adobeNoUuid: { valid: true, opts: book('Adobe Not Uuid Book', ttf('adobe'), { identifier: 'urn:isbn:9783161484100' }) },
  /** An algorithm nobody knows over the font alone (DRM on a font): the text reads, the font is not used */
  unknownAlgorithm: { valid: true, opts: book('Unknown Cipher Font Book', ttf('urn:example:cipher:rot13')) },
  /** The same under AES, a font only (a book whose chapters are plain) */
  aesFont: { valid: true, opts: book('Aes Font Book', ttf('http://www.w3.org/2001/04/xmlenc#aes128-cbc')) },
  /** A font the manifest lists and the archive lacks */
  missing: { valid: false, errors: ['RSC-001'], opts: book('Missing Font Book', [], { manifestOnly: [{ name: 'fonts/marker.ttf', mediaType: 'font/ttf' }] }) },
  /** A font that is not one (2 KB of noise), masked */
  corrupt: { valid: true, opts: book('Corrupt Font Book', ttf('idpf', randomBytes(2048, 11)), { identifier: uuid }) },
  /** A font shorter than the 1040 bytes the mask covers */
  short: { valid: true, opts: book('Short Font Book', ttf('idpf', randomBytes(100, 12)), { identifier: uuid }) },
};
