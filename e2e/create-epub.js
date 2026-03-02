/**
 * Minimal EPUB creator for e2e testing.
 *
 * Builds a valid EPUB 3 file (which is a ZIP archive) from scratch
 * using Node.js zlib for deflate compression. No external dependencies.
 */

import { deflateRawSync, inflateRawSync } from 'node:zlib';

// CRC-32 lookup table
const crcTable = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    table[n] = c;
  }
  return table;
})();

function crc32(buf) {
  let crc = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) {
    crc = crcTable[(crc ^ buf[i]) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

function toBytes(str) {
  return Buffer.from(str, 'utf-8');
}

/**
 * Create a ZIP file from an array of { name, data, store } entries.
 * If store is true, the entry is stored uncompressed (required for mimetype).
 */
function createZip(entries) {
  const localHeaders = [];
  const centralEntries = [];
  let offset = 0;

  for (const entry of entries) {
    const nameBytes = toBytes(entry.name);
    const rawData = typeof entry.data === 'string' ? toBytes(entry.data) : entry.data;
    const crc = crc32(rawData);
    const uncompressedSize = rawData.length;

    let compressedData;
    let method;
    if (entry.store) {
      compressedData = rawData;
      method = 0; // stored
    } else {
      compressedData = deflateRawSync(rawData);
      method = 8; // deflate
    }
    const compressedSize = compressedData.length;

    // Local file header (30 bytes + name + data)
    const local = Buffer.alloc(30 + nameBytes.length + compressedData.length);
    local.writeUInt32LE(0x04034B50, 0);   // signature
    local.writeUInt16LE(20, 4);            // version needed
    local.writeUInt16LE(0, 6);             // flags
    local.writeUInt16LE(method, 8);        // compression method
    local.writeUInt16LE(0, 10);            // mod time
    local.writeUInt16LE(0, 12);            // mod date
    local.writeUInt32LE(crc, 14);          // crc-32
    local.writeUInt32LE(compressedSize, 18);
    local.writeUInt32LE(uncompressedSize, 22);
    local.writeUInt16LE(nameBytes.length, 26);
    local.writeUInt16LE(0, 28);            // extra field length
    nameBytes.copy(local, 30);
    compressedData.copy(local, 30 + nameBytes.length);

    // Central directory entry (46 bytes + name)
    const central = Buffer.alloc(46 + nameBytes.length);
    central.writeUInt32LE(0x02014B50, 0);  // signature
    central.writeUInt16LE(20, 4);          // version made by
    central.writeUInt16LE(20, 6);          // version needed
    central.writeUInt16LE(0, 8);           // flags
    central.writeUInt16LE(method, 10);     // compression method
    central.writeUInt16LE(0, 12);          // mod time
    central.writeUInt16LE(0, 14);          // mod date
    central.writeUInt32LE(crc, 16);        // crc-32
    central.writeUInt32LE(compressedSize, 20);
    central.writeUInt32LE(uncompressedSize, 24);
    central.writeUInt16LE(nameBytes.length, 28);
    central.writeUInt16LE(0, 30);          // extra field length
    central.writeUInt16LE(0, 32);          // comment length
    central.writeUInt16LE(0, 34);          // disk number start
    central.writeUInt16LE(0, 36);          // internal attrs
    central.writeUInt32LE(0, 38);          // external attrs
    central.writeUInt32LE(offset, 42);     // local header offset
    nameBytes.copy(central, 46);

    localHeaders.push(local);
    centralEntries.push(central);
    offset += local.length;
  }

  const centralDirOffset = offset;
  const centralDirSize = centralEntries.reduce((s, e) => s + e.length, 0);

  // End of central directory record (22 bytes)
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054B50, 0);       // signature
  eocd.writeUInt16LE(0, 4);                // disk number
  eocd.writeUInt16LE(0, 6);                // disk with central dir
  eocd.writeUInt16LE(entries.length, 8);   // entries on this disk
  eocd.writeUInt16LE(entries.length, 10);  // total entries
  eocd.writeUInt32LE(centralDirSize, 12);
  eocd.writeUInt32LE(centralDirOffset, 16);
  eocd.writeUInt16LE(0, 20);               // comment length

  return Buffer.concat([...localHeaders, ...centralEntries, eocd]);
}

/**
 * Re-package an existing EPUB (ZIP) file using our createZip.
 * Reads all entries from the source ZIP, decompresses any deflated entries,
 * and re-creates the ZIP with our implementation.
 * The mimetype entry is stored uncompressed; all others are deflated.
 *
 * @param {Buffer} zipData - Raw ZIP file bytes
 * @returns {Buffer} Re-packaged ZIP file
 */
export function repackageEpub(zipData) {
  // Parse central directory from the end of the ZIP
  // Find EOCD signature (0x06054b50) scanning backwards
  let eocdOff = -1;
  for (let i = zipData.length - 22; i >= 0; i--) {
    if (zipData.readUInt32LE(i) === 0x06054B50) {
      eocdOff = i;
      break;
    }
  }
  if (eocdOff < 0) throw new Error('No EOCD found');

  const entryCount = zipData.readUInt16LE(eocdOff + 10);
  const cdSize = zipData.readUInt32LE(eocdOff + 12);
  const cdOffset = zipData.readUInt32LE(eocdOff + 16);

  const entries = [];
  let pos = cdOffset;
  for (let i = 0; i < entryCount; i++) {
    if (zipData.readUInt32LE(pos) !== 0x02014B50) throw new Error('Bad CD entry');
    const method = zipData.readUInt16LE(pos + 10);
    const crc = zipData.readUInt32LE(pos + 16);
    const csize = zipData.readUInt32LE(pos + 20);
    const usize = zipData.readUInt32LE(pos + 24);
    const nameLen = zipData.readUInt16LE(pos + 28);
    const extraLen = zipData.readUInt16LE(pos + 30);
    const commentLen = zipData.readUInt16LE(pos + 32);
    const localOff = zipData.readUInt32LE(pos + 42);
    const name = zipData.subarray(pos + 46, pos + 46 + nameLen).toString('utf-8');

    // Read data from local file header
    const localNameLen = zipData.readUInt16LE(localOff + 26);
    const localExtraLen = zipData.readUInt16LE(localOff + 28);
    const dataOff = localOff + 30 + localNameLen + localExtraLen;
    const compressedData = zipData.subarray(dataOff, dataOff + csize);

    let data;
    if (method === 0) {
      data = Buffer.from(compressedData); // stored — copy as-is
    } else if (method === 8) {
      data = inflateRawSync(compressedData); // deflated — decompress
    } else {
      throw new Error(`Unsupported compression method ${method}`);
    }

    // mimetype must be stored uncompressed per EPUB spec.
    // Images should be stored (uncompressed) to match original behavior —
    // Quire's try_set_image only handles stored images (compression=0).
    const isImage = /\.(jpg|jpeg|png|gif|svg)$/i.test(name);
    const shouldStore = name === 'mimetype' || (method === 0 && isImage);
    entries.push({ name, data, store: shouldStore });
    pos += 46 + nameLen + extraLen + commentLen;
  }

  return createZip(entries);
}

/**
 * Generate a paragraph of filler text for multi-page content.
 */
function loremParagraph(seed) {
  const paragraphs = [
    'The morning sun cast long shadows across the ancient courtyard, where ivy crept along weathered stone walls that had stood for centuries. Birds sang from the tall oaks that lined the garden path, their melodies weaving through the cool autumn air. A gentle breeze carried the scent of fallen leaves and distant rain.',
    'In the library, rows upon rows of leather-bound volumes stretched from floor to ceiling, their spines gilded with titles in languages both familiar and forgotten. The reading lamps cast pools of warm light across the polished oak tables where scholars bent over manuscripts, their pens scratching softly against parchment.',
    'The village market bustled with activity as merchants called out their wares from colorful stalls draped in embroidered cloth. Fresh bread, ripe fruit, and fragrant spices filled the air with an intoxicating blend of aromas. Children darted between the crowds, laughing and chasing after each other.',
    'Beyond the harbor, the sea stretched endlessly toward the horizon, its surface shifting between shades of deep blue and emerald green. Fishing boats bobbed gently at their moorings, their hulls painted in bright primary colors that reflected in the rippling water below.',
    'The mountain path wound upward through dense forest, where ancient trees formed a canopy so thick that only scattered beams of sunlight penetrated to the mossy ground below. Each step revealed new wonders: delicate wildflowers, chattering squirrels, and the distant sound of a waterfall.',
    'As twilight descended, the city transformed into a tapestry of light. Street lamps flickered to life along cobblestone lanes, and windows glowed with the warm amber of candlelight. The evening air carried the sound of distant music, laughter from open doorways, and the gentle hum of conversation.',
    'The old clockmaker worked with meticulous precision, his magnifying glass revealing the intricate dance of gears and springs within the antique timepiece. Each component had been crafted by hand generations ago, and he treated every one with the reverence it deserved.',
    'Rain drummed steadily against the windowpanes as the storm rolled across the valley. Lightning illuminated the landscape in brief, brilliant flashes, revealing the swollen river that rushed between the banks. Thunder echoed off the surrounding hills like the voice of the mountain itself.',
  ];
  return paragraphs[seed % paragraphs.length];
}

/**
 * Create a minimal EPUB file with the given options.
 *
 * @param {object} opts
 * @param {string} opts.title - Book title
 * @param {string} opts.author - Book author
 * @param {number} opts.chapters - Number of chapters (default 3)
 * @param {number} opts.paragraphsPerChapter - Paragraphs per chapter (default 12)
 * @returns {Buffer} EPUB file contents
 */
// Minimal 1x1 red PNG (68 bytes) for testing image rendering
export const TINY_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8D4HwAFBQIAX8jx0gAAAABJRU5ErkJggg==',
  'base64'
);

export function createEpub(opts = {}) {
  const title = opts.title || 'Test Book';
  const author = opts.author || 'Test Author';
  const numChapters = opts.chapters || 3;
  const parasPerChapter = opts.paragraphsPerChapter || 12;
  const coverImage = opts.coverImage || false;
  const svgCover = opts.svgCover || false;
  const rawChapters = opts.rawChapters || null; // array of {body, images?}

  // mimetype must be first entry, stored uncompressed
  const mimetype = 'application/epub+zip';

  // container.xml
  const containerXml = `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>`;

  // Build manifest and spine items
  let manifestItems = '';
  let spineItems = '';
  const chapters = [];

  // SVG cover wrap page (like real-world EPUBs that use <svg><image> for covers)
  if (svgCover) {
    manifestItems += `    <item id="coverpage-wrapper" href="wrap0000.xhtml" media-type="application/xhtml+xml" properties="svg"/>\n`;
    manifestItems += `    <item id="cover-img" href="images/cover.png" media-type="image/png" properties="cover-image"/>\n`;
    spineItems += `    <itemref idref="coverpage-wrapper"/>\n`;
  }

  const effectiveChapters = rawChapters ? rawChapters.length : numChapters;
  for (let i = 1; i <= effectiveChapters; i++) {
    manifestItems += `    <item id="ch${i}" href="chapter${i}.xhtml" media-type="application/xhtml+xml"/>\n`;
    spineItems += `    <itemref idref="ch${i}"/>\n`;

    let xhtml;
    if (rawChapters && rawChapters[i - 1]) {
      // Use raw body content provided by the caller
      const rawBody = rawChapters[i - 1].body;
      xhtml = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter ${i}</title></head>
<body>
${rawBody}
</body>
</html>`;
    } else {
      // Generate chapter XHTML with enough text to fill multiple pages
      let body = '';
      if (coverImage && i === 1) {
        body += `<img src="images/cover.png" alt="Cover" />\n`;
      }
      body += `<h1>Chapter ${i}</h1>\n`;
      for (let p = 0; p < parasPerChapter; p++) {
        body += `      <p>${loremParagraph(i * 100 + p)}</p>\n`;
      }
      xhtml = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter ${i}</title></head>
<body>
      ${body}
</body>
</html>`;
    }
    chapters.push({ name: `OEBPS/chapter${i}.xhtml`, data: xhtml });
  }

  // Add cover image if requested (EPUB3: properties="cover-image")
  if (coverImage) {
    manifestItems += `    <item id="cover-img" href="images/cover.png" media-type="image/png" properties="cover-image"/>\n`;
  }

  // Build TOC nav document
  let tocItems = '';
  for (let i = 1; i <= numChapters; i++) {
    tocItems += `        <li><a href="chapter${i}.xhtml">Chapter ${i}</a></li>\n`;
  }

  const navXhtml = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Table of Contents</title></head>
<body>
  <nav epub:type="toc">
    <ol>
${tocItems}    </ol>
  </nav>
</body>
</html>`;

  manifestItems += `    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\n`;

  // content.opf
  const contentOpf = `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>${title}</dc:title>
    <dc:creator>${author}</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="uid">urn:uuid:${crypto.randomUUID()}</dc:identifier>
  </metadata>
  <manifest>
${manifestItems}  </manifest>
  <spine>
${spineItems}  </spine>
</package>`;

  // Assemble ZIP entries
  // mimetype MUST be first and stored (EPUB spec)
  // container.xml and content.opf are stored here for simplicity (deflated also works)
  const zipEntries = [
    { name: 'mimetype', data: mimetype, store: true },
    { name: 'META-INF/container.xml', data: containerXml, store: true },
    { name: 'OEBPS/content.opf', data: contentOpf, store: true },
    { name: 'OEBPS/nav.xhtml', data: navXhtml },
  ];

  // SVG cover wrap page (emulates real-world pattern: <svg><image xlink:href="...">)
  if (svgCover) {
    const wrapXhtml = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Cover</title></head>
<body>
  <div>
    <svg xmlns="http://www.w3.org/2000/svg" height="100%" preserveAspectRatio="xMidYMid meet" version="1.1" viewBox="0 0 1 1" width="100%" xmlns:xlink="http://www.w3.org/1999/xlink">
      <image width="1" height="1" xlink:href="images/cover.png"/>
    </svg>
  </div>
</body>
</html>`;
    zipEntries.push({ name: 'OEBPS/wrap0000.xhtml', data: wrapXhtml });
    zipEntries.push({ name: 'OEBPS/images/cover.png', data: TINY_PNG, store: true });
  }

  // storeChapters: true → store chapters uncompressed (diagnostic: test sync path)
  if (opts.storeChapters) {
    chapters.forEach(ch => { ch.store = true; });
  }
  zipEntries.push(...chapters);

  // Add cover image as stored (uncompressed) entry for synchronous reading
  if (coverImage) {
    zipEntries.push({ name: 'OEBPS/images/cover.png', data: TINY_PNG, store: true });
  }

  // Add extra images (for rawChapters that reference images)
  if (opts.extraImages) {
    for (const img of opts.extraImages) {
      zipEntries.push({ name: `OEBPS/${img.name}`, data: img.data, store: true });
    }
  }

  return createZip(zipEntries);
}
