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
 *   - a moment's things (the reader's back button), which goes by itself: run
 *     out on the fake clock (`settled`, #657); reader acts: `settled` takes the bars and hint away;
 *   - the renderer's own noise: a pixel drawn up to 16 levels a channel
 *     apart (an edge's anti-aliasing) is not counted as changed.
 */

import { writeFileSync } from 'node:fs';
import { test, expect, onAndroid, androidInsets } from './fixtures.js';
import { indicator, librarySearch, libraryShown, rawMouse, bareReader } from './helpers.js';

/** The time the tests' clock stands at */
export const FIXED_TIME = new Date('2026-06-01T10:00:00Z');

/** The context's clock fixed at FIXED_TIME: Date stands still, the
    timers run (in real time, and `settled` runs them ahead) */
export async function fixedClock(context) {
  await context.clock.setFixedTime(FIXED_TIME);
}

/** Every record the app keeps: localStorage, and each IndexedDB
    database's stores, each value as a hash of its bytes (a Blob's or an
    ArrayBuffer's, or its JSON) */
export async function stored(page) {
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
export async function writesDone(page) {
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

/** The time the app is given to rest in `rested`: more than its longest
    debounce (a scroll's 150 ms, a resize's 200 ms) and its `_settle`
    re-counts (250 ms, 12 times) that a place waits for */
const REST_MS = 1500;

/** Lets the app rest: the fake clock (installed before the page opened,
    as `fixedClock` and `page.clock.install()` do) runs REST_MS ahead, so
    every debounce and re-count the app has pending fires in order, and
    then every write they started has reached IndexedDB (#657). It
    replaces `waitForTimeout(1500)`, which waited the same time in real
    time and wrote nothing down */
export async function rested(page) {
  await page.clock.runFor(REST_MS);
  await writesDone(page);
}

/** Longer than the longest moment (the back button's 10 s) */
const MOMENT_MS = 15000;

/** Waits until the app is still: what it keeps has not changed for
    a second and a half (every launch step, a sync included, has ended),
    and the reader's bars and hint are down and its back button, which goes
    by itself, has gone */
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
  // the back button goes 10 s after a jump (BACK_SHOWN): a moment's, not the
  // app's state. Under a fake clock installed before the page opened
  // (`fixedClock` does, so does `page.clock.install()`) the moment is run,
  // not waited out (#657): `runFor` fires every timer due in it in order,
  // those a timer sets in turn too, and leaves the network and IndexedDB,
  // which are not the clock's, alone
  if (await page.evaluate(() => globalThis.__pwClock !== undefined)) {
    await page.clock.runFor(MOMENT_MS);
    await writesDone(page);
  }
  // reader acts: the bars and the hint are taken away
  await bareReader(page);
  // whichever way it passed, the assertions are the same
  await expect(page.getByRole('button', { name: '↩ Back' })).toBeHidden({ timeout: 15000 });
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
    each element is scrolled, every stored record, and in the Android
    app which system bars are hidden (full screen, #313; drawn by the
    system, not in the page's pixels) and whether the Full screen switch
    is on (not the focus: an app opened has none until the reader acts) */
export async function capture(page) {
  await settled(page);
  // the pointer away from every control: where the mouse last was is
  // not the app's state (a hover)
  await rawMouse(page, 'move', 0, 0);
  // nor is the focus, nor its ring, which the browser draws after keys
  // and not after a tap: whether the app drew one by itself is kept,
  // and the focus let go
  const ringed = await page.evaluate(() => document.querySelector(':focus-visible') !== null);
  await page.evaluate(() => document.activeElement && document.activeElement.blur());
  const screen = await page.screenshot({ animations: 'disabled', caret: 'hide' });
  await strayForensics(page, screen);
  return {
    bars: await page.evaluate(() => (window.__android ? window.__android.hidden : null)),
    fullScreen: await page.evaluate(() => document.getElementById('screen-fullscreen')?.getAttribute('aria-pressed') ?? null),
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

/**
 * Where two screenshots differ, and what the page has at each place (#546: two isolated pixels differed after a relaunch, and a
 * count says nothing of where): the first 50 differing pixels with both colours, and the elements and text at each. Keyword: pixel diff.
 */
export async function pixelDiff(page, before, after) {
  const points = await page.evaluate(async ([first, second, levels]) => {
    const pixels = async base64 => {
      const bitmap = await createImageBitmap(await (await fetch(`data:image/png;base64,${base64}`)).blob());
      const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
      const context = canvas.getContext('2d');
      context.drawImage(bitmap, 0, 0);
      return context.getImageData(0, 0, bitmap.width, bitmap.height);
    };
    const [a, b] = [await pixels(first), await pixels(second)];
    if (a.width !== b.width || a.height !== b.height) return { sizes: [[a.width, a.height], [b.width, b.height]], list: [], count: a.width * a.height };
    const list = [];
    let count = 0;
    for (let k = 0; k < a.data.length; k += 4) {
      if (Math.abs(a.data[k] - b.data[k]) > levels || Math.abs(a.data[k + 1] - b.data[k + 1]) > levels || Math.abs(a.data[k + 2] - b.data[k + 2]) > levels) {
        count++;
        if (list.length < 50) { const at = k / 4; list.push({ x: at % a.width, y: Math.floor(at / a.width), before: Array.from(a.data.slice(k, k + 3)), after: Array.from(b.data.slice(k, k + 3)) }); }
      }
    }
    return { list, count };
  }, [before.screen.toString('base64'), after.screen.toString('base64'), LEVELS]);
  if (points.list) {
    // the page's pixels are device pixels; the elements are asked at CSS pixels
    points.dom = await page.evaluate(list => list.slice(0, 10).map(({ x, y }) => {
      const scale = window.devicePixelRatio || 1;
      const css = [x / scale, y / scale];
      return { at: [x, y], stack: document.elementsFromPoint(css[0], css[1]).map(e => `${e.tagName.toLowerCase()}#${e.id}.${e.className}`).slice(0, 6) };
    }), points.list).catch(() => 'the page did not answer');
  }
  return points;
}

/** The two captures are the same: each part compared on its own, so a
    failure says which differs (and, for stored records, which ones; for
    the screen, both screenshots are attached). page is any page open */
export async function sameState(page, before, after) {
  expect(after.page, 'what the page shows (its accessibility tree)').toBe(before.page);
  expect(after.scrolled, 'where each element is scrolled').toEqual(before.scrolled);
  expect(after.bars, 'the system bars hidden (the Android app)').toEqual(before.bars);
  expect(after.fullScreen, 'the Full screen switch').toBe(before.fullScreen);
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
    // where they differ and what the page has there, so a stray pixel is a place and an element, not a count
    await test.info().attach('pixel-diff', { body: JSON.stringify(await pixelDiff(page, before, after), null, 1), contentType: 'application/json' });
  }
  expect(changed, 'the pixels of the screen that changed').toBe(0);
}

// ---- what the specs share ----

/** The app opened, its clock fixed (so nothing that counts minutes
    moves) */
export async function launch(context, page) {
  await fixedClock(context);
  await page.goto('/');
  await expect(libraryShown(page)).toBeVisible();
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

// ---- #546 forensics (temporary): what a stray pixel right of the text column is ----

/** The pixels right of the text column that are not the page's ground */
async function strayPixels(page, shot) {
  return page.evaluate(async base64 => {
    const img = new Image();
    img.src = `data:image/png;base64,${base64}`;
    await img.decode();
    const canvas = document.createElement('canvas');
    canvas.width = img.width;
    canvas.height = img.height;
    const drawn = canvas.getContext('2d');
    drawn.drawImage(img, 0, 0);
    const data = drawn.getImageData(0, 0, canvas.width, canvas.height).data;
    const ground = data.slice((400 * canvas.width + 5) * 4, (400 * canvas.width + 5) * 4 + 3);
    const out = [];
    for (let y = 60; y < canvas.height - 40; y++) for (let x = 800; x < Math.min(1000, canvas.width); x++) {
      const i = (y * canvas.width + x) * 4;
      if (data[i] !== ground[0] || data[i + 1] !== ground[1] || data[i + 2] !== ground[2]) out.push(`${x},${y}:${data[i]}.${data[i + 1]}.${data[i + 2]}`);
    }
    return out;
  }, shot.toString('base64'));
}

/** When the screen has a stray pixel, say what clears it: a second screenshot, a nudge of the page's scroll, the page-turn copy taken out */
async function strayForensics(page, screen) {
  const found = await strayPixels(page, screen);
  // a few pixels are a stray; a screen with content there (a bar, a list) has hundreds
  if (found.length === 0 || found.length > 12) return;
  const info = test.info();
  const report = { first: found };
  await info.attach('stray-first.png', { body: screen, contentType: 'image/png' });
  const again = await page.screenshot({ animations: 'disabled', caret: 'hide' });
  report.again = await strayPixels(page, again);
  await page.evaluate(() => { document.getElementById('page-turn').style.display = 'none'; });
  await page.waitForTimeout(300);
  const without = await page.screenshot({ animations: 'disabled', caret: 'hide' });
  report.turnRemoved = await strayPixels(page, without);
  await info.attach('stray-turn-removed.png', { body: without, contentType: 'image/png' });
  await page.evaluate(() => { document.getElementById('page-turn').style.display = ''; });
  // what the DOM has there: any element or text whose box reaches the pixel
  report.dom = await page.evaluate(points => points.map(([x, y]) => ({
    at: [x, y],
    stack: document.elementsFromPoint(x, y).map(e => `${e.tagName.toLowerCase()}#${e.id}.${e.className}`).slice(0, 6),
    text: (() => { const hits = []; const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      for (let n = walker.nextNode(); n && hits.length < 3; n = walker.nextNode()) {
        const range = document.createRange(); range.selectNodeContents(n);
        for (const r of range.getClientRects()) if (r.left - 2 <= x && x <= r.right + 2 && r.top - 2 <= y && y <= r.bottom + 2) { hits.push(`${n.data.slice(0, 20)}@${r.left | 0},${r.top | 0},${r.right | 0},${r.bottom | 0}`); break; }
      } return hits; })(),
  })), found.slice(0, 4).map(p => p.split(':')[0].split(',').map(Number)));
  // a real invalidation: the page scrolled away and back with a frame painted at each
  const frames = () => page.evaluate(() => new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done))));
  await page.evaluate(() => { for (const caf of document.querySelectorAll('.caf')) caf.scrollTop += 40; });
  await frames();
  await page.evaluate(() => { for (const caf of document.querySelectorAll('.caf')) caf.scrollTop -= 40; });
  await frames();
  const nudged = await page.screenshot({ animations: 'disabled', caret: 'hide' });
  report.nudged = await strayPixels(page, nudged);
  await info.attach('stray-nudged.png', { body: nudged, contentType: 'image/png' });
  // a whole repaint: the page hidden for a painted frame
  await page.evaluate(() => { for (const caf of document.querySelectorAll('.caf')) caf.style.visibility = 'hidden'; });
  await frames();
  await page.evaluate(() => { for (const caf of document.querySelectorAll('.caf')) caf.style.visibility = ''; });
  await frames();
  report.repainted = await strayPixels(page, await page.screenshot({ animations: 'disabled', caret: 'hide' }));
  await info.attach('stray-report.json', { body: JSON.stringify(report, null, 1), contentType: 'application/json' });
  console.log('STRAY546', JSON.stringify(report));
}
