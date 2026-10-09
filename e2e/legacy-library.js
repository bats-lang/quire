// The old whole-library record "lib" (QLB1 to QLB6) and the store it is in,
// as the specs that convert it need them (library-records.spec.js,
// stability.spec.js).


/* ---------------- the old record, as each version of it wrote it ---------------- */

const int32 = n => { const b = new Uint8Array(4); new DataView(b.buffer).setInt32(0, n, true); return [...b]; };
const text = s => { const e = new TextEncoder().encode(s); return [e.length, ...e]; };

/** The bytes "lib" held at version 1 to 6: collections (from version 3) and books */
export function legacyLibrary(version, collections, books) {
  const out = [...'QLB'].map(c => c.charCodeAt(0));
  out.push(48 + version);
  if (version >= 3) {
    out.push(collections.length);
    for (const name of collections) out.push(...text(name));
  }
  for (const b of books) {
    out.push(...int32(b.idHigh), ...int32(b.idLow), ...text(b.title), ...text(b.author));
    out.push(...int32(b.shelf ?? 0), ...int32(b.added ?? 100), ...int32(b.opened ?? 0), ...int32(b.chapter ?? 0),
      ...int32(b.chapters ?? 0), ...int32(b.page ?? 0), ...int32(b.pages ?? 0), ...int32(b.anchor ?? -1),
      ...int32(b.size ?? 1000), ...int32((b.cover ?? 0) + (b.done ? 256 : 0)));
    if (version >= 2) out.push(...text(b.series ?? ''), ...int32(b.number ?? 0));
    if (version >= 3) out.push(...int32(b.collections ?? 0));
    if (version >= 4) out.push(...int32(b.minutes ?? 0), ...int32(b.pagesRead ?? 0), ...int32(b.finished ?? 0));
    if (version >= 5) out.push(...int32(b.shelfModified ?? 0), ...int32(b.collectionsModified ?? 0),
      ...int32(b.finishedModified ?? 0), ...int32(b.minutesElsewhere ?? 0), ...int32(b.pagesElsewhere ?? 0));
    if (version >= 6) out.push(...int32(b.placeModified ?? 0), ...int32(b.placeDeclined ?? 0));
  }
  return Uint8Array.from(out);
}

export const hex7 = n => n.toString(16).padStart(7, '0');
export const bookKey = b => `library/book/${hex7(b.idHigh)}${hex7(b.idLow)}`;

/* ---------------- the store, seen from the page ---------------- */

/** Every key of the store with its bytes as numbers */
export async function store(page) {
  return page.evaluate(async () => {
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open('bats');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const [keys, values] = await new Promise((resolve, reject) => {
      const tx = db.transaction('kv', 'readonly');
      const keysRequest = tx.objectStore('kv').getAllKeys();
      const valuesRequest = tx.objectStore('kv').getAll();
      tx.oncomplete = () => resolve([keysRequest.result, valuesRequest.result]);
      tx.onerror = () => reject(tx.error);
    });
    db.close();
    const records = {};
    keys.forEach((key, i) => {
      const value = values[i];
      const bytes = value instanceof ArrayBuffer ? new Uint8Array(value) : new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
      records[key] = [...bytes];
    });
    return records;
  });
}

/** Puts bytes under key (null: deletes the key) */
export async function put(page, key, bytes) {
  await page.evaluate(async ({ key, bytes }) => {
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open('bats');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    await new Promise((resolve, reject) => {
      const tx = db.transaction('kv', 'readwrite');
      if (bytes === null) tx.objectStore('kv').delete(key);
      else tx.objectStore('kv').put(Uint8Array.from(bytes), key);
      tx.oncomplete = resolve;
      tx.onerror = () => reject(tx.error);
    });
    db.close();
  }, { key, bytes });
}

/** Removes every record of the library (as before it was converted) */
export async function forgetRecords(page) {
  for (const key of Object.keys(await store(page))) if (key.startsWith('library/')) await put(page, key, null);
}

