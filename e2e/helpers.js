// Shared steps for the e2e tests: books made on the fly, imported
// through the file input, opened from their cards, and the reader's
// place read back from the page.
//
// Everything is found as a reader finds it: by role, accessible name,
// label or visible text. No test depends on an element's id or class.

import { expect } from '@playwright/test';
import { createEpub, solidPng } from './create-epub.js';
import { attempted, noted } from './attempt-log.js';
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
export const importInput = page => page.locator('#import-file');

/** Waits until the import in progress has ended: the import's progress
    (#import-progress, whatever its stage says: "Reading file", "Opening
    archive", "Reading metadata", "Adding to library") is gone, and with it
    the file input is made anew (the app clears it in the same step), so
    the next file is picked on the input the app keeps. A wait for some
    stages' words passed in the stage between them ("Reading metadata"),
    while the import ran on, and the next file was then set on an input the
    app replaced a moment later: its change was lost and no question came */
export const importEnded = page => expect(page.locator('#import-progress')).toBeHidden();

/** The empty library's own Import EPUB (quire#375): its input and the
    button over it */
/** The Import EPUB the reader sees: the bar's, or the empty library's */
export const importOffered = page => page.locator('input[type=file][aria-label="Import EPUB"]:visible');

export const emptyImportInput = page => page.locator('#empty-import-file');

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

/** The cards' titles, in the order shown (a card's first line), read in one
    evaluation: a locator's allInnerTexts finds the cards in one call and reads
    them in a second, and a library that is drawn again between the two (the
    cards replaced) gives the text of the detached cards, which has no line
    breaks, so a whole card was the "title" (#575, library-records QLB4 on CI,
    job 119175168267: the read cards had isConnected false) */
export async function titles(page) {
  // the regions are found by their role and accessible name (aria-label), as `cards` finds them, in the same evaluation that reads the cards
  return page.evaluate(() => ['Continue reading', 'Books']
    .flatMap(name => [...document.querySelectorAll(`[role=region][aria-label="${name}"]`)])
    .filter(region => region.checkVisibility({ visibilityProperty: true }))
    .flatMap(region => [...region.querySelectorAll('[role=group]')])
    .filter(group => group.checkVisibility({ visibilityProperty: true }))
    .map(group => group.innerText.split('\n')[0].trim()));
}

/** The library's search box, whose presence says the library is shown */
/** The library is shown: its bar's name (the search box is not there while the library is empty, quire#375) */
export const libraryShown = page => page.locator('#library-title');

export const librarySearch = page => page.getByRole('searchbox', { name: 'Search the library' });

/** A dialog by its name (the modal dialog is named by its title) */
/** The collection button of the library, named by the collection shown
    (quire#861: one button, which opens the collection menu) */
export const collectionButton = page => page.getByRole('button', { name: /^Collection:/ });
export const collectionMenu = page => page.getByRole('menu', { name: 'Collection' });

/** Shows a collection (or All books), by the collection menu */
export async function showCollection(page, name) {
  await collectionButton(page).click();
  await expect(collectionMenu(page)).toBeVisible();
  await collectionMenu(page).getByRole('menuitemradio', { name, exact: true }).click();
  await expect(collectionMenu(page)).toBeHidden();
}

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

/** The sort and view menu (quire#377, #404), opened from the bar's Sort
    and view button */
export const sortMenu = page => page.getByRole('menu', { name: 'Sort and view' });

export async function openSortMenu(page) {
  await page.getByRole('button', { name: 'Sort and view', exact: true }).click();
  await expect(sortMenu(page)).toBeVisible();
}

/** Chooses an order (Title, Author, ...) or a layout (List, Grid) in the
    sort and view menu; the menu closes with the choice */
export async function chooseInSortMenu(page, name) {
  await openSortMenu(page);
  await sortMenu(page).getByRole('menuitemradio', { name, exact: true }).click();
  await expect(sortMenu(page)).toBeHidden();
}

/** The checked choices of the sort and view menu, by name (the order, then
    the layout); the menu is opened and closed again */
export async function sortMenuChecked(page) {
  await openSortMenu(page);
  const checked = await sortMenu(page).getByRole('menuitemradio', { checked: true }).allTextContents();
  await page.keyboard.press('Escape');
  await expect(sortMenu(page)).toBeHidden();
  return checked;
}

/** A shelf's own screen (Hidden, Archived, Trash; quire#404), opened from
    the library menu, and the controls that show it is open */
export async function openShelf(page, name) {
  await libraryMenu(page);
  await menuItem(page, name).click();
  await expect(shelfTitle(page)).toHaveText(name);
}
export const shelfTitle = page => page.locator('#shelf-title');

/** The question that empties the Trash (quire#385): its title counts what
    goes ("Delete 2 books forever?") */
export const emptyTrashDialog = page => page.getByRole('dialog', { name: /^Delete .* forever\?$/ });

/** The Trash's own screen, with its Empty Trash pressed: the question is up */
export async function askEmptyTrash(page) {
  await openShelf(page, 'Trash');
  await page.getByRole('button', { name: 'Empty Trash' }).click();
  await expect(emptyTrashDialog(page)).toBeVisible();
}

/** The Trash emptied, and back at the library */
export async function emptyTrash(page) {
  await askEmptyTrash(page);
  await emptyTrashDialog(page).getByRole('button', { name: 'Delete forever' }).click();
  await page.locator('#shelf-back').click();
}
export const shelfBack = page => page.locator('#shelf-back');

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
  await expect(libraryShown(page)).toBeVisible();
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

/** Opens the book whose card has text, and waits for its first page; reader acts: the bars are brought up unless asOpened */
export async function openBook(page, text, { asOpened = false } = {}) {
  await card(page, text).click();
  await pageShown(page);
  await rulerOnWhenAsked(page);
  // reader acts: the key, not a tap, which can land on the book's content
  if (!asOpened && !(await control(page, 'Previous page').isVisible())) {
    await page.keyboard.press('t');
    await expect(control(page, 'Previous page')).toBeVisible();
  }
}

/** With QUIRE_READING_RULER set to a style's name (say Lightbox), a book just opened has the reading
    ruler on in that style, chosen in the Look tab as a reader does (reading-ruler.spec.js, #566) */
async function rulerOnWhenAsked(page) {
  const style = process.env.QUIRE_READING_RULER;
  if (!style) return;
  await openReadingSettings(page, 'Look');
  const sheet = readingSettings(page);
  await sheet.getByRole('group', { name: 'Reading ruler', exact: true }).getByRole('button', { name: style, exact: true }).click();
  await page.keyboard.press('Escape');
  await expect(sheet).toBeHidden();
}

/** Waits until the book just opened shows its page: the reader is up
    before its chapter is loaded, and a key pressed until then turns
    nothing */
export async function pageShown(page) {
  await expect(bookPage(page)).toBeVisible();
  await expect(indicator(page)).toContainText('in chapter');
}

/** Imports one book made from opts and opens it */
export async function readBook(page, opts, { asOpened = false } = {}) {
  const n = await cards(page).count();
  await importFiles(page, [epubFile(opts)], n + 1);
  await openBook(page, opts.title, { asOpened });
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

/** A control behind the selection toolbar's More (a highlight style's
    swatch, Search, Read from here): More is pressed when the row it
    turns over is not shown, then the control is */
export async function selectionPick(page, name) {
  const more = selectionButton(page, 'More');
  if ((await more.getAttribute('aria-expanded')) === 'false') await more.click();
  await selectionButton(page, name).click();
}

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

/** Chrome's own time, in this window and arrangement, to lay out and draw
    the page's DOM: a copy of it, with the page's styles (the stylesheet
    applies to a copy as to the page), put beside the page, laid out, drawn
    for two frames, and removed. A hosted runner that is slow is slow for
    the copy too, so what the app takes is held to a multiple of it */
export async function bareFrameMs(page) {
  return page.evaluate(async () => {
    const doc = document.querySelector('[role=document][aria-label=Page]');
    if (!doc) return 0; // no page shown: no layout to wait for
    const frame = () => new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done)));
    const copy = doc.cloneNode(true);
    for (const attribute of ['id', 'role', 'aria-label', 'tabindex', 'data-gesture-region']) copy.removeAttribute(attribute);
    for (const element of copy.querySelectorAll('[id]')) element.removeAttribute('id');
    const box = doc.getBoundingClientRect();
    copy.setAttribute('inert', '');
    copy.style.cssText = `position:fixed;left:${box.left}px;top:${box.top}px;width:${box.width}px;height:${box.height}px;max-width:none;max-height:none;margin:0;z-index:-1;pointer-events:none`;
    await frame();
    const started = performance.now();
    doc.parentElement.append(copy);
    copy.getBoundingClientRect();
    await frame();
    const took = performance.now() - started;
    copy.remove();
    await frame();
    return took;
  });
}

/** Leaves the reader for the library, through its back arrow (in the
    bars, which a page turn or a jump can take down: bringing them
    up and clicking are tried again together, as clickControl does).

    The page answers a tap or a click only once the task it is in has
    ended, and the work a long chapter in columns costs the main thread
    (the layout, the hit test) is one task of seconds, longer on a loaded
    runner (#600: a megabyte of one word on a phone left a click of 2 s
    tried for 20 unanswered). The wait is therefore the page's own time to
    answer, as #522's `slow` is the layout's: what bringing the bars up
    took (it has no timeout of its own, so its time is the page's), and,
    after a click that was not answered, what `bareFrameMs` took (asked
    behind the task the click waits for, so its time is that task's cost on
    this runner now). The longest of them is the layout's (`layoutMs`); each
    click waits three times it and a second (the open budget of
    e2e/pathological.spec.js), and the tries last 20 s and three times it.
    A button that is not there is still given up on after 20 s: the
    layout's time is the page's, not the button's. */
const BACK_CLICK_MS = 2000;
const BACK_TRIES_MS = 20000;
const BACK_LAYOUT_TIMES = 3;
const BACK_ALLOWANCE_MS = 1000;
export async function toLibrary(page, { layoutMs: known = 0 } = {}) {
  const started = Date.now();
  // `known` is the layout the page is in, when the caller measured it (#600)
  let layoutMs = known;
  for (let attempt = 1; ; attempt++) {
    const clickMs = clickAllowanceMs(layoutMs);
    try {
      // each try is noted (#600): how long the bars took, the click's allowance
      // and why it was tried again, with what the page's main thread did
      await attempted(page, 'toLibrary', attempt, async (note) => {
        const barsAt = Date.now();
        await showChrome(page, { layoutMs });
        layoutMs = Math.max(layoutMs, Date.now() - barsAt);
        note.set({ barsMs: Date.now() - barsAt });
        await page.getByRole('button', { name: 'Back to library' }).click({ timeout: clickMs });
      }, { clickAllowanceMs: clickMs, layoutMs });
      break;
    } catch (failure) {
      // a click that timed out may have been made all the same: the events
      // it sent are answered when the task the page was in has ended, so the
      // library can be there already (#600)
      if (await libraryShown(page).isVisible()) {
        noted(page, 'toLibrary', attempt, { why: 'the click failed but the library is shown: the click was made all the same' });
        break;
      }
      const askedAt = Date.now();
      await bareFrameMs(page);
      layoutMs = Math.max(layoutMs, Date.now() - askedAt);
      const giveUp = Date.now() - started > triesAllowanceMs(layoutMs);
      noted(page, 'toLibrary', attempt, { bareFrameMs: Date.now() - askedAt, layoutMsNow: layoutMs, sinceStartMs: Date.now() - started, why: giveUp ? 'giving up: the tries ran out' : 'tried again after the page answered a bare frame' });
      if (giveUp) throw failure;
    }
  }
  await expect(libraryShown(page)).toBeVisible();
}

/** Puts away what a click that timed out may have left in the page (#600).
    A locator's click puts Playwright's hit target interceptor in the page
    (the injected script's `_hitTargetInterceptor`, a capture listener on the
    window) and takes it away when the click is done. A click that times out
    while the page is in a task of seconds (the columns of a long chapter)
    can have its setup run after the page answers, with nobody to stop it,
    and then it stops every pointer event that is not on its element
    (`stopImmediatePropagation`, from the first one on: its verdict is
    made once), the page's own listeners never seeing them. A raw
    `page.mouse` tap is such an event, so the bars did not come up. The
    next action of a locator that completes sets up its own interceptor,
    replacing the stale one, and stops it: a trial hover on the document is
    that action: it moves the pointer to the centre of the viewport, which
    the click, double click or move after it sets anyway (see rawMouse). */
export async function releaseClick(page, timeout = 2000) {
  // a trial hover that times out in a task of seconds can leave its own
  // interceptor behind in the same way, so it is made again until one
  // completes (the one that completes puts its own in place and stops it)
  for (let tries = 1; ; tries++) {
    try {
      await attempted(page, 'releaseClick', tries, () => page.locator('html').hover({ trial: true, timeout }), { timeoutMs: timeout });
      return;
    } catch (failure) {
      if (tries >= 5) throw failure;
    }
  }
}

/** Every raw pointer event a spec makes (Playwright's mouse: a click, a double
    click, a move, a press, a release, a wheel) goes through here (#630).
    Callers name the action as a string: rawMouse(page, 'click', x, y). The
    fixtures (fixtures.js) replace a test's page.mouse with one whose methods
    throw, and keep the real mouse in `realMice`, which only this function
    reads: a raw call, however it is written, fails at run time.

    releaseClick is a trial hover, and a trial hover MOVES the pointer to the
    centre of the viewport (Playwright runs the move and only the hit-target
    interceptor is blocked: measured on 1.58.2). So it is made only before an
    event that sets the pointer itself (click, dblclick, move) and only while
    no button is held, never between a move and the press, the wheel or the
    release that rely on where the pointer is. */
const buttonHeld = new WeakSet();
// the page's real mouse, given by fixtures.js (keepRealMouse); a page it did
// not give one falls back on its own
const realMice = new WeakMap();
export function keepRealMouse(page, mouse) {
  realMice.set(page, mouse);
}
export async function rawMouse(page, action, ...args) {
  if (['click', 'dblclick', 'move'].includes(action) && !buttonHeld.has(page)) await releaseClick(page);
  if (action === 'down') buttonHeld.add(page);
  if (action === 'up') buttonHeld.delete(page);
  const mouse = realMice.get(page) ?? page.mouse;
  return mouse[action](...args);
}

/** Opens the reader's bars when they are hidden */
export async function showChrome(page, { layoutMs = 0, again = true } = {}) {
  const prev = control(page, 'Previous page');
  const wasUp = await prev.isVisible();
  // a tap while text is selected only ends the selection (quire#428), so
  // the tap is made again when the bars did not come up; each tap is noted (#600)
  // The note of a tap that did not bring the bars up is made from the read the
  // loop makes anyway before the next tap (#715): the original's reads, no
  // more, and a note cannot throw. After the second tap the expect below reads.
  for (let tap = 0; tap < 2; tap++) {
    if (await prev.isVisible()) break;
    if (tap > 0) noted(page, 'showChrome', tap, { why: 'the bars were not up after the tap' });
    await attempted(page, 'showChrome', tap + 1, async (note) => {
      // a book page that is not there (a click that timed out was made, and
      // the library is shown) is no page to tap: the wait is the click's
      const box = await bookPage(page).boundingBox({ timeout: 2000 });
      await rawMouse(page, 'click', box.x + box.width / 2, box.y + box.height / 2);
      await page.waitForTimeout(150);
      // a tap between the zones on a highlight selects it, with its toolbar
      // (quire#428), and brings up no bars: the selection is ended and the
      // t key, which toggles them, brings them up
      if (!(await prev.isVisible()) && (await page.evaluate(() => getSelection().toString() !== ''))) {
        note.set({ why: 'a selection held the tap: it was ended and the t key pressed' });
        await page.evaluate(() => getSelection().removeAllRanges());
        await page.keyboard.press('t');
        await page.waitForTimeout(150);
      }
    });
  }
  // the bars come up when the page's task ends, so the wait is the layout's (#600)
  // Bars that were up when this began hide 5 s after they came up (keyword:
  // chrome timer, `_chrome_set` in quire.bats), and a wait that began just
  // before that never sees them again: it taps once more, as a fresh call (#932)
  try {
    await attempted(page, 'showChrome', 'wait', () => expect(prev).toBeVisible({ timeout: wasUp && again ? 1000 : stepExpectMs(layoutMs) }));
  } catch (error) {
    if (!(wasUp && again)) throw error;
    noted(page, 'showChrome', 'hidden', { why: 'the bars were up and hid while this waited: tapped again' });
    await showChrome(page, { layoutMs, again: false });
  }
}

/** The time a step that follows a layout may take: the layout's measured
    length in STEP_TIMES, plus STEP_ALLOWANCE_MS for what is not layout, and
    never less than the floor (the 15 s of the expect config). Measured
    (#600): one search and selection took 2.4 to 3.6 times the bare frame
    of the giant text in columns on a phone, so 5 times and 5 s is headroom. */
export const STEP_TIMES = 5;
export const STEP_ALLOWANCE_MS = 5000;

/** The longest layout a step waits for (#600). Every timeout that a layout
    sets takes the layout through this bound (stepExpectMs, clickAllowanceMs,
    triesAllowanceMs, and layoutBudget's test budget), so a layout measured
    longer than it is waited for only this long, and a test with a page that
    stalls for a minute fails at this bound, not after twenty minutes.
    Evidence: the largest layout measured for the giant text in columns on the
    phone project is 3.5 s (bareFrameMs's first read, unloaded; 1.75 s warm,
    layout-budget.js). Under CPU throttling 2.5 the largest layout attached to a
    failing run is 2.6 s (a task of 2575 ms behind a click, the diagnosis
    comment on #600). 30 s is 8.6 times the unloaded first read, and about 3.3 times
    what that read would be at throttling 2.5 (9 s, if the layout scaled with
    the throttle, as it is taken to here). The test of tests/layout-cap checks
    the bound. */
export const LAYOUT_CAP_MS = 30000;
export function layoutCapped(layoutMs) {
  return Math.min(layoutMs, LAYOUT_CAP_MS);
}

export function stepExpectMs(layoutMs, floorMs = 15000) {
  return Math.max(floorMs, STEP_TIMES * layoutCapped(layoutMs) + STEP_ALLOWANCE_MS);
}

/** How long one click waits for its element, as the layout the page is in
    takes (see the cap above): 2 s with no layout, as before */
export function clickAllowanceMs(layoutMs) {
  return Math.max(BACK_CLICK_MS, BACK_LAYOUT_TIMES * layoutCapped(layoutMs) + BACK_ALLOWANCE_MS);
}

/** How long the tries of one action last, with each try's click */
export function triesAllowanceMs(layoutMs) {
  return BACK_TRIES_MS + BACK_LAYOUT_TIMES * layoutCapped(layoutMs);
}

// ---- the app's own timers, run on the fake clock (#657) ----
//
// A page whose clock was installed before it opened (`page.clock.install()`)
// still sees time pass as real time does, and `runFor` adds to it: every
// timer due in the span fires in order, those a timer sets in turn too, and
// the network, IndexedDB and fonts, which are not the clock's, are left
// alone. A test waits for a moment of the app's (the back
// button's 10 s, a toast's 2 s, a poll's 3 s) by running the clock to it,
// not by waiting for it.

/** What the page's clock reads, in milliseconds */
export const clockNow = page => page.evaluate(() => Date.now());

/** Runs the page's fake clock until it reads `since + ms` (it does not go
    back if it is past), and answers how far past `since` it reads */
export async function runTo(page, since, ms) {
  const now = await clockNow(page);
  if (now < since + ms) await page.clock.runFor(since + ms - now);
  return (await clockNow(page)) - since;
}

/** A moment of the app's of `ms` that began no earlier than `since` (a
    `clockNow` read before what began it) is over: the element is still
    there `slack` before it ends, and gone `slack` after. The first is
    not asserted when a loaded machine has let the real flow of time
    carry the clock to within half a second of the end by itself, since
    it could then be gone by right; the second always is */
export async function expectMoment(page, element, { since, ms, slack = 1500 }) {
  const early = await runTo(page, since, ms - slack);
  if (early < ms - 500) await expect(element).toBeVisible();
  await runTo(page, since, ms + slack);
  await expect(element).toBeHidden();
}

/** Runs the fake clock on in steps of `stepMs` until `done` answers true
    (the polls of a sign-in, a retry): the span is as long as the app's
    timers need, and the real wait is only for the answers that come in
    real time */
export async function runUntil(page, done, { stepMs = 1000, timeout = 30000 } = {}) {
  await expect.poll(async () => {
    await page.clock.runFor(stepMs);
    return done();
  }, { timeout, intervals: [50] }).toBe(true);
}

/** reader acts: takes the bars down and the hint away by acts, as neither goes by itself */
export async function bareReader(page) {
  const bars = page.getByRole('toolbar', { name: 'Page controls' });
  if (await bars.isVisible()) await page.keyboard.press('t');
  const hint = page.getByText('Tap the middle for the menu.');
  if (await hint.isVisible()) await hint.click();
  await expect(bars).toBeHidden();
  await expect(hint).toBeHidden();
}

/** reader acts: waits for the chapter the page indicator names, leaving the bars as they are */
export async function expectChapter(page, title, { timeout = 10000 } = {}) {
  await expect.poll(async () => ((await indicator(page).textContent()) ?? '').replace(/\s·\s+pages?\s.*$/s, '').trim(), { timeout }).toBe(title);
}

/** Clicks the bottom bar's control name, bringing the bars up first (reader acts, layout: tried again together) */
export async function clickControl(page, name, { layoutMs = 0 } = {}) {
  // a click waits as long as the layout the page is in (#600, as toLibrary's
  // does): a click made behind a columns layout is answered when the layout
  // ends, and one that timed out was made all the same, so a retry of it is
  // covered by the sheet it opened and never clicks. With no layout given the
  // click waits 2 s and the tries 20 s, as before. The bars' wait is the
  // layout's too (showChrome's own, #600).
  const clickMs = clickAllowanceMs(layoutMs);
  let attempt = 0;
  await expect(async () => {
    attempt += 1;
    await attempted(page, 'clickControl', attempt, async () => {
      await showChrome(page, { layoutMs });
      await control(page, name).click({ timeout: clickMs });
    }, { control: name, clickAllowanceMs: clickMs, layoutMs });
  }).toPass({ timeout: triesAllowanceMs(layoutMs) });
}

/** Opens the reading settings' sheet */
export async function openSettings(page, { layoutMs = 0 } = {}) {
  await clickControl(page, 'Reading settings', { layoutMs });
  await expect(dialog(page, 'Reading settings')).toBeVisible();
}

/** The reading settings' sheet */
export function readingSettings(page) {
  return dialog(page, 'Reading settings');
}

/** The reading settings' sheet open on its tab named tab (Look, Page,
    Turning or Read aloud) */
export async function openReadingSettings(page, tab, { layoutMs = 0 } = {}) {
  if (!tab) throw new Error('openReadingSettings: which tab?');
  if (!(await readingSettings(page).isVisible())) await openSettings(page, { layoutMs });
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
  // the chapter steps lie beyond the page turns, on their sides (#388)
  if (await page.locator('#chapter-next').isVisible()) {
    const stepNext = await box('#chapter-next');
    expect(stepNext.middle < next.middle, 'Next chapter is beyond Next page').toBe(rightToLeft);
  }
  if (await page.locator('#chapter-previous').isVisible()) {
    const stepPrevious = await box('#chapter-previous');
    expect(stepPrevious.middle > previous.middle, 'Previous chapter is beyond Previous page').toBe(rightToLeft);
  }
}

/** Whether a font with Han characters is installed: the canvas draws a
    Han character and a code point no font has the same width when none
    is, so a vertical book is empty boxes (quire#359, #391). The e2e job
    installs fonts-noto-cjk; the UX review's capture needs one too */
export function cjkFontInstalled(page) {
  return page.evaluate(() => {
    const context = document.createElement('canvas').getContext('2d');
    context.font = '32px sans-serif';
    return context.measureText('日本語').width !== context.measureText('\uFFFF\uFFFF\uFFFF').width;
  });
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
  await saved.getByRole('button', { name: 'Done' }).click();
  return text;
}

/** The error banner on screen says what to do next (quire#360): a
    button besides Dismiss (Reopen Quire), or words that name the step;
    and in the Android app it does not say "browser". Call it where a
    spec has the banner up */
const NEXT_STEP = /(Reopen Quire|Import the book again|Choose another|Update Quire|Free some space|try opening it again|remove it in your Google account|Turn the device's own rotation lock|Select the text and copy|Restore a backup|Try Next phrase|read this one in the app it came from)/;
export async function expectBannerSaysWhatToDo(page, testInfo) {
  const banner = page.getByRole('alert');
  await expect(banner).toBeVisible();
  const text = await banner.innerText();
  const reopen = await banner.getByRole('button', { name: 'Reopen Quire' }).isVisible();
  expect(reopen || NEXT_STEP.test(text), `the banner says what to do: ${text}`).toBe(true);
  if (testInfo.project.name === 'android') expect(text, 'no "browser" in the app').not.toMatch(/browser/i);
}
