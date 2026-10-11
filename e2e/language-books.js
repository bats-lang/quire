// Small EPUBs whose language is missing, odd or contradicted by the text
// (#436): Hebrew and Japanese text in a book that names no language, a
// book that says English whose chapter says Hebrew, the forms a
// dc:language is written in (EN-us, en_US, eng, heb, zh-Hant-TW, two of
// them), and a French phrase in an English book. Each is checked by
// epubcheck (e2e/epubcheck.spec.js; a package with no dc:language, or
// with en_US, is invalid in the one way its entry says) and read by
// e2e/languages.spec.js.

const hebrew = 'שלום עולם, זהו ספר קצר בעברית. הוא נכתב כדי לבדוק את הכיוון של הטקסט. עוד משפט אחד כאן.';
const japanese = '吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。';

export const hebrewBody = (n = 12) => `<h1>פרק ראשון</h1>\n` + Array.from({ length: n }, (_, k) => `<p>פסקה ${k} ${hebrew}</p>`).join('\n');
export const japaneseBody = (n = 12) => `<h1>第一章</h1>\n` + Array.from({ length: n }, (_, k) => `<p>段落 ${k} ${japanese}</p>`).join('\n');
const english = n => `<h1>Chapter One</h1>\n` + Array.from({ length: n }, (_, k) => `<p>Paragraph ${k} ` + 'lorem ipsum dolor sit amet. '.repeat(8) + '</p>').join('\n');

const base = (title, extra) => ({ title, author: 'Language Tests', chapters: 1, rawChapters: [{ body: english(6) }], ...extra });

export const languageBooks = {
  /** Hebrew text, and no dc:language (required by EPUB 3: RSC-005) */
  hebrewNoLanguage: { valid: false, errors: ['RSC-005'], opts: base('Hebrew No Language', { language: '', rawChapters: [{ body: hebrewBody() }, { body: hebrewBody(4) }], chapters: 2 }) },

  /** Japanese text, a spine that reads right to left, and no dc:language */
  japaneseNoLanguage: { valid: false, errors: ['RSC-005'], opts: base('Japanese No Language', { language: '', rtl: true, rawChapters: [{ body: japaneseBody() }, { body: japaneseBody(4) }], chapters: 2 }) },

  /** The same Japanese text with its language, which is what makes it vertical */
  japaneseWithLanguage: { valid: true, opts: base('Japanese With Language', { language: 'ja', rtl: true, rawChapters: [{ body: japaneseBody() }, { body: japaneseBody(4) }], chapters: 2 }) },

  /** dc:language en, the chapter's xml:lang he, and Hebrew text */
  chapterOverrides: { valid: true, opts: base('Chapter Overrides', { language: 'en', rawChapters: [{ body: hebrewBody(), lang: 'he' }, { body: english(6) }], chapters: 2 }) },

  /** A French phrase in an English book, in a span of its own */
  frenchSpan: { valid: true, opts: base('French Span', { language: 'en', rawChapters: [{ body:
    '<h1>Chapter One</h1>\n<p>She said <span xml:lang="fr" lang="fr" id="phrase">c\'est la vie</span> and left the room quietly.</p>\n' +
    '<p lang="fr" xml:lang="fr" id="french">Ceci est un paragraphe tout entier en français. Il y a deux phrases.</p>\n' +
    '<p>The last paragraph is English again.</p>' }] }) },
};

/** The forms a dc:language is written in, and the tag each is read as */
export const forms = [
  ['upper', 'EN-us', 'en-US'],
  ['underscore', 'en_US', 'en-US'],
  ['iso 639-2 english', 'eng', 'en'],
  ['iso 639-2 hebrew', 'heb', 'he'],
  ['script and region', 'zh-Hant-TW', 'zh-Hant-TW'],
  ['old hebrew code', 'iw', 'he'],
  ['french', 'FRA', 'fr'],
];
for (const [name, written, tag] of forms) {
  // en_US is not a well-formed tag, so EPUB 3 does not allow it (OPF-092)
  languageBooks[`form ${name}`] = written === 'en_US'
    ? { valid: false, errors: ['OPF-092'], opts: base(`Form ${name}`, { language: written }) }
    : { valid: true, opts: base(`Form ${name}`, { language: written }) };
}

/** Two dc:language elements: the first is the book's */
languageBooks['two languages'] = { valid: true, opts: base('Two Languages', { language: 'fr', metadata: '    <dc:language>de</dc:language>\n' }) };
