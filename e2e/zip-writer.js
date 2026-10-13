// A ZIP writer for the archives real tools make and create-epub.js does not
// (#433): data descriptors (general-purpose bit 3), names flagged UTF-8,
// extra fields, an archive comment, a local header that differs from the
// central directory's, ZIP64 records, duplicate names, directory entries,
// and a CRC that does not match. create-epub.js writes one shape of
// archive; a book made by it is read back by readZip and written again
// here with the quirk in it, so the book itself is the same one.

import { deflateRawSync, inflateRawSync } from 'node:zlib';

const crcTable = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    table[n] = c;
  }
  return table;
})();

export function crc32(buf) {
  let crc = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) crc = crcTable[(crc ^ buf[i]) & 0xFF] ^ (crc >>> 8);
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

/** The entries of a zip as create-epub.js writes it: [{name, data (inflated), store}] */
export function readZip(zip) {
  let end = zip.length - 22;
  while (end >= 0 && zip.readUInt32LE(end) !== 0x06054B50) end--;
  if (end < 0) throw new Error('no end record');
  const count = zip.readUInt16LE(end + 10);
  let pos = zip.readUInt32LE(end + 16);
  const entries = [];
  for (let i = 0; i < count; i++) {
    const method = zip.readUInt16LE(pos + 10);
    const compressed = zip.readUInt32LE(pos + 20);
    const nameLength = zip.readUInt16LE(pos + 28);
    const extraLength = zip.readUInt16LE(pos + 30);
    const commentLength = zip.readUInt16LE(pos + 32);
    const local = zip.readUInt32LE(pos + 42);
    const name = zip.subarray(pos + 46, pos + 46 + nameLength).toString('utf8');
    const start = local + 30 + zip.readUInt16LE(local + 26) + zip.readUInt16LE(local + 28);
    const raw = zip.subarray(start, start + compressed);
    entries.push({ name, data: method === 0 ? Buffer.from(raw) : inflateRawSync(raw), store: method === 0 });
    pos += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

/** A ZIP extra field: id, then its data */
export function extraField(id, data) {
  const field = Buffer.alloc(4 + data.length);
  field.writeUInt16LE(id, 0);
  field.writeUInt16LE(data.length, 2);
  data.copy(field, 4);
  return field;
}

/** The extended timestamp (Info-ZIP 0x5455): a modification time */
export const timestampExtra = () => {
  const data = Buffer.alloc(5);
  data[0] = 1;
  data.writeUInt32LE(1767225600, 1);
  return extraField(0x5455, data);
};

/** The Info-ZIP Unix extra (0x7875): version 1, a uid and a gid of 1000 */
export const unixExtra = () => {
  const data = Buffer.alloc(11);
  data[0] = 1; data[1] = 4; data.writeUInt32LE(1000, 2); data[6] = 4; data.writeUInt32LE(1000, 7);
  return extraField(0x7875, data);
};

/** A ZIP64 extra (0x0001) holding the two sizes, on a file whose 32-bit fields are right too */
export const zip64Extra = (uncompressed, compressed) => {
  const data = Buffer.alloc(16);
  data.writeBigUInt64LE(BigInt(uncompressed), 0);
  data.writeBigUInt64LE(BigInt(compressed), 8);
  return extraField(0x0001, data);
};

/**
 * Writes a zip. Each entry: { name, data, store?,
 *   descriptor? (bit 3: sizes and CRC after the data; 'bare' leaves out the descriptor's signature),
 *   utf8? (bit 11),
 *   localExtra?, centralExtra? (Buffers),
 *   localName? (the name in the local header, when it is not the central directory's),
 *   crc? (the CRC both headers say, when it is not the data's),
 *   directory? (a directory entry: no data),
 *   zip64? (sizes and offset in a ZIP64 extra of the central entry, the 32-bit fields 0xFFFFFFFF) }
 * Archive options: { comment?, zip64End? (a ZIP64 end record and its locator) }
 */
export function writeZip(entries, { comment = '', zip64End = false } = {}) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const entry of entries) {
    const nameBytes = Buffer.from(entry.name, 'utf8');
    const localName = entry.localName === undefined ? nameBytes : Buffer.from(entry.localName, 'utf8');
    const raw = entry.directory ? Buffer.alloc(0) : (typeof entry.data === 'string' ? Buffer.from(entry.data, 'utf8') : entry.data);
    const stored = entry.store || entry.directory;
    const body = stored ? raw : deflateRawSync(raw);
    const method = stored ? 0 : 8;
    const crc = entry.crc === undefined ? crc32(raw) : entry.crc;
    const flags = (entry.descriptor ? 8 : 0) | (entry.utf8 ? 0x800 : 0);
    const localExtra = entry.localExtra || Buffer.alloc(0);
    const centralExtra = Buffer.concat([entry.zip64 ? zip64Extra(raw.length, body.length) : Buffer.alloc(0), entry.centralExtra || Buffer.alloc(0)]);

    const header = Buffer.alloc(30);
    header.writeUInt32LE(0x04034B50, 0);
    header.writeUInt16LE(entry.zip64 ? 45 : 20, 4);
    header.writeUInt16LE(flags, 6);
    header.writeUInt16LE(method, 8);
    if (!entry.descriptor) {
      header.writeUInt32LE(crc, 14);
      header.writeUInt32LE(body.length, 18);
      header.writeUInt32LE(raw.length, 22);
    }
    header.writeUInt16LE(localName.length, 26);
    header.writeUInt16LE(localExtra.length, 28);
    let descriptor = Buffer.alloc(0);
    if (entry.descriptor) {
      const signed = entry.descriptor !== 'bare';
      descriptor = Buffer.alloc(signed ? 16 : 12);
      let at = 0;
      if (signed) { descriptor.writeUInt32LE(0x08074B50, 0); at = 4; }
      descriptor.writeUInt32LE(crc, at);
      descriptor.writeUInt32LE(body.length, at + 4);
      descriptor.writeUInt32LE(raw.length, at + 8);
    }
    const local = Buffer.concat([header, localName, localExtra, body, descriptor]);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014B50, 0);
    central.writeUInt16LE(entry.zip64 ? 45 : 20, 4);
    central.writeUInt16LE(entry.zip64 ? 45 : 20, 6);
    central.writeUInt16LE(flags, 8);
    central.writeUInt16LE(method, 10);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(entry.zip64 ? 0xFFFFFFFF : body.length, 20);
    central.writeUInt32LE(entry.zip64 ? 0xFFFFFFFF : raw.length, 24);
    central.writeUInt16LE(nameBytes.length, 28);
    central.writeUInt16LE(centralExtra.length, 30);
    central.writeUInt32LE(entry.directory ? 0x10 : 0, 38);
    central.writeUInt32LE(offset, 42);
    centrals.push(Buffer.concat([central, nameBytes, centralExtra]));
    locals.push(local);
    offset += local.length;
  }
  const centralBytes = Buffer.concat(centrals);
  const commentBytes = Buffer.from(comment, 'utf8');
  const tail = [];
  let count = entries.length;
  let sizeField = centralBytes.length;
  let offsetField = offset;
  if (zip64End) {
    const end64 = Buffer.alloc(56);
    end64.writeUInt32LE(0x06064B50, 0);
    end64.writeBigUInt64LE(44n, 4);
    end64.writeUInt16LE(45, 12);
    end64.writeUInt16LE(45, 14);
    end64.writeBigUInt64LE(BigInt(entries.length), 24);
    end64.writeBigUInt64LE(BigInt(entries.length), 32);
    end64.writeBigUInt64LE(BigInt(centralBytes.length), 40);
    end64.writeBigUInt64LE(BigInt(offset), 48);
    const locator = Buffer.alloc(20);
    locator.writeUInt32LE(0x07064B50, 0);
    locator.writeBigUInt64LE(BigInt(offset + centralBytes.length), 8);
    locator.writeUInt32LE(1, 16);
    tail.push(end64, locator);
    count = 0xFFFF; sizeField = 0xFFFFFFFF; offsetField = 0xFFFFFFFF;
  }
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054B50, 0);
  eocd.writeUInt16LE(count, 8);
  eocd.writeUInt16LE(count, 10);
  eocd.writeUInt32LE(sizeField, 12);
  eocd.writeUInt32LE(offsetField, 16);
  eocd.writeUInt16LE(commentBytes.length, 20);
  return Buffer.concat([...locals, centralBytes, ...tail, eocd, commentBytes]);
}
