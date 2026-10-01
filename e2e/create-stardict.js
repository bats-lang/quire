// A small StarDict dictionary, made on the fly for the e2e tests: its
// .ifo, .idx, .dict (or .dict.dz, dictzip's chunked gzip) and .syn.
//
// The format (as StarDict's own doc/StarDictFileFormat gives it):
// * .ifo: "StarDict's dict ifo file", then key=value lines;
// * .idx: records of word\0, the article's offset and size (u32,
//   big-endian), sorted as stardict_strcmp sorts: ASCII case-insensitive
//   first, then by bytes;
// * .syn: records of word\0 and a u32 (big-endian) index into the .idx
//   records, sorted the same way;
// * .dict.dz: a gzip file whose header's extra field has an "RA"
//   subfield (version 1, chunk length, chunk count, then each chunk's
//   compressed size); every chunk but the last ends with a full flush,
//   so it inflates on its own.

import { deflateRawSync, constants } from 'node:zlib';

/** stardict_strcmp: ASCII case-insensitive, then byte order */
export function stardictCompare(a, b) {
  const x = Buffer.from(a), y = Buffer.from(b);
  const lower = c => (c >= 65 && c <= 90 ? c + 32 : c);
  const n = Math.min(x.length, y.length);
  for (let i = 0; i < n; i++) {
    const d = lower(x[i]) - lower(y[i]);
    if (d) return d;
  }
  if (x.length !== y.length) return x.length - y.length;
  return Buffer.compare(x, y);
}

function u32(value) {
  const b = Buffer.alloc(4);
  b.writeUInt32BE(value);
  return b;
}

/** data as dictzip: chunks of chunkLength bytes, each inflatable alone */
export function dictzip(data, chunkLength = 64) {
  const chunks = [];
  for (let at = 0; at < data.length; at += chunkLength) chunks.push(data.subarray(at, at + chunkLength));
  if (chunks.length === 0) chunks.push(Buffer.alloc(0));
  const compressed = chunks.map((chunk, i) => deflateRawSync(chunk,
    i < chunks.length - 1 ? { finishFlush: constants.Z_FULL_FLUSH } : {}));
  // the RA subfield: version, chunk length, chunk count, the sizes
  const ra = Buffer.alloc(6 + 2 * chunks.length);
  ra.writeUInt16LE(1, 0);
  ra.writeUInt16LE(chunkLength, 2);
  ra.writeUInt16LE(chunks.length, 4);
  compressed.forEach((c, i) => ra.writeUInt16LE(c.length, 6 + 2 * i));
  const subfield = Buffer.concat([Buffer.from('RA'), Buffer.from([ra.length & 255, ra.length >> 8]), ra]);
  const header = Buffer.from([0x1f, 0x8b, 8, 4 | 8, 0, 0, 0, 0, 2, 3, subfield.length & 255, subfield.length >> 8]);
  // FNAME, as dictzip writes it
  const name = Buffer.from('test.dict\0');
  const trailer = Buffer.alloc(8);
  trailer.writeUInt32LE(data.length >>> 0, 4);
  return Buffer.concat([header, subfield, name, ...compressed, trailer]);
}

/**
 * @param {object} opts
 * @param {string} opts.name - bookname
 * @param {{word: string, article: string}[]} opts.entries
 * @param {{word: string, target: string}[]} [opts.synonyms] - other forms of an entry's word
 * @param {string|null} [opts.type] - sametypesequence ("m" by default; null leaves it out)
 * @param {boolean} [opts.dz] - the articles as .dict.dz
 * @param {number} [opts.idxFileSize] - the .ifo's idxfilesize, if not the true one
 * @param {number} [opts.offsetBits] - idxoffsetbits, when given
 * @returns {{ifo: Buffer, idx: Buffer, dict: Buffer, syn: Buffer|null, dz: boolean}}
 */
export function createStardict(opts) {
  const type = opts.type === undefined ? 'm' : opts.type;
  const entries = [...opts.entries].sort((a, b) => stardictCompare(a.word, b.word));
  const articles = [];
  const records = [];
  let offset = 0;
  for (const e of entries) {
    const article = Buffer.from(e.article);
    articles.push(article);
    records.push(Buffer.concat([Buffer.from(e.word + '\0'), u32(offset), u32(article.length)]));
    offset += article.length;
  }
  const idx = Buffer.concat(records);
  const plain = Buffer.concat(articles);
  const synonyms = [...(opts.synonyms || [])].sort((a, b) => stardictCompare(a.word, b.word));
  const syn = synonyms.length ? Buffer.concat(synonyms.map(s => {
    const target = entries.findIndex(e => e.word === s.target);
    return Buffer.concat([Buffer.from(s.word + '\0'), u32(target)]);
  })) : null;
  let ifo = "StarDict's dict ifo file\nversion=2.4.2\n"
    + `bookname=${opts.name}\nwordcount=${entries.length}\n`
    + (syn ? `synwordcount=${synonyms.length}\n` : '')
    + `idxfilesize=${opts.idxFileSize === undefined ? idx.length : opts.idxFileSize}\n`
    + (opts.offsetBits ? `idxoffsetbits=${opts.offsetBits}\n` : '')
    + (type ? `sametypesequence=${type}\n` : '')
    + 'description=Made for the e2e tests\n';
  return { ifo: Buffer.from(ifo), idx, dict: opts.dz ? dictzip(plain) : plain, syn, dz: !!opts.dz };
}
