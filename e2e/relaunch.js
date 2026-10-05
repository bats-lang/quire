/**
 * Quitting Quire and opening it again changes nothing (#302): the
 * shared helpers that hold it. `capture` takes the whole state a reader
 * could see or the app keeps, `relaunch` closes the app and opens it
 * again in the same browser context (its storage kept), and `sameState`
 * requires two captures to be identical.
 *
 * The clock is fixed for the test (`fixedClock`): the app counts time in
 * minutes, so with Date standing still no field that is meant to move
 * with the clock (when a book was opened, when the last sync was, the
 * stamps' minutes) moves, and no stored record needs to be normalized.
 * What is left to differ is a real change, but for what is not the app's
 * state, each left out for its reason:
 *   - the focus, and its ring (drawn after keys, not after a tap): an
 *     app just opened has none until the reader acts, and must draw
 *     none by itself;
 *   - the pointer's hover: the mouse is moved off every control first;
 *   - a moment's things (the reader's bars, its back button, the hint on
 *     turning pages), which go by themselves: waited out (`settled`);
 *   - the renderer's own noise: a pixel drawn up to 16 levels a channel
 *     apart (an edge's anti-aliasing) is not counted as changed.
 */

import { writeFileSync } from 'node:fs';
import { test, expect, onAndroid, androidInsets } from './fixtures.js';
import { indicator, librarySearch } from './helpers.js';

/** The time the tests' clock stands at */
export const FIXED_TIME = new Date('2026-06-01T10:00:00Z');

/** The context's clock fixed at FIXED_TIME (timers still run) */
export async function fixedClock(context) {
  await context.clock.setFixedTime(FIXED_TIME);
}

/** Every record the app keeps: localStorage, and each IndexedDB
    database's stores, each value as a hash of its bytes (a Blob's or an
    ArrayBuffer's, or its JSON) */
async function stored(page) {
  return page.evaluate(async () => {
    const hex = async bytes => {
      const digest = await crypto.subtle.digest('SHA-256', bytes);
      return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
    };
    const bytesOf = async value => {
      if (value instanceof Blob) return new Uint8Array(await value.arrayBuffer());
      if (value instanceof ArrayBuffer) return new Uint8Array(value);
      if (ArrayBuffer.isView(value)) return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
      return new TextEncoder().encode(JSON.stringify(value));
    };
    const keyName = key => {
      if (key instanceof ArrayBuffer || ArrayBuffer.isView(key)) {
        const bytes = key instanceof ArrayBuffer ? new Uint8Array(key) : new Uint8Array(key.buffer, key.byteOffset, key.byteLength);
        return [...bytes].map(b => (b >= 32 && b < 127 ? String.fromCharCode(b) : `\\x${b.toString(16).padStart(2, '0')}`)).join('');
      }
      return JSON.stringify(key);
    };
    const records = {};
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      records[`localStorage ${key}`] = localStorage.getItem(key);
    }
    for (const { name } of await indexedDB.databases()) {
      const db = await new Promise((resolve, reject) => {
        const request = indexedDB.open(name);
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
      for (const store of db.objectStoreNames) {
        const [keys, values] = await new Promise((resolve, reject) => {
          const tx = db.transaction(store, 'readonly');
          const keysRequest = tx.objectStore(store).getAllKeys();
          const valuesRequest = tx.objectStore(store).getAll();
          tx.oncomplete = () => resolve([keysRequest.result, valuesRequest.result]);
          tx.onerror = () => reject(tx.error);
        });
        for (let j = 0; j < keys.length; j++)
          // a small record as its bytes (a failure shows which changed),
          // a large one (a book's file) as their hash
          records[`${name}/${store} ${keyName(keys[j])}`] = await (async bytes => (bytes.length <= 4096
            ? [...bytes].map(b => b.toString(16).padStart(2, '0')).join('')
            : await hex(bytes)))(await bytesOf(values[j]));
      }
      db.close();
    }
    return records;
  });
}

/** Waits until every write the app has started has reached IndexedDB:
    a read-write transaction on a store completes only after every one
    created before it */
async function writesDone(page) {
  await page.evaluate(async () => {
    for (const { name } of await indexedDB.databases()) {
      await new Promise((resolve, reject) => {
        const request = indexedDB.open(name);
        request.onerror = () => reject(request.error);
        request.onsuccess = () => {
          const db = request.result;
          const stores = [...db.objectStoreNames];
          if (!stores.length) { db.close(); resolve(); return; }
          const tx = db.transaction(stores, 'readwrite');
          tx.oncomplete = () => { db.close(); resolve(); };
          tx.onerror = () => { db.close(); reject(tx.error); };
        };
      });
    }
  });
}

/** Waits until the app is still: what it keeps has not changed for
    a second and a half (every launch step, a sync included, has ended),
    and the reader's bars and its back button, which go by themselves,
    have gone */
export async function settled(page) {
  let last = null;
  let still = 0;
  const deadline = Date.now() + 30000;
  while (still < 3) {
    if (Date.now() > deadline) throw new Error('the app did not settle within 30 s');
    await page.waitForTimeout(500);
    await writesDone(page);
    const now = JSON.stringify(await stored(page));
    still = now === last ? still + 1 : 0;
    last = now;
  }
  // the bars hide 5 s after they are shown, the back button 10 s after a
  // jump: both are a moment's, not the app's state
  await expect(page.getByRole('toolbar', { name: 'Page controls' })).toBeHidden({ timeout: 15000 });
  await expect(page.getByRole('button', { name: '↩ Back' })).toBeHidden({ timeout: 15000 });
  // the hint on turning pages goes 8 s after the first book opens
  await expect(page.getByText('Swipe or tap the sides to turn the page')).toBeHidden({ timeout: 15000 });
}

/** How far each element shown is scrolled (the page, the library's
    list): one hidden (the page turn's copy, kept laid out but
    invisible) is no part of what the reader sees */
async function scrolled(page) {
  return page.evaluate(() => [...document.querySelectorAll('*')]
    .filter(e => (e.scrollTop || e.scrollLeft) && e.checkVisibility({ visibilityProperty: true }))
    .map(e => `${e.id || e.className || e.tagName} ${e.scrollLeft},${e.scrollTop}`));
}

/** The app's state, once it is still: the screen's pixels, what the
    page says to assistive technology (what is open, the book and its
    place, the library's view, every toast, dialog and banner), where
    each element is scrolled, and every stored record (not the focus:
    an app opened has none until the reader acts) */
export async function capture(page) {
  await settled(page);
  // the pointer away from every control: where the mouse last was is
  // not the app's state (a hover)
  await page.mouse.move(0, 0);
  // nor is the focus, nor its ring, which the browser draws after keys
  // and not after a tap: whether the app drew one by itself is kept,
  // and the focus let go
  const ringed = await page.evaluate(() => document.querySelector(':focus-visible') !== null);
  await page.evaluate(() => document.activeElement && document.activeElement.blur());
  const screen = await page.screenshot({ animations: 'disabled', caret: 'hide' });
  return {
    ringed,
    screen,
    page: await page.locator('body').ariaSnapshot(),
    scrolled: await scrolled(page),
    stored: await stored(page),
  };
}

/** Closes the app and opens it again in the same context, its storage
    kept: quit (put in the background, then closed, as the system closes
    an app it no longer shows), or killed (its process ended with no
    event at all). Returns the new page, once its first view is up */
export async function relaunch(page, how = 'quit') {
  const context = page.context();
  // the files the Android app keeps (fixtures.js's androidApp keeps them
  // in the page) outlast its process, as the app's files do
  const files = await page.evaluate(() => (window.__android ? [...window.__android.files.entries()] : []));
  if (how === 'quit') {
    await page.evaluate(() => {
      Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await writesDone(page);
    await page.close({ runBeforeUnload: true });
  } else {
    // the process ends with no event at all: the page's own handlers of
    // the events a close sends are kept from running (a capturing
    // listener on the window runs before them, and stops them)
    await page.evaluate(() => {
      for (const type of ['pagehide', 'visibilitychange', 'beforeunload', 'unload', 'freeze'])
        window.addEventListener(type, event => event.stopImmediatePropagation(), true);
    });
    await page.close();
  }
  const next = await context.newPage();
  if (onAndroid(test.info())) {
    await androidInsets(next);
    await next.addInitScript(kept => { if (window.__android) for (const [path, data] of kept) window.__android.files.set(path, data); }, files);
  }
  await next.goto('/');
  await expect(next.locator('#bats-root')).not.toBeEmpty();
  return next;
}

/** How many pixels of two screenshots differ, by more than LEVELS in
    any channel: the renderer draws the same page's edges (a rounded
    corner, a glyph) a level or a few apart from one page to another,
    which no reader sees and is no state of the app's. The screenshots
    are compared in page (no image library is needed) */
const LEVELS = 16;
async function pixelsChanged(page, before, after) {
  return page.evaluate(async ([first, second, levels]) => {
    const pixels = async base64 => {
      const bitmap = await createImageBitmap(await (await fetch(`data:image/png;base64,${base64}`)).blob());
      const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
      const context = canvas.getContext('2d');
      context.drawImage(bitmap, 0, 0);
      return context.getImageData(0, 0, bitmap.width, bitmap.height);
    };
    const [a, b] = [await pixels(first), await pixels(second)];
    if (a.width !== b.width || a.height !== b.height) return a.width * a.height;
    let changed = 0;
    for (let k = 0; k < a.data.length; k += 4)
      if (Math.abs(a.data[k] - b.data[k]) > levels || Math.abs(a.data[k + 1] - b.data[k + 1]) > levels
        || Math.abs(a.data[k + 2] - b.data[k + 2]) > levels) changed++;
    return changed;
  }, [before.screen.toString('base64'), after.screen.toString('base64'), LEVELS]);
}

/** The two captures are the same: each part compared on its own, so a
    failure says which differs (and, for stored records, which ones; for
    the screen, both screenshots are attached). page is any page open */
export async function sameState(page, before, after) {
  expect(after.page, 'what the page shows (its accessibility tree)').toBe(before.page);
  expect(after.scrolled, 'where each element is scrolled').toEqual(before.scrolled);
  const records = Object.keys({ ...before.stored, ...after.stored })
    .filter(key => before.stored[key] !== after.stored[key]).sort();
  expect(records.map(key => `${key}\n  before ${before.stored[key]}\n  after  ${after.stored[key]}`),
    'the stored records that changed').toEqual([]);
  expect(after.ringed && !before.ringed, 'a focus ring the app drew by itself as it opened').toBe(false);
  const changed = await pixelsChanged(page, before, after);
  if (changed) {
    for (const [name, taken] of [['before', before], ['after', after]]) {
      const path = test.info().outputPath(`screen-${name}.png`);
      writeFileSync(path, taken.screen);
      await test.info().attach(`screen ${name}`, { path, contentType: 'image/png' });
    }
  }
  expect(changed, 'the pixels of the screen that changed').toBe(0);
}

// ---- what the specs share ----

/** The app opened, its clock fixed (so nothing that counts minutes
    moves) */
export async function launch(context, page) {
  await fixedClock(context);
  await page.goto('/');
  await expect(librarySearch(page)).toBeVisible();
}

/** The chapter shown, by the number in its title ("Chapter 2 · page 3
    of 9 in chapter", or scrolled "Chapter 2 · 40% of chapter") */
export async function chapterShown(page) {
  const text = (await indicator(page).textContent()).trim();
  const number = /^Chapter (\d+)\s/.exec(text);
  expect(number, `page indicator "${text}"`).not.toBeNull();
  return +number[1];
}

/** The next chapter's first page (from the end of this one) */
export async function nextChapter(page) {
  const was = await chapterShown(page);
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(() => chapterShown(page)).toBe(was + 1);
}

/** The previous chapter's last page (from the start of this one) */
export async function previousChapter(page) {
  const was = await chapterShown(page);
  await page.keyboard.press('Home');
  await page.keyboard.press('ArrowLeft');
  await expect.poll(() => chapterShown(page)).toBe(was - 1);
}

/** A few pages on, to the middle of a chapter */
export async function pagesOn(page, count) {
  for (let i = 0; i < count; i++) {
    const before = JSON.stringify(await indicator(page).textContent());
    await page.keyboard.press('ArrowRight');
    await expect.poll(async () => JSON.stringify(await indicator(page).textContent())).not.toBe(before);
  }
}

/** Captured, relaunched (quit or killed), captured again: the same */
export async function unchanged(page, how = 'quit') {
  const before = await capture(page);
  const next = await relaunch(page, how);
  const after = await capture(next);
  await sameState(next, before, after);
  return next;
}
