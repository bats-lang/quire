// Nothing of book A shows in book B (#435): the reader keeps much of a
// book in cells (its spine, its direction, its writing mode, its clip
// table, its back button, its search, its marks, the text read aloud), and
// this opens a book that has every one of them, uses each, and then opens
// one that has none, and checks that what is shown is the second's. The
// books are in two-books-books.js: Alpha has five
// chapters, a nested contents, a page list, a note, a ruby, a narration,
// reads left to right and is Japanese; Beta has two chapters and none of
// that, and is Hebrew read right to left; Gamma is set vertically.
//
// What the issue lists as "a vertical setting" is the book's: Quire sets a
// book vertically from its OPF (a Japanese book read right to left) and has
// no setting of the reader's for it, so the vertical case is Gamma opened
// before Beta.
//
// The clip table of Alpha's narration is released when the next chapter is
// rendered; no probe of the arena's count is added to the app for it (a
// test hook in the shipped build), the check is what the table is for:
// Beta offers no narration controls, and the narration's audio plays
// nothing and has no source.

import { test, expect, onAndroid, androidApp, androidInsets, googleStubbed } from './fixtures.js';
import {
  start, importFiles, epubFile, openBook, showChrome, control, dialog, toLibrary, place, jumpBack,
  indicator, bookPage, selectText, selectionButton, marks, reload, chapterTitle, openReadingSettings,
  readingSettings, clickControl, expectBarFollows, cards, startsOnPage, cjkFontInstalled,
} from './helpers.js';
import { createEpub } from './create-epub.js';
import { twoBooks } from './two-books-books.js';
import { capture, fixedClock } from './relaunch.js';
import { reloadSettled } from './legacy-library.js';

const A = 'Alpha Ledger';
const B = 'Beta Ledger';
const G = 'Gamma Ledger';
const D = 'Delta Ledger';

const contents = page => dialog(page, 'Contents');
const contentsRows = (page, tab) => contents(page).getByRole('tabpanel', { name: tab }).getByRole('button');
const annotations = page => dialog(page, 'Annotations');
const searchPanel = page => dialog(page, 'Search in book');
const searchBox = page => searchPanel(page).getByRole('searchbox', { name: 'Search in book' });
const searchSummary = page => searchPanel(page).getByRole('status');
const searchRows = page => searchPanel(page).getByRole('region', { name: 'Results' }).getByRole('button');
const resultsBar = page => page.getByRole('toolbar', { name: 'Search results' });
const star = page => page.getByRole('button', { name: 'Bookmark this page' });
const readAloud = page => control(page, 'Read aloud');

/** A speech engine that says nothing and keeps what it was asked to say */
async function fakeSpeech(page) {
  await page.addInitScript(() => {
    window.spoken = [];
    window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
    const synth = {
      current: null,
      getVoices: () => [{ name: 'Reader', lang: 'en-US', voiceURI: 'reader-en', default: true }],
      speak(u) { window.spoken.push({ text: u.text, lang: u.lang }); this.current = u; },
      cancel() { const u = this.current; this.current = null; if (u && u.onerror) u.onerror({ error: 'interrupted' }); },
      addEventListener() {},
    };
    Object.defineProperty(window, 'speechSynthesis', { value: synth });
  });
}
const spoken = page => page.evaluate(() => window.spoken);

/** A wake lock the tests can count (the screen's own, as the reader keeps it) */
async function countedWakeLock(page) {
  await page.addInitScript(() => {
    const w = window.__wake = { held: 0, live: [] };
    Object.defineProperty(navigator, 'wakeLock', {
      configurable: true,
      value: {
        request: async () => {
          const on = [];
          const lock = { released: false, addEventListener: (type, f) => { if (type === 'release') on.push(f); }, release: async () => {
            if (lock.released) return;
            lock.released = true; w.held--; w.live = w.live.filter(l => l !== lock);
            on.forEach(f => f());
          } };
          w.held++; w.live.push(lock);
          return lock;
        },
      },
    });
  });
}
const wakeLocks = page => page.evaluate(() => window.__wake.held);

/** The narration's audio element's state, none when it is not made; revoked is whether the page revoked the blob URL it holds */
const narration = page => page.evaluate(() => {
  const a = document.getElementById('narration');
  if (!a) return null;
  const src = a.getAttribute('src') || '';
  return { paused: a.paused, time: a.currentTime, src, revoked: window.__revoked.includes(src) };
});

/** Whether the narration plays nothing and holds no source the app has not revoked */
const narrationReleased = async page => {
  const audio = await narration(page);
  return audio === null || (audio.paused && (audio.src === '' || audio.revoked));
};

/** Notes each blob URL the page revokes (the app revokes a narration's with its book) */
async function revocationsNoted(page) {
  await page.addInitScript(() => {
    window.__revoked = [];
    const revoke = URL.revokeObjectURL.bind(URL);
    URL.revokeObjectURL = url => { window.__revoked.push(url); revoke(url); };
  });
}

async function openContents(page) {
  await showChrome(page);
  await control(page, 'Contents').click();
  await expect(contents(page)).toBeVisible();
}

async function closeContents(page) {
  await page.keyboard.press('Escape');
  await expect(contents(page)).toBeHidden();
}

/** Opens the in-book search, searches for words, and goes to its first result */
async function searchFor(page, words) {
  await page.keyboard.press('/');
  await expect(searchPanel(page)).toBeVisible();
  await searchBox(page).fill(words);
  return searchPanel(page);
}

/** Imports A and B (and Gamma when asked) and opens nothing */
async function library(page, { gamma = false, delta = false } = {}) {
  await revocationsNoted(page);
  const errors = await start(page);
  const opts = [twoBooks.alpha.opts, twoBooks.beta.opts, ...(gamma ? [twoBooks.gamma.opts] : []), ...(delta ? [twoBooks.delta.opts] : [])];
  await importFiles(page, opts.map(o => epubFile(o)), opts.length);
  return errors;
}

/** The reader's Columns setting, Two */
async function columnsTwo(page) {
  await openReadingSettings(page, 'Page');
  await readingSettings(page).getByRole('group', { name: 'Pages on screen' }).getByRole('button', { name: 'Two', exact: true }).click();
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
}

/** Opens A and uses every feature it has: a bookmark, a highlight, a search
    gone to, a jump (the back button up), Columns Two, and its narration
    playing. Returns what it made, for the checks afterwards. */
async function useAlpha(page, { narrate = true } = {}) {
  await openBook(page, A);
  // a bookmark and a highlight, on the first page
  await page.keyboard.press('b');
  await showChrome(page);
  await expect(star(page)).toHaveAttribute('aria-pressed', 'true');
  await selectText(page, 0, 5);
  await selectionButton(page, 'Highlight').click();
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'Alpha' });
  // a search, and its first result gone to
  await searchFor(page, 'Zebrafish');
  await expect(searchSummary(page)).toHaveText('1 result');
  await searchRows(page).first().click();
  await expect(searchPanel(page)).toBeHidden();
  await expect(resultsBar(page)).toBeVisible();
  // a jump to chapter 3, which leaves the back button up
  await openContents(page);
  await contentsRows(page, 'Contents').filter({ hasText: 'Alpha Chapter 3' }).click();
  await expect(contents(page)).toBeHidden();
  await expect.poll(async () => (await place(page)).ch).toBe(3);
  await expect(jumpBack(page)).toBeVisible();
  await columnsTwo(page);
  // its narration, playing
  if (narrate) {
    await clickControl(page, 'Read aloud');
    await expect(readAloud(page)).toHaveAttribute('aria-pressed', 'true');
    await expect.poll(async () => (await narration(page)).time).toBeGreaterThan(0);
  }
}

/** What is shown of a book's text: the page's language and direction */
const pageLanguage = page => bookPage(page).evaluate(doc => {
  const own = doc.getAttribute('lang') || doc.closest('[lang]')?.getAttribute('lang') || '';
  const dir = getComputedStyle(doc).direction;
  const writing = getComputedStyle(doc).writingMode;
  return { lang: own, dir, writing };
});

test.describe('B opened after A', () => {
  test('its contents are its own: its chapters only, no Pages tab, no bookmarks, no annotations, no print page', async ({ page }) => {
    const errors = await library(page);
    await useAlpha(page);
    // A's own contents, for the comparison: nested, with the page list
    await openContents(page);
    await expect(contents(page).getByRole('tab')).toHaveText(['Contents', 'Bookmarks', 'Pages']);
    await expect(contentsRows(page, 'Contents')).toHaveText(['Alpha Chapter 1', 'Alpha Section 1.1', 'Alpha Chapter 2', 'Alpha Chapter 3', 'Alpha Section 3.1', 'Alpha Chapter 4', 'Alpha Chapter 5']);
    await closeContents(page);

    await toLibrary(page);
    await openBook(page, B);
    await openContents(page);
    await expect(contents(page).getByRole('tab', { name: 'Pages' })).toHaveCount(0);
    await expect(contents(page).getByRole('tab')).toHaveText(['Contents', 'Bookmarks']);
    await expect(contentsRows(page, 'Contents')).toHaveCount(2);
    await expect(contentsRows(page, 'Contents').nth(0)).toContainText('Beta Chapter 1');
    await expect(contentsRows(page, 'Contents').nth(1)).toContainText('Beta Chapter 2');
    expect(await contents(page).innerText()).not.toContain('Alpha');
    // its bookmarks are none
    await contents(page).getByRole('tab', { name: 'Bookmarks' }).click();
    await expect(contentsRows(page, 'Bookmarks').filter({ hasNot: page.getByRole('button', { name: 'Add note' }) })).toHaveCount(0);
    expect(await contents(page).getByRole('tabpanel', { name: 'Bookmarks' }).innerText()).not.toContain('Alpha');
    await closeContents(page);
    await expect(star(page)).toHaveAttribute('aria-pressed', 'false');
    // its annotations are none, and A's highlight is not painted
    await expect.poll(() => marks(page)).toEqual({ size: 0, text: '' });
    await showChrome(page);
    await control(page, 'Annotations').click();
    await expect(annotations(page)).toBeVisible();
    expect(await annotations(page).innerText()).not.toContain('Alpha');
    await expect(annotations(page).getByRole('button', { name: 'Delete' })).toHaveCount(0);
    await page.keyboard.press('Escape');
    // no print page in the footer, on its first page or any other
    await page.keyboard.press('t');
    await expect(page.getByText(/ · page .+ in print$/)).toHaveCount(0);
    await page.keyboard.press('ArrowRight');
    await expect(page.getByText(/ · page .+ in print$/)).toHaveCount(0);
    expect(errors).toEqual([]);
  });

  test('its search is its own: the field empty, no results of A\'s, nothing found of A\'s words', async ({ page }) => {
    const errors = await library(page);
    await useAlpha(page);
    await toLibrary(page);
    await openBook(page, B);
    await expect(resultsBar(page)).toBeHidden();
    await page.keyboard.press('/');
    await expect(searchPanel(page)).toBeVisible();
    await expect(searchBox(page)).toHaveValue('');
    await expect(searchRows(page)).toHaveCount(0);
    expect(await searchPanel(page).innerText()).not.toContain('Zebrafish');
    await searchBox(page).fill('Zebrafish');
    await expect(searchSummary(page)).toHaveText(/^(No results|0 results)/);
    await expect(searchRows(page)).toHaveCount(0);
    // and a word of its own is found, in its own chapters
    await searchBox(page).fill('Beta 2.3');
    await expect(searchSummary(page)).toHaveText('1 result');
    // after a reload the stored search is B's or none: never A's
    await page.keyboard.press('Escape');
    await reload(page);
    await expect(indicator(page)).toContainText('in chapter');
    await expect(resultsBar(page)).toBeHidden();
    await page.keyboard.press('/');
    await expect(searchPanel(page)).toBeVisible();
    await expect(searchBox(page)).not.toHaveValue(/Zebrafish/);
    await expect(searchRows(page)).toHaveCount(0);
    expect(errors).toEqual([]);
  });

  test('its place is its own: chapter 1, page 1, its chapters counted, its ticks, and A\'s back button gone', async ({ page }) => {
    const errors = await library(page);
    await useAlpha(page);
    expect((await place(page)).ch).toBe(3);
    const alphaTicks = await page.locator('#scrubber-ticks > *').count();
    expect(alphaTicks).toBe(4);
    await toLibrary(page);
    await openBook(page, B);
    const first = await place(page);
    expect(first.ch).toBe(1);
    expect(first.p).toBe(1);
    await expect(indicator(page)).toHaveText(/^Beta Chapter 1\D+pages? 1/);
    expect(await jumpBack(page).isVisible()).toBe(false);
    await showChrome(page);
    expect(await jumpBack(page).isVisible()).toBe(false);
    // the scrubber's ticks are B's: one between its two chapters
    expect(await page.locator('#scrubber-ticks > *').count()).toBe(1);
    // the chapters step through B's two and no further
    await page.keyboard.press('End');
    await page.keyboard.press('ArrowLeft');
    await page.keyboard.press('Home');
    await openContents(page);
    await contentsRows(page, 'Contents').nth(1).click();
    await expect.poll(async () => (await place(page)).ch).toBe(2);
    await expect(indicator(page)).toContainText('Beta Chapter 2');
    await page.keyboard.press('End');
    await page.keyboard.press('ArrowRight');
    await expect.poll(async () => (await place(page)).ch).toBe(2);
    expect(errors).toEqual([]);
  });

  test('its settings rows are its own: no ruby row, no narration, reading aloud by speech instead', async ({ page }) => {
    await fakeSpeech(page);
    const errors = await library(page);
    await useAlpha(page);
    // A has a ruby: the row is offered once its chapter has shown one
    await toLibrary(page);
    await openBook(page, A);
    await openContents(page);
    await contentsRows(page, 'Contents').filter({ hasText: 'Alpha Chapter 1' }).first().click();
    await expect.poll(async () => (await place(page)).ch).toBe(1);
    await openReadingSettings(page, 'Look');
    await expect(readingSettings(page).getByRole('group', { name: 'Pronunciation over the characters (ruby)' })).toHaveCount(1);
    await page.keyboard.press('Escape');
    await toLibrary(page);

    await openBook(page, B);
    await openReadingSettings(page, 'Look');
    await expect(readingSettings(page).getByRole('group', { name: 'Pronunciation over the characters (ruby)' })).toHaveCount(0);
    await page.keyboard.press('Escape');
    // no narration controls, and the narration's clip table is gone with its audio
    await showChrome(page);
    await expect(control(page, 'Previous phrase')).toBeHidden();
    await expect(control(page, 'Next phrase')).toBeHidden();
    expect(await narrationReleased(page)).toBe(true);
    // Read aloud is the speech's: offered with the voice settings
    await expect(readAloud(page)).toBeVisible();
    await openReadingSettings(page, 'Read aloud');
    await expect(readingSettings(page).getByRole('slider', { name: 'Narration speed' })).toBeHidden();
    await page.keyboard.press('Escape');
    expect(errors).toEqual([]);
  });

  test('its direction and language are its own, and A\'s again when A is opened', async ({ page }) => {
    const errors = await library(page);
    await useAlpha(page, { narrate: false });
    await expectBarFollows(page, false);
    expect(await pageLanguage(page)).toMatchObject({ lang: 'ja', dir: 'ltr' });
    await toLibrary(page);
    await openBook(page, B);
    await expectBarFollows(page, true);
    expect(await pageLanguage(page)).toMatchObject({ lang: 'he', dir: 'rtl' });
    // right to left: the next page is turned with the left arrow, as its book reads
    await page.keyboard.press('ArrowLeft');
    await expect.poll(async () => (await place(page)).p).toBe(2);
    await toLibrary(page);
    await openBook(page, A);
    await expectBarFollows(page, false);
    expect(await pageLanguage(page)).toMatchObject({ lang: 'ja', dir: 'ltr' });
    expect(errors).toEqual([]);
  });

  test('a vertical book does not leave the next one vertical', async ({ page }) => {
    test.skip(!(await cjkFontInstalled(page).catch(() => true)), 'no font has Japanese characters');
    const errors = await library(page, { gamma: true });
    await openBook(page, G);
    expect(await pageLanguage(page)).toMatchObject({ lang: 'ja', writing: 'vertical-rl' });
    await toLibrary(page);
    await openBook(page, B);
    const own = await pageLanguage(page);
    expect(own).toMatchObject({ lang: 'he', dir: 'rtl', writing: 'horizontal-tb' });
    // the layout's settings, hidden for a vertical book, are back
    await openReadingSettings(page, 'Page');
    await expect(readingSettings(page).getByRole('group', { name: 'Pages on screen' })).toBeVisible();
    await page.keyboard.press('Escape');
    // and A, horizontal too
    await toLibrary(page);
    await openBook(page, A);
    expect(await pageLanguage(page)).toMatchObject({ lang: 'ja', dir: 'ltr', writing: 'horizontal-tb' });
    expect(errors).toEqual([]);
  });

  test('a fixed-layout book does not leave its page box to the next one', async ({ page }) => {
    const errors = await library(page, { delta: true });
    await cards(page).filter({ hasText: D }).click();
    await expect(indicator(page)).toContainText('in book');
    await expect(page.locator('#page-box')).toHaveCount(1);
    await expect(page.locator('.caf.fixed')).toHaveCount(1);
    await toLibrary(page);
    await openBook(page, B);
    await expect(indicator(page)).toContainText('Beta Chapter 1');
    await expect(page.locator('.caf.fixed')).toHaveCount(0);
    // B's own text is laid out in its page, not in a box scaled to fit
    await expect(page.locator('#page-box')).toHaveCount(0);
    await expect(bookPage(page).locator('p').first()).toContainText('Beta 1.0');
    // the typography rows a fixed page hides are back
    await openReadingSettings(page, 'Look');
    await expect(page.locator('#font-row')).toBeVisible();
    await page.keyboard.press('Escape');
    expect(errors).toEqual([]);
  });

  test('reading aloud and the narration of A stop at the switch, and B reads aloud from its first sentence', async ({ page }) => {
    await fakeSpeech(page);
    await countedWakeLock(page);
    const errors = await library(page);
    await useAlpha(page);
    expect(await wakeLocks(page)).toBe(1);
    await toLibrary(page);
    const stopped = await narration(page);
    expect(stopped === null || stopped.paused).toBe(true);
    expect(await wakeLocks(page)).toBe(0);
    await openBook(page, B);
    await expect.poll(() => wakeLocks(page)).toBe(1);
    // the narration plays nothing in B
    expect(await narrationReleased(page)).toBe(true);
    expect(await spoken(page)).toEqual([]);
    await showChrome(page);
    await expect(readAloud(page)).toHaveAttribute('aria-pressed', 'false');
    await readAloud(page).click();
    await expect(readAloud(page)).toHaveAttribute('aria-pressed', 'true');
    await expect.poll(async () => (await spoken(page)).length).toBe(1);
    expect((await spoken(page))[0].text).toBe('Beta One');
    expect(await wakeLocks(page)).toBe(1);
    expect(errors).toEqual([]);
  });

  test('the reading settings are the reader\'s, but nothing per book is carried: Columns stay, the direction and mode do not', async ({ page }) => {
    const errors = await library(page);
    await useAlpha(page, { narrate: false });
    await toLibrary(page);
    await openBook(page, B);
    // the reader's own setting, made in A, is B's too
    await openReadingSettings(page, 'Page');
    const columns = readingSettings(page).getByRole('group', { name: 'Pages on screen' });
    await expect(columns.getByRole('button', { name: 'Two', exact: true })).toHaveAttribute('aria-pressed', 'true');
    await page.keyboard.press('Escape');
    // while the book's own things are B's
    expect(await pageLanguage(page)).toMatchObject({ lang: 'he', dir: 'rtl', writing: 'horizontal-tb' });
    await expectBarFollows(page, true);
    expect(errors).toEqual([]);
  });

  test('A, then B, then A: everything is A\'s again, its notes and its place intact', async ({ page }) => {
    const errors = await library(page);
    await useAlpha(page, { narrate: false });
    const left = await place(page);
    await toLibrary(page);
    await openBook(page, B);
    await toLibrary(page);
    await openBook(page, A);
    expect(await place(page)).toEqual(left);
    // its bookmark and highlight, listed and painted
    await expect.poll(() => marks(page)).toEqual({ size: 0, text: '' });
    await openContents(page);
    await expect(contents(page).getByRole('tab')).toHaveText(['Contents', 'Bookmarks', 'Pages']);
    await expect(contentsRows(page, 'Contents')).toHaveCount(7);
    await contents(page).getByRole('tab', { name: 'Pages' }).click();
    await expect(contentsRows(page, 'Pages')).toHaveText(['101', '102']);
    await contents(page).getByRole('tab', { name: 'Bookmarks' }).click();
    await expect(contentsRows(page, 'Bookmarks').first()).toContainText('Alpha');
    await closeContents(page);
    await showChrome(page);
    await control(page, 'Annotations').click();
    await expect(annotations(page)).toContainText('Alpha');
    await page.keyboard.press('Escape');
    // the first chapter's mark is painted when it is shown again
    await openContents(page);
    await contentsRows(page, 'Contents').filter({ hasText: 'Alpha Chapter 1' }).first().click();
    await expect.poll(async () => (await place(page)).ch).toBe(1);
    await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'Alpha' });
    await showChrome(page);
    await expect(star(page)).toHaveAttribute('aria-pressed', 'true');
    // the search of A is not carried over B: it is empty now, and finds A's word again
    await page.keyboard.press('/');
    await expect(searchPanel(page)).toBeVisible();
    await searchBox(page).fill('Zebrafish');
    await expect(searchSummary(page)).toHaveText('1 result');
    await page.keyboard.press('Escape');
    expect(errors).toEqual([]);
  });
});

test('B opened after A and a reload with the view kept is B\'s, with nothing of A\'s', async ({ page }) => {
  const errors = await library(page);
  await useAlpha(page, { narrate: false });
  await toLibrary(page);
  await openBook(page, B);
  await expect(indicator(page)).toHaveText(/^Beta Chapter 1/);
  await reload(page);
  await expect(indicator(page)).toContainText('in chapter');
  await expect(indicator(page)).toHaveText(/^Beta Chapter 1/);
  await openContents(page);
  await expect(contents(page).getByRole('tab')).toHaveText(['Contents', 'Bookmarks']);
  await expect(contentsRows(page, 'Contents')).toHaveCount(2);
  await closeContents(page);
  await expect(jumpBack(page)).toBeHidden();
  await expectBarFollows(page, true);
  expect(await pageLanguage(page)).toMatchObject({ lang: 'he', dir: 'rtl' });
  await expect.poll(() => marks(page)).toEqual({ size: 0, text: '' });
  expect(errors).toEqual([]);
});

/** A catalogue whose one book is B's EPUB, served here (page.route) */
async function catalogueOf(page, epub) {
  const CORS = { 'access-control-allow-origin': '*' };
  await page.route(url => url.hostname !== 'localhost', route => route.abort());
  await page.route('https://catalogue.test/**', route => {
    const url = new URL(route.request().url());
    if (url.pathname === '/opds/root.xml') {
      return route.fulfill({ status: 200, headers: CORS, contentType: 'application/atom+xml', body: `<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"><id>urn:test</id><title>Two Books</title><updated>2026-10-01T00:00:00Z</updated>
<entry><title>${B}</title><id>beta</id><author><name>Two Books</name></author>
<link rel="http://opds-spec.org/acquisition/open-access" href="/books/beta.epub" type="application/epub+zip"/></entry></feed>` });
    }
    if (url.pathname === '/books/beta.epub') return route.fulfill({ status: 200, headers: CORS, contentType: 'application/epub+zip', body: epub });
    return route.fulfill({ status: 404, headers: CORS, body: '' });
  });
}

test('B got from a catalogue and opened after A is B\'s, with nothing of A\'s', async ({ page }) => {
  await catalogueOf(page, createEpub({ storeChapters: true, ...twoBooks.beta.opts }));
  const errors = await start(page);
  await importFiles(page, [epubFile(twoBooks.alpha.opts)], 1);
  await useAlpha(page, { narrate: false });
  await toLibrary(page);
  // B is got from the catalogue and imported as a picked file is
  await page.getByRole('button', { name: 'More options' }).first().click();
  await page.getByRole('menuitem', { name: 'Catalogues', exact: true }).click();
  const catalogues = dialog(page, 'Catalogues');
  await catalogues.getByRole('textbox', { name: 'Catalogue name' }).fill('Two Books');
  await catalogues.getByRole('textbox', { name: 'Catalogue URL' }).fill('https://catalogue.test/opds/root.xml');
  await catalogues.getByRole('button', { name: 'Add catalogue' }).click();
  await catalogues.getByRole('group', { name: 'Two Books' }).getByRole('button', { name: 'Two Books' }).click();
  const browser = page.getByRole('dialog').filter({ has: page.getByRole('button', { name: 'Close catalogue' }) });
  await browser.getByRole('region', { name: 'Entries' }).getByRole('group', { name: B }).getByRole('button', { name: 'Get' }).click();
  await expect(browser.getByRole('status')).toHaveText('Added to your library.', { timeout: 30000 });
  await browser.getByRole('button', { name: 'Close catalogue' }).click();
  await expect(cards(page)).toHaveCount(2);
  await openBook(page, B);
  await expect(indicator(page)).toHaveText(/^Beta Chapter 1/);
  await openContents(page);
  await expect(contents(page).getByRole('tab')).toHaveText(['Contents', 'Bookmarks']);
  await expect(contentsRows(page, 'Contents')).toHaveCount(2);
  await closeContents(page);
  await expect(jumpBack(page)).toBeHidden();
  await expectBarFollows(page, true);
  expect(errors).toEqual([]);
});

/** A record's chunks (the format of src/chunk.bats: QREC, a kind and two versions, then length, tag, data, CRC), minus those that name the
    book's place in this library: its ids (BOOK) and its position (ORDR) */
function chunksOf(hex) {
  const bytes = Buffer.from(hex, 'hex');
  const chunks = {};
  let at = 7;
  while (at + 8 <= bytes.length) {
    const length = bytes.readUInt32LE(at);
    const tag = bytes.toString('latin1', at + 4, at + 8);
    chunks[tag] = bytes.subarray(at + 8, at + 8 + length).toString('hex');
    at += 8 + length + 4;
  }
  return chunks;
}

/** What is kept of the book whose id is `id`: every key that holds it, its record by chunks without its position in the library */
function keptOf(stored, id) {
  const kept = {};
  for (const [key, value] of Object.entries(stored)) {
    const name = /^bats\/kv "(.*)"$/.exec(key)?.[1];
    if (name === undefined || !name.includes(id)) continue;
    if (name.startsWith('library/book/')) {
      const { ORDR, ...rest } = chunksOf(value);
      kept[name] = rest;
    } else kept[name] = value;
  }
  return kept;
}

/** Opens a book, and reloads, waiting for the sync the app makes as it opens (in the android project) to end, so what it writes is
    written before the records are taken; the app comes back to the book */
async function openSettled(page, title) {
  await openBook(page, title);
  await reloadSettled(page);
  await expect(indicator(page)).toContainText('in chapter');
}

test('B opened after A is the same as B opened first, in everything it keeps', async ({ page, browser }) => {
  // one file for B in both profiles, so its id is the same
  const betaFile = epubFile(twoBooks.beta.opts);
  // B first, in a profile of its own (the reader's Columns setting made there as in A's)
  const fresh = await browser.newContext(page.context()._options);
  await googleStubbed(fresh);
  if (onAndroid(test.info())) await fresh.addInitScript(androidApp);
  const lone = await fresh.newPage();
  if (onAndroid(test.info())) await androidInsets(lone);
  await fixedClock(fresh);
  await lone.goto('/');
  await importFiles(lone, [betaFile], 1);
  await openSettled(lone, B);
  await columnsTwo(lone);
  const first = await capture(lone);
  await fresh.close();

  await fixedClock(page.context());
  await page.goto('/');
  await importFiles(page, [epubFile(twoBooks.alpha.opts), betaFile], 2);
  await useAlpha(page, { narrate: false });
  await toLibrary(page);
  await openSettled(page, B);
  const after = await capture(page);
  // what B shows
  expect(after.page).toBe(first.page);
  expect(after.screen.equals(first.screen)).toBe(true);
  // what is kept of B: the same, but its place in the library's order
  const id = Object.keys(first.stored).map(key => /library\/book\/([0-9a-f]+)/.exec(key)?.[1]).find(Boolean);
  expect(Object.keys(keptOf(first.stored, id)).length).toBeGreaterThan(3);
  expect(keptOf(after.stored, id)).toEqual(keptOf(first.stored, id));
  // and the reader's settings are the same too
  expect(after.stored['bats/kv "set"']).toEqual(first.stored['bats/kv "set"']);
});
