// Small EPUBs for the numbers of books in a series (#434): the whole
// numbers of a series, a novella between two volumes (2.5), a prequel
// numbered 0, a negative number, a comma as some locales write the
// point, a number that is not one, a book of two series and a book of a
// series with no number. Each is checked by epubcheck
// (e2e/epubcheck.spec.js) and read by e2e/series.spec.js. A book's
// series is written the way EPUB 3 does (belongs-to-collection and the
// group-position that refines it) or the way Calibre does
// (calibre:series and calibre:series_index).

/** EPUB 3's series: a collection of the series type and the position that refines it (none when position is null) */
export const epub3Series = (name, position, id = 'c1', type = 'series') =>
  `    <meta property="belongs-to-collection" id="${id}">${name}</meta>\n` +
  `    <meta refines="#${id}" property="collection-type">${type}</meta>\n` +
  (position === null ? '' : `    <meta refines="#${id}" property="group-position">${position}</meta>\n`);

/** Calibre's series (none when position is null) */
export const calibreSeries = (name, position) =>
  `    <meta name="calibre:series" content="${name}"/>\n` +
  (position === null ? '' : `    <meta name="calibre:series_index" content="${position}"/>\n`);

/** A one-chapter book of the series, whose title is title */
export const volumeOpts = (title, metadata) => ({
  title, author: 'Series Tests', chapters: 1, metadata,
  rawChapters: [{ body: `<h1>${title}</h1>\n<p>${title} is a short book of a series, with text enough to open.</p>` }],
});

const valid = (title, metadata) => ({ valid: true, opts: volumeOpts(title, metadata) });

export const seriesBooks = {};

/** The volumes the sort spec reads, in each form: titles whose own order (10 before 2, the novella first) is not the series' */
export const volumes = [['Foundation Vol 1', '1'], ['Foundation Vol 2', '2'], ['A Novella', '2.5'], ['Foundation Vol 3', '3'], ['Foundation Vol 10', '10']];
for (const [form, write] of [['epub3', epub3Series], ['calibre', calibreSeries]]) {
  volumes.forEach(([title, position], k) => {
    seriesBooks[`${form} volume ${position}`] = valid(`${form === 'epub3' ? 'Three' : 'Cal'} ${title}`, write('Foundation', position));
  });
}

/** Numbers as they are written: how each is shown ("" is none) and what it sorts as */
export const written = [
  ['two point zero', '2.0', '2'],
  ['one point two five', '1.25', '1.25'],
  ['one point five zero', '1.50', '1.5'],
  ['two point five', '2.5', '2.5'],
  ['three digits of fraction', '3.125', '3.12'],
  ['zero', '0', '0'],
  ['negative', '-1', '-1'],
  ['negative fraction', '-0.5', '-0.5'],
  ['comma', '2,5', '2.5'],
  ['plus sign', '+4', '4'],
  ['point only after', '5.', '5'],
  ['point only before', '.5', '0.5'],
  ['spaces around', '   3   ', '3'],
  ['roman', 'II', ''],
  ['words', 'Part Two', ''],
  ['inner space', '2 5', ''],
  ['exponent', '1e2', ''],
  ['two points', '1.2.3', ''],
  ['too large', '123456', ''],
];
/** The title of the k-th written number's book (two digits, so that no title holds another) */
export const writtenTitle = (k, name, prefix = 'W') => `${prefix}${String(k).padStart(2, '0')} ${name}`;
written.forEach(([name, text], k) => {
  seriesBooks[`written ${name}`] = valid(writtenTitle(k, name), epub3Series('Written', text));
});
written.slice(0, 3).forEach(([name, text], k) => {
  seriesBooks[`calibre written ${name}`] = valid(writtenTitle(k, name, 'C'), calibreSeries('Calibre Written', text));
});

/** A position that is empty or blank: not valid EPUB 3 (a meta element may not be empty, RSC-005), but books have it,
    and it is no number */
for (const [name, text] of [['empty', ''], ['blank', '   ']]) {
  seriesBooks[`${name} position`] = { valid: false, errors: ['RSC-005'], opts: volumeOpts(`Position ${name}`, epub3Series('Written', text)) };
}

/** Two series: the first is the book's, with its own position (the second's is not taken for it) */
seriesBooks['two series'] = valid('Two Series',
  epub3Series('First Series', '4', 'c1') + epub3Series('Second Series', '7', 'c2'));

/** A collection of the set type before the series: not the book's series */
seriesBooks['set before series'] = valid('Set Before Series',
  epub3Series('A Set Of Books', '9', 'c1', 'set') + epub3Series('Real Series', '3', 'c2'));

/** The series' own position follows the collection it refines, whatever the order of the metas */
seriesBooks['positions out of order'] = valid('Positions Out Of Order',
  `    <meta property="belongs-to-collection" id="c1">First Series</meta>\n` +
  `    <meta property="belongs-to-collection" id="c2">Second Series</meta>\n` +
  `    <meta refines="#c2" property="group-position">7</meta>\n` +
  `    <meta refines="#c1" property="group-position">4</meta>\n` +
  `    <meta refines="#c1" property="collection-type">series</meta>\n` +
  `    <meta refines="#c2" property="collection-type">series</meta>\n`);

/** EPUB 3's series and Calibre's for another, together: EPUB 3's is the book's */
seriesBooks['epub3 and calibre'] = valid('Epub3 And Calibre',
  epub3Series('Standard Series', '2') + calibreSeries('Calibre Series', '8'));

/** Books of a series with no number, and one numbered, to sort */
seriesBooks['no series'] = valid('Aaa Alone', '');
seriesBooks['unnumbered zulu'] = valid('Zulu Unnumbered', epub3Series('Mixed', null));
seriesBooks['unnumbered alpha'] = valid('Alpha Unnumbered', epub3Series('Mixed', null));
seriesBooks['numbered first'] = valid('Numbered First', epub3Series('Mixed', '1'));
seriesBooks['numbered second'] = valid('Numbered Second', epub3Series('Mixed', '2'));
seriesBooks['calibre unnumbered'] = valid('Calibre Unnumbered', calibreSeries('Mixed', null));
