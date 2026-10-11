// The steps the specs of replacing a book share (replace.spec.js and
// replace-corrected.spec.js, quire#425)

import { expect } from './fixtures.js';
import {
  importInput, importEnded, showChrome, toLibrary, dialog, menuItem, bookMenu, place, placeChanged, selectText, selectionButton, clickControl, bookPage,
} from './helpers.js';

export const panel = page => dialog(page, 'Annotations');
export const note = page => dialog(page, 'Note');

/** Turns n pages, a minute apart: the minutes read */
export async function readMinutes(page, n) {
  for (let k = 0; k < n; k++) {
    const before = await place(page);
    await page.clock.fastForward('01:00');
    await page.keyboard.press('ArrowRight');
    await placeChanged(page, before);
  }
}

/** Bookmarks the page shown. The bars hide 5 s after they were last
    shown, which a loaded machine can pass between one step and this: the
    bars are brought up and the click made again until it lands, as
    clickControl does for the bottom bar's buttons */
export async function bookmarkPage(page) {
  await expect(async () => {
    await showChrome(page);
    await page.getByRole('button', { name: 'Bookmark this page' }).click({ timeout: 2000 });
  }).toPass({ timeout: 20000 });
}

/** A highlight of the first words of the chapter shown, with a note */
export async function highlightWithNote(page, text) {
  await selectText(page, 0, 8);
  await selectionButton(page, 'Highlight').click();
  await clickControl(page, 'Annotations');
  await expect(panel(page)).toBeVisible();
  await panel(page).getByRole('button', { name: 'Add note' }).first().click();
  await note(page).getByRole('textbox', { name: 'Note' }).fill(text);
  await note(page).getByRole('button', { name: 'Save' }).click();
  await expect(panel(page)).toContainText(text);
  await panel(page).getByRole('button', { name: 'Close' }).click();
  await expect(panel(page)).toBeHidden();
}

/** Puts the open book in a collection of that name, made if it is new */
export async function inCollection(page, title, name) {
  await bookMenu(page, title);
  await menuItem(page, 'Collections').click();
  const collections = dialog(page, 'Collections');
  await collections.getByRole('button', { name: 'New collection' }).click();
  const field = dialog(page, 'New collection').getByRole('textbox', { name: 'Name' });
  await field.fill(name);
  await field.press('Enter');
  await expect(collections.getByRole('button', { name, exact: true })).toHaveAttribute('aria-pressed', 'true');
  await collections.getByRole('button', { name: 'Done' }).click();
  await expect(collections).toBeHidden();
}

/** The size in bytes of each book's file as the library keeps it (the
    entries "b<id>" of the app's store), by id */
export async function fileSizes(page) {
  return page.evaluate(async () => {
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open('bats');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const sizes = {};
    await new Promise((resolve, reject) => {
      const tx = db.transaction('kv', 'readonly');
      const cursor = tx.objectStore('kv').openCursor();
      cursor.onsuccess = () => {
        const at = cursor.result;
        if (!at) return;
        const key = typeof at.key === 'string' ? at.key : new TextDecoder().decode(at.key);
        if (/^b[0-9a-f]{14}$/.test(key)) {
          const v = at.value;
          sizes[key.slice(1)] = v.size ?? v.byteLength ?? v.length;
        }
        at.continue();
      };
      tx.oncomplete = resolve;
      tx.onerror = () => reject(tx.error);
    });
    db.close();
    return sizes;
  });
}

/** Imports file again and chooses Replace */
export async function replaceWith(page, file) {
  await importInput(page).setInputFiles([file]);
  const ask = dialog(page, 'Already in library');
  await ask.getByRole('button', { name: 'Replace' }).click();
  await expect(ask).toBeHidden();
  await importEnded(page);
}


/** Imports file, a corrected file of the book in the library, and
    answers the question "Newer file of a book?" with its button */
async function newerFile(page, file, button) {
  await importInput(page).setInputFiles([file]);
  const ask = dialog(page, 'Newer file of a book?');
  await expect(ask).toBeVisible();
  await expect(ask).toContainText('looks like a corrected version');
  await ask.getByRole('button', { name: button, exact: true }).click();
  await expect(ask).toBeHidden();
  await importEnded(page);
}

/** A corrected file of the book, imported as that book (Replace) */
export const replaceWithNewer = (page, file) => newerFile(page, file, 'Replace');

/** The same file, imported as a book of its own (Add as new book) */
export const addNewerAsNew = (page, file) => newerFile(page, file, 'Add as new book');

/** The bytes of the cover the library keeps for each book ('c<id>'), by id */
export async function coverBytes(page) {
  return page.evaluate(async () => {
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open('bats');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const values = {};
    await new Promise((resolve, reject) => {
      const tx = db.transaction('kv', 'readonly');
      const cursor = tx.objectStore('kv').openCursor();
      cursor.onsuccess = () => {
        const at = cursor.result;
        if (!at) return;
        const key = typeof at.key === 'string' ? at.key : new TextDecoder().decode(at.key);
        if (/^c[0-9a-f]{14}$/.test(key)) values[key.slice(1)] = at.value;
        at.continue();
      };
      tx.oncomplete = resolve;
      tx.onerror = () => reject(tx.error);
    });
    db.close();
    const bytes = {};
    for (const [id, value] of Object.entries(values)) {
      const buffer = value instanceof Blob ? await value.arrayBuffer()
        : value instanceof ArrayBuffer ? value
        : value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength);
      bytes[id] = Array.from(new Uint8Array(buffer));
    }
    return bytes;
  });
}

/** How many paragraphs begin on the page shown */
const beginning = page => bookPage(page).evaluate(doc => {
  const c = doc.getBoundingClientRect();
  return [...doc.querySelectorAll('p')].filter(e => {
    const r = e.getBoundingClientRect();
    return r.width > 0 && r.left >= c.left - 1 && r.left < c.right;
  }).length;
});

/** Selects from..to of the last paragraph that begins on the page shown
    (on a narrow page the last page of a chapter may have none: the page
    before it is taken then) */
export async function selectLastText(page, from, to) {
  for (let back = 0; back < 5 && (await beginning(page)) === 0; back++) {
    await page.keyboard.press('ArrowLeft');
    await page.waitForTimeout(400);
  }
  await bookPage(page).evaluate((doc, [from, to]) => {
    const c = doc.getBoundingClientRect();
    const starting = [...doc.querySelectorAll('p')].filter(e => {
      const r = e.getBoundingClientRect();
      return r.width > 0 && r.left >= c.left - 1 && r.left < c.right;
    });
    const el = starting[starting.length - 1];
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    const t = walker.nextNode();
    const r = document.createRange();
    r.setStart(t, from);
    r.setEnd(t, to);
    const s = getSelection();
    s.removeAllRanges();
    s.addRange(r);
  }, [from, to]);
}

/** A highlight of the first words of the last paragraph that begins on
    the page shown, with a note (the one list row that has none yet is
    its row) */
export async function highlightLastWithNote(page, text) {
  await selectLastText(page, 0, 8);
  await selectionButton(page, 'Highlight').click();
  await clickControl(page, 'Annotations');
  await expect(panel(page)).toBeVisible();
  await panel(page).getByRole('button', { name: 'Add note' }).first().click();
  await note(page).getByRole('textbox', { name: 'Note' }).fill(text);
  await note(page).getByRole('button', { name: 'Save' }).click();
  await expect(panel(page)).toContainText(text);
  await panel(page).getByRole('button', { name: 'Close' }).click();
  await expect(panel(page)).toBeHidden();
}
