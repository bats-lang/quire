// Small EPUB 3 books in the archives and containers real tools write (#433):
// ZIP quirks (data descriptors, UTF-8 names, extra fields, a comment, ZIP64,
// a wrong CRC, duplicate names, directory entries), the mimetype entry
// written wrongly, a container.xml with two rootfiles or an odd full-path,
// extra META-INF files, and OPF variants. Each is made by create-epub.js, read
// back as entries and written again by zip-writer.js with the quirk in it, so
// the book is the same one. Checked by epubcheck (e2e/epubcheck.spec.js):
// `valid` ones must pass; an invalid one is invalid on purpose, and `errors`
// names the only messages it may give.

import { createEpub } from './create-epub.js';
import { readZip, writeZip, extraField, timestampExtra, unixExtra, zip64Extra } from './zip-writer.js';

const OPF = 'OEBPS/content.opf';
const base = (title, more = {}) => createEpub({ title, author: 'Containers', chapters: 3, paragraphsPerChapter: 8, ...more });

/** The entries of a book made from opts, changed by change(entries) */
const archive = (title, change, more, zipOptions) => {
  const bytes = () => {
    const entries = readZip(base(title, more));
    return writeZip(change(entries) || entries, zipOptions);
  };
  bytes.title = title;
  return bytes;
};
const find = (entries, name) => entries.find(entry => entry.name === name);
const text = entry => entry.data.toString('utf8');
const setText = (entries, name, change) => { const entry = find(entries, name); entry.data = Buffer.from(change(text(entry)), 'utf8'); };

const chapterName = k => `OEBPS/chapter${k}.xhtml`;
const isMimetype = entry => entry.name === 'mimetype';

export const containerBooks = {
  /** Deflated entries with their sizes and CRC after the data (bit 3), as Java's and Sigil's streaming writers make them */
  descriptors: { valid: true, bytes: archive('Data descriptors', entries => entries.map(entry =>
    isMimetype(entry) || entry.store ? entry : { ...entry, descriptor: true })) },

  /** The same without the descriptor's signature, which the specification allows */
  descriptorsBare: { valid: true, bytes: archive('Bare descriptors', entries => entries.map(entry =>
    isMimetype(entry) || entry.store ? entry : { ...entry, descriptor: 'bare' })) },

  /** A name flagged UTF-8 (bit 11) and one not flagged but in UTF-8 anyway, both with non-ASCII names the OPF names */
  utf8Names: { valid: true, bytes: archive('UTF-8 names', entries => entries.map(entry =>
    entry.name === 'OEBPS/Größe.xhtml' ? { ...entry, utf8: true } : entry), {
      chapters: 2,
      rawChapters: [
        { file: 'Größe.xhtml', body: '<h1>Flagged</h1><p>Flagged name 0.</p>' },
        { file: 'Straße.xhtml', body: '<h1>Unflagged</h1><p>Unflagged name 0.</p>' },
      ],
      toc: [{ label: 'Flagged', href: 'Größe.xhtml' }, { label: 'Unflagged', href: 'Straße.xhtml' }] }) },

  /** An archive comment, and the timestamp, unix and ZIP64 extra fields in both headers */
  extras: { valid: true, bytes: archive('Comment and extra fields', entries => entries.map(entry => ({
    ...entry,
    ...(isMimetype(entry) ? {} : {
      localExtra: Buffer.concat([timestampExtra(), unixExtra()]),
      centralExtra: Buffer.concat([timestampExtra(), unixExtra(), zip64Extra(entry.data.length, entry.data.length)]) }),
  })), {}, { comment: 'Made by a tool that writes comments.' }) },

  /** A local header whose extra field is longer than the central directory's: the data starts after the local header's own lengths */
  localExtraDiffers: { valid: true, bytes: archive('Local header longer', entries => entries.map(entry =>
    isMimetype(entry) ? entry : { ...entry, localExtra: Buffer.concat([timestampExtra(), unixExtra(), extraField(0xCAFE, Buffer.alloc(40))]), centralExtra: Buffer.alloc(0) })) },

  /** A small archive in ZIP64 form: the ZIP64 end record and its locator, and each entry's sizes in a ZIP64 extra */
  zip64: { valid: true, bytes: archive('ZIP64 form', entries => entries.map(entry => ({ ...entry, zip64: true })), {}, { zip64End: true }) },

  /** A mimetype entry that is deflated */
  mimetypeDeflated: { valid: false, errors: ['PKG-007'], bytes: archive('Deflated mimetype', entries =>
    entries.map(entry => isMimetype(entry) ? { ...entry, store: false } : entry)) },

  /** A mimetype entry that is not the first */
  mimetypeNotFirst: { valid: false, errors: ['PKG-006'], bytes: archive('Mimetype not first', entries =>
    [...entries.filter(entry => !isMimetype(entry)), ...entries.filter(isMimetype)]) },

  /** A mimetype entry with an extra field in its local header */
  mimetypeExtra: { valid: false, errors: ['PKG-005'], bytes: archive('Mimetype with extra', entries =>
    entries.map(entry => isMimetype(entry) ? { ...entry, localExtra: timestampExtra() } : entry)) },

  /** No mimetype entry at all */
  mimetypeMissing: { valid: false, errors: ['PKG-006'], bytes: archive('No mimetype', entries => entries.filter(entry => !isMimetype(entry))) },

  /** A chapter whose stored CRC is not its data's (the deflate stream is whole) */
  wrongCrc: { valid: true, bytes: archive('Wrong CRC', entries =>
    entries.map(entry => entry.name === chapterName(2) ? { ...entry, crc: 0x12345678 } : entry)) },

  /** Two entries named OEBPS/chapter1.xhtml, the later with other words */
  duplicateName: { valid: false, errors: ['OPF-060'], bytes: archive('Duplicate names', entries => {
    const first = find(entries, chapterName(1));
    const second = { ...first, data: Buffer.from(text(first).replace('Chapter 1', 'Second Copy'), 'utf8') };
    return [...entries, second];
  }) },

  /** Directory entries (OEBPS/ and META-INF/) among the files */
  directories: { valid: true, bytes: archive('Directory entries', entries => [
    entries[0],
    { name: 'META-INF/', data: Buffer.alloc(0), directory: true },
    ...entries.slice(1),
    { name: 'OEBPS/', data: Buffer.alloc(0), directory: true },
  ]) },

  /** Every name after "./" (a tool that writes relative paths) */
  dotSlashNames: { valid: true, bytes: archive('Dot slash names', entries =>
    entries.map(entry => isMimetype(entry) ? entry : { ...entry, name: `./${entry.name}` })) },

  /** Backslashes for slashes in the names (a tool for Windows) */
  backslashNames: { valid: false, errors: ['PKG-009', 'RSC-002'], bytes: archive('Backslash names', entries =>
    entries.map(entry => isMimetype(entry) ? entry : { ...entry, name: entry.name.replaceAll('/', '\\') })) },

  /** Two rootfiles: a second rendition of another title with its own chapter */
  twoRootfiles: { valid: true, bytes: Object.assign(() => {
    const entries = readZip(base('First Rendition'));
    const other = readZip(createEpub({ title: 'Second Rendition', author: 'Containers', rawChapters: [{ body: '<h1>Other</h1><p>Other rendition 0.</p>' }], toc: [{ label: 'Other', href: 'chapter1.xhtml' }] }));
    const container = find(entries, 'META-INF/container.xml');
    container.data = Buffer.from(text(container).replace('</rootfiles>',
      '  <rootfile full-path="OTHER/content.opf" media-type="application/oebps-package+xml"/>\n  </rootfiles>'), 'utf8');
    for (const entry of other) {
      if (entry.name.startsWith('OEBPS/')) entries.push({ ...entry, name: entry.name.replace('OEBPS/', 'OTHER/') });
    }
    return writeZip(entries);
  }, { title: 'First Rendition' }) },

  /** A full-path with an encoded space (the package is in a folder with a space) */
  rootfileEncoded: { valid: true, bytes: Object.assign(() => {
    const entries = readZip(base('Encoded full-path')).map(entry =>
      entry.name.startsWith('OEBPS/') ? { ...entry, name: entry.name.replace('OEBPS/', 'OPS dir/') } : entry);
    setText(entries, 'META-INF/container.xml', xml => xml.replace('OEBPS/', 'OPS%20dir/'));
    return writeZip(entries);
  }, { title: 'Encoded full-path' }) },

  /** A full-path with a leading slash */
  rootfileSlash: { valid: false, errors: ['RSC-026'], bytes: archive('Leading slash', entries => {
    setText(entries, 'META-INF/container.xml', xml => xml.replace('full-path="OEBPS/', 'full-path="/OEBPS/'));
  }) },

  /** A full-path that names a file the archive does not have */
  rootfileMissing: { valid: false, errors: ['OPF-002'], bytes: archive('Missing package', entries => {
    setText(entries, 'META-INF/container.xml', xml => xml.replace('OEBPS/content.opf', 'OEBPS/missing.opf'));
  }) },

  /** META-INF/metadata.xml, manifest.xml and signatures.xml next to the container (rights.xml is Adobe's DRM, refused by drm.spec.js) */
  metaInfFiles: { valid: false, errors: ['RSC-005'], bytes: archive('Other META-INF files', entries => [
    ...entries,
    { name: 'META-INF/metadata.xml', data: '<?xml version="1.0"?>\n<metadata xmlns="http://www.idpf.org/2013/metadata"/>' },
    { name: 'META-INF/manifest.xml', data: '<?xml version="1.0"?>\n<manifest xmlns="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"/>' },
    { name: 'META-INF/signatures.xml', data: '<?xml version="1.0"?>\n<signatures xmlns="urn:oasis:names:tc:opendocument:xmlns:container"/>' },
  ]) },

  /** An OPF with a byte order mark */
  opfBom: { valid: true, bytes: archive('OPF with BOM', entries => {
    find(entries, OPF).data = Buffer.concat([Buffer.from([0xEF, 0xBB, 0xBF]), find(entries, OPF).data]);
  }) },

  /** An OPF with a DOCTYPE and an xml-stylesheet instruction */
  opfDoctype: { valid: true, bytes: archive('OPF with DOCTYPE', entries => {
    setText(entries, OPF, xml => xml.replace('?>\n', '?>\n<?xml-stylesheet type="text/css" href="style.css"?>\n<!DOCTYPE package>\n'));
  }) },

  /** An OPF whose every element has the opf: prefix */
  opfPrefixed: { valid: true, bytes: archive('OPF with prefixes', entries => {
    setText(entries, OPF, xml => xml
      .replace(/<(\/?)(package|metadata|manifest|spine|guide|item|itemref|meta|reference)\b/g, '<$1opf:$2')
      .replace('<opf:package xmlns="http://www.idpf.org/2007/opf"', '<opf:package xmlns:opf="http://www.idpf.org/2007/opf"'));
  }) },

  /** An OPF with CRLF line ends */
  opfCrlf: { valid: true, bytes: archive('OPF with CRLF', entries => { setText(entries, OPF, xml => xml.replace(/\n/g, '\r\n')); }) },
};

