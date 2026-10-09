// Shared steps for the e2e tests: books made on the fly, imported
// through the file input, opened from their cards, and the reader's
// place read back from the page.
//
// Everything is found as a reader finds it: by role, accessible name,
// label or visible text. No test depends on an element's id or class.

import { expect } from '@playwright/test';
import { createEpub, solidPng } from './create-epub.js';
import { writeFileSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const dir = mkdtempSync(join(tmpdir(), 'quire-e2e-'));
let count = 0;

/** An EPUB made from opts (see create-epub.js), written to a file */
export function epubFile(opts = {}) {
  const path = join(dir, `book-${process.pid}-${count++}.epub`);
  writeFileSync(path, createEpub({ storeChapters: true, ...opts }));
  return path;
}

/** Any bytes, written to a file named name */
export function rawFile(name, data) {
  const path = join(dir, `${count++}-${name}`);
  writeFileSync(path, data);
  return path;
}

/** Chapter i's body: a heading and n paragraphs long enough to fill
    several pages, each starting with a findable tag */
export function chapterBody(i, n = 20, tag = 'Para') {
  let body = `<h1>Part ${i}</h1>`;
  for (let k = 0; k < n; k++) {
    body += `<p>${tag} ${i}.${k} ` + 'lorem ipsum dolor sit amet '.repeat(12) + '</p>';
  }
  return body;
}

/** Chapters 1..n made by chapterBody */
export function chapters(n, paras = 20, tag = 'Para') {
  return Array.from({ length: n }, (_, k) => ({ body: chapterBody(k + 1, paras, tag) }));
}

/** Chapter i's body in Japanese: a heading and n paragraphs long
    enough to fill several pages set vertically, each starting with a
    findable tag (段落 i.k) */
export function japaneseChapterBody(i, n = 20) {
  let body = `<h1>第${i}章</h1>`;
  for (let k = 0; k < n; k++) {
    body += `<p>段落 ${i}.${k} ` + '吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。'.repeat(6) + '</p>';
  }
  return body;
}

/** Chapters 1..n made by japaneseChapterBody */
export function japaneseChapters(n, paras = 20) {
  return Array.from({ length: n }, (_, k) => ({ body: japaneseChapterBody(k + 1, paras) }));
}

/** A book with the print edition's pages (a page-list): chapters 1 and 2
    each hold three page breaks, the first before their first paragraph
    (pages 1-3 and 4-6), and chapter 3 has none */
export function pagedBook(title, author) {
  const para = (i, k) => `<p>Para ${i}.${k} ` + 'lorem ipsum dolor sit amet '.repeat(12) + '</p>';
  const body = (i, breaks) => Array.from({ length: 30 }, (_, k) =>
    (breaks && k % 10 === 0 ? `<span epub:type="pagebreak" id="pg${i}-${k / 10}" title="${(i - 1) * 3 + k / 10 + 1}"/>` : '') + para(i, k)).join('');
  const pageList = [];
  for (let i = 1; i <= 2; i++) for (let j = 0; j < 3; j++) pageList.push({ label: String((i - 1) * 3 + j + 1), href: `chapter${i}.xhtml#pg${i}-${j}` });
  return { title, author, rawChapters: [{ body: body(1, true) }, { body: body(2, true) }, { body: body(3, false) }], pageList };
}

// ---- the library ----

/** The input that imports EPUB files */
export const importInput = page => page.getByLabel('Import EPUB');

/** The list of books */
export const books = page => page.getByRole('region', { name: 'Books' });

/** The book to continue, above the list (and then not in it, #273) */
export const continueReading = page => page.getByRole('region', { name: 'Continue reading' });

/** Every book's row the library shows, in order: the book to continue,
    then the list; each a group named by the book's title, holding its
    card and its "Book menu" button */
export const cards = page => page.getByRole('region', { name: /^(Continue reading|Books)$/ }).getByRole('group');

/** The row of the book whose card has text */
export function card(page, text) {
  return cards(page).filter({ hasText: text });
}

/** The cards' titles, in the order shown (a card's first line) */
export async function titles(page) {
  return (await cards(page).allInnerTexts()).map(t => t.split('\n')[0].trim());
}

/** The library's search box, whose presence says the library is shown */
export const librarySearch = page => page.getByRole('searchbox', { name: 'Search the library' });

/** A dialog by its name (the modal dialog is named by its title) */
export const dialog = (page, name) => page.getByRole('dialog', { name });

/** A menu item by its name */
export const menuItem = (page, name) => page.getByRole('menuitem', { name, exact: true });

/** Reloads the app once every write it has started has reached
    IndexedDB. The app saves asynchronously, so a reload straight after a
    change could come before the write commits. A read-write transaction
    on the same store completes only after every one created before it,
    so waiting for one here waits for all of the app's writes so far. */
export async function reload(page) {
  await page.evaluate(async () => {
    // opening a database that does not exist would create it empty
    if (!(await indexedDB.databases()).some(d => d.name === 'bats')) return;
    await new Promise((resolve, reject) => {
      const r = indexedDB.open('bats');
      r.onerror = () => reject(r.error);
      r.onsuccess = () => {
        const db = r.result;
        if (!db.objectStoreNames.contains('kv')) { db.close(); resolve(); return; }
        const tx = db.transaction('kv', 'readwrite');
        tx.oncomplete = () => { db.close(); resolve(); };
        tx.onerror = () => { db.close(); reject(tx.error); };
      };
    });
  });
  await page.reload();
}

/** Opens the library menu (the bar's More options) */
export async function libraryMenu(page) {
  await page.getByRole('button', { name: 'More options' }).click();
  await expect(page.getByRole('menu')).toBeVisible();
}

/** The Settings screen (sync, dictionaries, backup, the reading goal and
    the resets) */
export const settingsScreen = page => page.getByRole('dialog', { name: 'Settings', exact: true });

/** A button of the Settings screen, by its name */
export const settingsButton = (page, name) => settingsScreen(page).getByRole('button', { name, exact: true });

/** Opens the Settings screen from the library menu */
export async function librarySettings(page) {
  await libraryMenu(page);
  await menuItem(page, 'Settings').click();
  await expect(settingsScreen(page)).toBeVisible();
}

/** The Settings screen's input that restores a backup */
export const restoreInput = page => page.getByLabel('Restore backup');

/** Opens the book menu of the card with text, with its visible button */
export async function bookMenu(page, text) {
  await card(page, text).getByRole('button', { name: 'Book menu' }).click();
  await expect(page.getByRole('menu', { name: 'Book menu' })).toBeVisible();
}

/** Opens the app on an empty library; returns the page's errors (a
    list that fills as they happen) */
export async function start(page) {
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  await page.goto('/');
  await expect(librarySearch(page)).toBeVisible();
  return errors;
}

/** Imports the files through the import button's input, and waits
    until the library shows total cards */
export async function importFiles(page, files, total) {
  await importInput(page).setInputFiles(files);
  await expect(cards(page)).toHaveCount(total, { timeout: 30000 });
}

// ---- the reader ----

/** The page of the book shown */
export const bookPage = page => page.getByRole('document', { name: 'Page' });

/** The page indicator (read even while the bars are hidden) */
export const indicator = page => page.getByRole('status', { name: 'Page', includeHidden: true });

/** The reader's top bar */
export const topBar = page => page.getByRole('navigation', { name: 'Book' });

/** The chapter's title in the top bar */
export const chapterTitle = page => topBar(page).getByRole('heading');

/** A button of the reader's bottom bar, by name */
export const control = (page, name) =>
  page.getByRole('toolbar', { name: 'Page controls' }).getByRole('button', { name, exact: true });

/** The button that goes back after a jump */
export const jumpBack = page => page.getByRole('button', { name: '↩ Back' });

/** Opens the book whose card has text, and waits for its first page */
export async function openBook(page, text) {
  await card(page, text).click();
  await pageShown(page);
}

/** Waits until the book just opened shows its page: the reader is up
    before its chapter is loaded, and a key pressed until then turns
    nothing */
export async function pageShown(page) {
  await expect(bookPage(page)).toBeVisible();
  await expect(indicator(page)).toContainText('in chapter');
}

/** Imports one book made from opts and opens it */
export async function readBook(page, opts) {
  const n = await cards(page).count();
  await importFiles(page, [epubFile(opts)], n + 1);
  await openBook(page, opts.title);
}

/** The page indicator read back: the chapter, page and pages. The
    indicator names the chapter by its title; the chapter is its number
    when the title ends in one (the made books' chapters are "Chapter N",
    and so is a chapter the contents do not name), else the title */
export async function place(page) {
  const t = await indicator(page).textContent();
  const n = s => { const d = /(\d+)$/.exec(s); return d ? +d[1] : s; };
  // a spread shows two pages a screen, "pages 3–4 of 40": its place is
  // counted in screens, as a turn is
  const spread = /^(.*)\s· pages (\d+)–(\d+) of (\d+) in chapter$/.exec(t.trim());
  if (spread) return { ch: n(spread[1]), p: (+spread[2] + 1) / 2, t: +spread[4] / 2 };
  const m = /^(.*)\s· page (\d+) of (\d+) in chapter$/.exec(t.trim());
  expect(m, `page indicator "${t}"`).not.toBeNull();
  return { ch: n(m[1]), p: +m[2], t: +m[3] };
}

/** Waits until the page indicator changes from before */
export async function placeChanged(page, before) {
  await expect.poll(async () => JSON.stringify(await place(page))).not.toBe(JSON.stringify(before));
  return place(page);
}

/** The first words of each paragraph or heading that starts on the
    page shown */
export async function startsOnPage(page) {
  return bookPage(page).evaluate(doc => {
    const c = doc.getBoundingClientRect();
    return [...doc.querySelectorAll('p, h1, h2, h3')]
      .filter(e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.left >= c.left - 1 && r.left < c.right; })
      .map(e => e.textContent.slice(0, 12));
  });
}

/** Whether a paragraph or heading starting with text is (at least in
    part) on the page shown */
export async function onPage(page, text) {
  return bookPage(page).evaluate((doc, text) => {
    const c = doc.getBoundingClientRect();
    return [...doc.querySelectorAll('p, h1, h2, h3')].some(e => {
      if (!e.textContent.startsWith(text)) return false;
      return [...e.getClientRects()].some(r => r.right > c.left && r.left < c.right);
    });
  }, text);
}

/** The text shown on the page (the paragraphs and headings in view) */
export async function visibleText(page) {
  return bookPage(page).evaluate(doc => {
    const c = doc.getBoundingClientRect();
    return [...doc.querySelectorAll('p, h1, h2')]
      .filter(e => { const r = e.getBoundingClientRect(); return r.right > c.left && r.left < c.right; })
      .map(e => e.textContent).join('\n');
  });
}

/** Selects characters [from, to) of the first text of the page's first
    paragraph */
export async function selectText(page, from, to) {
  await bookPage(page).locator('p').first().evaluate((el, [from, to]) => {
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

/** The selection's toolbar button of name */
export const selectionButton = (page, name) =>
  page.getByRole('toolbar', { name: 'Selection' }).getByRole('button', { name, exact: true });

/** How many ranges are painted over the text (highlights, or the
    search match), and the text of the first */
export async function marks(page) {
  return page.evaluate(() => {
    let size = 0, text = '';
    for (const [, h] of CSS.highlights) {
      for (const r of h) { if (!size) text = r.toString(); size++; }
    }
    return { size, text };
  });
}

/** The colour behind the view shown, and the text's colour */
export async function colours(page) {
  return page.getByRole('main').filter({ visible: true }).evaluate(e => {
    let el = e;
    while (el && getComputedStyle(el).backgroundColor === 'rgba(0, 0, 0, 0)') el = el.parentElement;
    const rgb = s => s.match(/\d+/g).slice(0, 3).map(Number);
    return { bg: rgb(getComputedStyle(el || document.body).backgroundColor), fg: rgb(getComputedStyle(e).color) };
  });
}

/** Leaves the reader for the library, through its back arrow (in the
    bars, which hide themselves 5 s after they are shown: bringing them
    up and clicking are tried again together, as clickControl does) */
export async function toLibrary(page) {
  await expect(async () => {
    await showChrome(page);
    await page.getByRole('button', { name: 'Back to library' }).click({ timeout: 2000 });
  }).toPass({ timeout: 20000 });
  await expect(librarySearch(page)).toBeVisible();
}

/** Opens the reader's bars when they are hidden */
export async function showChrome(page) {
  const prev = control(page, 'Previous page');
  if (!(await prev.isVisible())) {
    const box = await bookPage(page).boundingBox();
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  }
  await expect(prev).toBeVisible();
}

/** Clicks the bottom bar's control name, bringing the bars up first.
    The bars hide themselves 5 s after they are shown, so a slow step
    before the click (an audit, a loaded machine) can see them up and
    then lose them: bringing them up and clicking are tried again
    together until the click lands */
export async function clickControl(page, name) {
  await expect(async () => {
    await showChrome(page);
    await control(page, name).click({ timeout: 2000 });
  }).toPass({ timeout: 20000 });
}

/** Opens the reading settings' sheet */
export async function openSettings(page) {
  await clickControl(page, 'Reading settings');
  await expect(dialog(page, 'Reading settings')).toBeVisible();
}

/** The reading settings' sheet */
export function readingSettings(page) {
  return dialog(page, 'Reading settings');
}

/** The reading settings' sheet open on its tab named tab (Look, Page,
    Turning or Read aloud) */
export async function openReadingSettings(page, tab) {
  if (!tab) throw new Error('openReadingSettings: which tab?');
  if (!(await readingSettings(page).isVisible())) await openSettings(page);
  const named = readingSettings(page).getByRole('tab', { name: tab, exact: true });
  await named.click();
  await expect(named).toHaveAttribute('aria-selected', 'true');
}

/** One column a screen, whatever the window: for a test of what a
    single page shows (a wide window in landscape shows a spread) */
export async function oneColumn(page) {
  await openReadingSettings(page, 'Page');
  await readingSettings(page).getByRole('group', { name: 'Pages on screen' })
    .getByRole('button', { name: 'One', exact: true }).click();
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
}

/** The visible buttons within root whose text has a contrast ratio
    under 3 against the background behind it, by their names */
export async function illegible(root) {
  return root.evaluate(root => {
    const rgba = s => { const m = s.match(/[\d.]+/g).map(Number); return { r: m[0], g: m[1], b: m[2], a: m.length > 3 ? m[3] : 1 }; };
    const lum = c => {
      const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
      return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    };
    const behind = e => {
      for (let el = e; el; el = el.parentElement) {
        const c = rgba(getComputedStyle(el).backgroundColor);
        if (c.a > 0.5) return c;
      }
      return { r: 255, g: 255, b: 255, a: 1 };
    };
    const bad = [];
    for (const b of root.querySelectorAll('button')) {
      const r = b.getBoundingClientRect();
      if (r.width === 0 || !b.textContent.trim()) continue;
      const fg = lum(rgba(getComputedStyle(b).color)), bg = lum(behind(b));
      const ratio = (Math.max(fg, bg) + 0.05) / (Math.min(fg, bg) + 0.05);
      if (ratio < 3) bad.push(b.getAttribute('aria-label') || b.textContent.trim());
    }
    return bad;
  });
}

// ---- fixed layout ----

/** A page of a fixed-layout book: an image of the page's size (600 by
    800, drawn at twice that), with its viewport meta unless bare, and
    its itemref's properties, if any */
export const imagePage = (n, bare = false, itemref = undefined) => ({
  head: bare ? '' : '<meta name="viewport" content="width=600, height=800"/>',
  body: `<div><img src="images/page${n}.png" alt="Page ${n}"/></div>`,
  itemref,
});

/** A fixed-layout book of count image pages: the pages listed in bare
    have no viewport meta; spread is its rendition:spread (none, when
    left out); itemrefs, each page's itemref properties; rtl, read
    right to left */
export const fixedLayoutBook = (title, count, { bare = [], spread, itemrefs = [], rtl = false } = {}) => ({
  title, author: 'Fixed Tests', chapters: count, rtl,
  metadata: '<meta property="rendition:layout">pre-paginated</meta>\n' +
    (spread ? `<meta property="rendition:spread">${spread}</meta>\n` : ''),
  rawChapters: Array.from({ length: count }, (_, k) => imagePage(k + 1, bare.includes(k + 1), itemrefs[k])),
  extraImages: Array.from({ length: count }, (_, k) => ({ name: `images/page${k + 1}.png`, data: solidPng(1200, 1600) })),
});

/** The page indicator of a fixed page read back: the spine item shown
    (the first of a spread's two, with last the second) and the book's
    count */
export async function fixedPlace(page) {
  const text = (await indicator(page).textContent()).trim();
  const spread = /· pages (\d+)–(\d+) of (\d+) in book$/.exec(text);
  if (spread) return { p: +spread[1], last: +spread[2], t: +spread[3] };
  const m = /· page (\d+) of (\d+) in book$/.exec(text);
  expect(m, `page indicator "${text}"`).not.toBeNull();
  return { p: +m[1], t: +m[2] };
}

/** Imports the book made from opts and opens it, waiting for its first
    fixed page */
export async function readFixed(page, opts) {
  const n = await cards(page).count();
  await importFiles(page, [epubFile(opts)], n + 1);
  await card(page, opts.title).click();
  await expect(bookPage(page)).toBeVisible();
  await expect(indicator(page)).toContainText('in book');
}

/** The fixed pages shown: the page (the whole reader view) and each of
    its boxes, left to right, with the image in it (its name, and
    whether it is loaded) */
export const fixedBoxes = page => bookPage(page).evaluate(doc => {
  const rect = e => { const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height }; };
  const sides = [...doc.children].map(box => {
    const image = box.querySelector('img');
    return {
      ...rect(box), laidOut: { w: box.offsetWidth, h: box.offsetHeight },
      image: image ? { ...rect(image), name: image.alt, loaded: image.complete && image.naturalWidth > 0 } : null,
    };
  });
  const shown = sides.find(side => side.image) || sides[0];
  return { view: rect(doc), sides, page: shown, image: shown && shown.image, loaded: !!(shown && shown.image && shown.image.loaded) };
});

/** The bottom bar follows the reading axis (quire#359; Apple's HIG and
    Material both flip progress and the page turns in a right-to-left
    context): with the bars up, at the book's start the scrubber's thumb
    is in the track's right half and Previous is right of Next when the
    book reads right to left (the left half and the other way round when
    it reads left to right), and the thumb moves the way the book goes
    as the pages are turned */
export async function expectBarFollows(page, rightToLeft) {
  await showChrome(page);
  const box = async selector => {
    const b = await page.locator(selector).boundingBox();
    return { middle: b.x + b.width / 2, left: b.x, right: b.x + b.width };
  };
  const track = await box('#scrubber-track');
  const thumb = await box('#scrubber-thumb');
  const previous = await box('#previous-page');
  const next = await box('#next-page');
  const trackMiddle = track.middle;
  expect(thumb.middle > trackMiddle, 'the thumb at the start is in the track\'s ' + (rightToLeft ? 'right' : 'left') + ' half').toBe(rightToLeft);
  expect(previous.middle > next.middle, 'Previous is ' + (rightToLeft ? 'right' : 'left') + ' of Next').toBe(rightToLeft);
  expect(track.middle > Math.max(previous.middle, next.middle) || track.middle < Math.min(previous.middle, next.middle), 'the scrubber between the page turns').toBe(false);
}

/** Export backup, from the open Settings screen: the file's text, as the
    browser downloads it or the app shares it, and the dialog that says
    it was saved (quire#362) answered. */
export async function exportedBackup(page) {
  const inApp = await page.evaluate(() => !!(window.__android && window.Capacitor && window.Capacitor.Plugins.Share));
  const shares = () => page.evaluate(() => window.__android.calls.filter(c => c.plugin === 'Share').length);
  const before = inApp ? await shares() : 0;
  const download = inApp ? null : page.waitForEvent('download');
  await settingsButton(page, 'Export backup').click();
  let text;
  if (inApp) {
    await expect.poll(shares).toBe(before + 1);
    text = Buffer.from(await page.evaluate(() => window.__android.files.get('quire-backup.json')), 'base64').toString('utf8');
  } else {
    const file = await download;
    expect(file.suggestedFilename()).toBe('quire-backup.json');
    text = readFileSync(await file.path(), 'utf8');
  }
  const saved = dialog(page, 'Backup saved');
  await expect(saved).toContainText(inApp ? 'quire-backup.json was shared' : 'quire-backup.json is in your downloads');
  await saved.getByRole('button', { name: 'OK' }).click();
  return text;
}

/** The error banner on screen says what to do next (quire#360): a
    button besides Dismiss (Reopen Quire), or words that name the step;
    and in the Android app it does not say "browser". Call it where a
    spec has the banner up */
const NEXT_STEP = /(Reopen Quire|Import the book again|Choose another|Update Quire|Free some space|try opening it again|remove it in your Google account|Turn the device's own rotation lock|Select the text and copy|Restore a backup|Try Next phrase)/;
export async function expectBannerSaysWhatToDo(page, testInfo) {
  const banner = page.getByRole('alert');
  await expect(banner).toBeVisible();
  const text = await banner.innerText();
  const reopen = await banner.getByRole('button', { name: 'Reopen Quire' }).isVisible();
  expect(reopen || NEXT_STEP.test(text), `the banner says what to do: ${text}`).toBe(true);
  if (testInfo.project.name === 'android') expect(text, 'no "browser" in the app').not.toMatch(/browser/i);
}
