// Pathological structure stays responsive (#423). KOReader's notes on slow
// books name the shapes this walks: a table cell holding many paragraphs
// that spans dozens of pages (laid out on every turn), a single-file book
// (the whole text in one spine item), converters that nest a thousand
// elements, ten thousand short paragraphs and one paragraph of a megabyte
// without a space. Each is a small book made by code
// (e2e/pathological-books.js, each checked by epubcheck), read paged, scrolled
// and in two columns.
//
// Budgets are relative, as page-turn.spec.js's are (#307): a turn is
// measured against an instant turn, and a pathological chapter against a
// plain chapter of the same length, both in the same page, so a slower
// machine slows both. Absolute times are only ever printed. The stall watch
// (e2e/stall-capture.js) is on in every test, so a page that stops
// answering explains itself and fails the test.

import { test, expect } from './fixtures.js';
import {
  start, readBook, place, indicator, bookPage, showChrome, dialog, openReadingSettings, readingSettings,
  selectionButton, marks, epubFile, importFiles, toLibrary, control, cards, card,
} from './helpers.js';
import { pageMargins } from './page-margins.js';
import {
  tableBook, novelBook, nestedBook, shortParagraphsBook, unbrokenBook, singleFileChapter, plainChapter, book,
  TAIL_WORD, DEEP_WORD, NEEDLE_WORD, CELL_PARAGRAPHS, SHORT_PARAGRAPHS, NOVEL_BYTES, NOVEL_SMALL_BYTES,
} from './pathological-books.js';

const MODES = ['pages', 'scrolled', 'columns'];

const slow = expect.configure({ timeout: 240000 });

/** How much of a long book a window shows as many columns as the desktop's
    1024 x 768 does: its area against that. Chrome's cost of drawing a page
    of a paged chapter grows with its columns times its boxes (a second a
    page at 1800 columns of 5 MB, measured in e2e below), and a phone fits
    a third of the desktop's text on a page, so the same 5 MB has three
    times the columns there and a turn takes seconds; the books are sized
    to the window so that every project walks the same number of columns */
const sizedTo = (page) => {
  const view = page.viewportSize();
  return Math.min(1, (view.width * view.height) / (1024 * 768));
};

// Playwright's trace and screenshots snapshot the whole DOM at every action
// (its snapshotter walks every node, 2 to 3 s on a chapter of 30,000), which
// is the harness's cost, not the app's, and made the long chapters' steps
// time out; the stall watch (e2e/stall-capture.js) is unaffected
test.use({ trace: 'off', screenshot: 'off' });

/** The reading arrangement: Pages (the default), Scroll, or Two columns */
async function arrange(page, mode) {
  await openReadingSettings(page, 'Page');
  const started = Date.now();
  if (mode === 'pages') {
    // one page a screen, whatever the window (a wide one shows a spread at Auto)
    await readingSettings(page).getByRole('group', { name: 'Pages on screen' }).getByRole('button', { name: 'One', exact: true }).click();
  } else if (mode === 'scrolled') {
    await readingSettings(page).getByRole('group', { name: 'Layout' }).getByRole('button', { name: 'Scroll', exact: true }).click();
  } else {
    await readingSettings(page).getByRole('group', { name: 'Pages on screen' }).getByRole('button', { name: 'Two', exact: true }).click();
  }
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
  await expect.poll(() => indicator(page).textContent()).toMatch(mode === 'scrolled' ? /% of chapter/ : mode === 'columns' ? /pages 1–2 of/ : / page 1 of/);
  return Date.now() - started;
}

/** Chrome's own time, in this window and arrangement, to lay out and draw
    the page's DOM: a copy of it, with the page's styles (the stylesheet
    applies to a copy as to the page), put beside the page, laid out, drawn
    for two frames, and removed. A hosted runner that is slow is slow for
    the copy too, so what the app takes is held to a multiple of it */
async function bareFrameMs(page) {
  return page.evaluate(async () => {
    const doc = document.querySelector('[role=document][aria-label=Page]');
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

/** The open budget: what the app takes to show a chapter, or to change
    how it is laid out, is at most this many times Chrome's own time to
    lay out and draw that DOM, and a second more for what is not layout
    (the archive read, parsed and put in the DOM: it has no window to be
    slow in). Three, by the user's measure of a chapter that opens as
    the browser would open the same page (#423) */
const OPEN_TIMES = 3;
const OPEN_ALLOWANCE_MS = 1000;
async function expectOpenBudget(page, notes) {
  // Chrome's time is taken last, after the turns the test times: the copy
  // it makes is garbage afterwards, and a collection must not fall in a turn
  const base = await bareFrameMs(page);
  for (const [what, tookMs] of notes) {
    const log = `${what}: ${Math.round(tookMs)} ms against Chrome's ${Math.round(base)} ms to lay out and draw the same DOM`;
    console.log(log);
    expect.soft(tookMs, log).toBeLessThanOrEqual(OPEN_TIMES * base + OPEN_ALLOWANCE_MS);
  }
}

/** Imports a book and opens it from its card: the time from the tap to
    the chapter's indicator, in ms */
async function openTimed(page, opts) {
  await importFiles(page, [epubFile(opts)], (await cards(page).count()) + 1);
  const started = Date.now();
  await card(page, opts.title).click();
  await slow(bookPage(page)).toBeVisible();
  await slow(indicator(page)).toContainText('in chapter');
  return Date.now() - started;
}

/** Where the reader is, in one shape for every arrangement: the chapter,
    how far into it as a fraction of 0 to 1, and whether it is at the end */
async function where(page) {
  const text = (await indicator(page).textContent()).trim();
  const percent = /(\d+)% of chapter$/.exec(text);
  // scrolled, the percentage is whole: how far the page is scrolled is finer
  if (percent) {
    const fine = await bookPage(page).evaluate(doc => doc.scrollTop / Math.max(1, doc.scrollHeight - doc.clientHeight));
    return { text, fraction: fine, percent: +percent[1], end: +percent[1] === 100 };
  }
  const here = await place(page);
  return { text, ...here, fraction: here.t > 1 ? (here.p - 1) / (here.t - 1) : 1, end: here.p === here.t };
}

/** How many screens the chapter fills: its pages, or scrolled its height
    in screenfuls */
const screens = async (page) => {
  const here = await where(page);
  if (here.t) return here.t;
  return bookPage(page).evaluate(doc => Math.ceil(doc.scrollHeight / doc.clientHeight));
};

/** Waits for the page's layout to hold still: the same place and count for
    300 ms (a chapter's pages are counted again as it is shown, for 3 s) */
async function settled(page) {
  let last = '';
  await expect.poll(async () => {
    const now = (await indicator(page).textContent()).trim();
    const same = now === last;
    last = now;
    await page.waitForTimeout(300);
    return same;
  }, { timeout: 30000 }).toBe(true);
}

// How long, in ms, from a key's press to the first frame drawn after it
// (page-turn.spec.js's measure)
const watchFirstFrame = (page) => page.evaluate(() => {
  window.firstFrame = new Promise((resolve) => {
    const onKey = () => {
      window.removeEventListener('keydown', onKey, true);
      const pressed = performance.now();
      requestAnimationFrame(() => resolve(performance.now() - pressed));
      // the app's own part: what its handlers run before the event reaches
      // the window again, in the bubble phase (the browser's frame follows)
      window.addEventListener('keydown', () => { window.keyScript = performance.now() - pressed; }, { once: true });
    };
    window.addEventListener('keydown', onKey, true);
  });
});

/** Six turns, on and back, from the key to the first frame, sorted; each
    carries the time the app's own script took, as `scripts`, sorted */
async function turnTimes(page) {
  const times = [];
  const scripts = [];
  for (let i = 0; i < 6; i++) {
    const before = (await where(page)).fraction;
    await watchFirstFrame(page);
    await page.keyboard.press(i % 2 ? 'ArrowLeft' : 'ArrowRight');
    times.push(await page.evaluate(() => window.firstFrame));
    scripts.push(await page.evaluate(() => window.keyScript));
    await expect.poll(async () => (await where(page)).fraction).not.toBe(before);
  }
  return Object.assign(times.sort((x, y) => x - y), { scripts: scripts.sort((x, y) => x - y) });
}
const ms = (times) => times.map(Math.round).join(', ');

/** How much later than an instant turn an animated one may come: 30 ms
    (page-turn.spec.js's margin), or a quarter of it where the browser's own
    frame takes 150 ms or more, which spreads by that much within one run
    (157 to 209 ms for six turns of the same chapter) */
const slack = (instant) => Math.max(30, instant * 0.25);

/** The middle turn of six, instant (less motion) and animated, in this page */
async function turnBudget(page) {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  const instant = await turnTimes(page);
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  const animated = await turnTimes(page);
  return { instant, animated };
}


/** What the footer's readout says at a place (reader.bats' _put_readout:
    pages left in the chapter by default, in screens, a spread's two pages
    each; scrolled, how far) */
const footerReadout = (mode, now) => {
  if (mode === 'scrolled') return `${now.percent}% of chapter`;
  const left = now.t - now.p;
  const pages = mode === 'columns' ? 2 * left : left;
  return left === 0 ? 'last page in chapter' : pages === 1 ? '1 page left in chapter' : `${pages} pages left in chapter`;
};

/** The running footer's two readouts, which show while the bars are down */
const footerOf = (page) => page.evaluate(() => ({
  readout: document.getElementById('footer-readout').textContent.replace(/^\s*·\s*/, '').trim(),
  book: document.getElementById('footer-book').textContent.replace(/^\s*·\s*/, '').trim(),
}));

/** The bars put down, so the running footer shows (a tap on the page's
    middle brings them up and puts them down) */
async function barsDown(page) {
  const footer = page.locator('#footer');
  if (!(await footer.isVisible())) {
    const box = await bookPage(page).boundingBox();
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  }
  await expect(footer).toBeVisible();
}

/** Milliseconds from act() to the predicate (source run in the page)
    holding, polled every few ms; the time is printed, never asserted alone */
async function elapsedUntil(page, act, predicate, arg = null, limit = 40000) {
  const started = Date.now();
  await act();
  await page.waitForFunction(predicate, arg, { polling: 10, timeout: limit })
    .catch(() => { throw new Error(`the page did not get there within ${limit / 1000} s: ${predicate.toString().slice(0, 120)}`); });
  return Date.now() - started;
}

/** The index n of the first paragraph tagged "<tag> n" that shows on the
    page, else null */
const firstTagged = (page, tag) => bookPage(page).evaluate((doc, tag) => {
  const c = doc.getBoundingClientRect();
  for (const p of doc.querySelectorAll('p')) {
    const m = new RegExp('^' + tag + ' (\\d+) ').exec(p.textContent.slice(0, 40));
    if (m && [...p.getClientRects()].some(r => r.width > 0 && r.right > c.left && r.left < c.right && r.bottom > c.top && r.top < c.bottom)) return +m[1];
  }
  return null;
}, tag);

test.describe('a table cell over many pages', () => {
  for (const mode of MODES) {
    test(`${mode}: turns across the cell cost what a plain chapter's do, and every page has its place and footer`, async ({ page }) => {
      test.setTimeout(85000);
      const errors = await start(page);
      await readBook(page, tableBook());
      await arrange(page, mode);
      await settled(page);
      // the plain chapter first (chapter 1): its turns are the yardstick
      const plain = await turnBudget(page);
      await page.keyboard.press('End');
      await expect.poll(async () => (await where(page)).end).toBe(true);
      const plainPages = await screens(page);
      await page.keyboard.press('ArrowRight');
      await expect.poll(async () => (await indicator(page).textContent())).toContain('Chapter 2');
      await settled(page);
      const cell = await turnBudget(page);
      const log = `${mode}: plain animated ${ms(plain.animated)} instant ${ms(plain.instant)}; cell animated ${ms(cell.animated)} instant ${ms(cell.instant)}`;
      console.log(log);
      // the middle of six (one slow frame moves neither): across the cell a
      // turn costs what a plain chapter's does, and the animated one what
      // the instant one does, within the margin page-turn.spec.js allows
      expect.soft(cell.instant[2], log).toBeLessThanOrEqual(plain.instant[2] + 30);
      expect.soft(cell.animated[2], log).toBeLessThanOrEqual(plain.animated[2] + 30);
      expect.soft(cell.animated[2], log).toBeLessThanOrEqual(cell.instant[2] + slack(cell.instant[2]));

      // a table is a scroll container no taller than a page (#413), so the
      // cell does not spread over dozens of pages, each laid out again at
      // every turn: the table is one box on one page, and its rows past
      // the page's foot are reached by scrolling the table. (Until #413 a
      // cell was one unbreakable box of a hundred pages or more, which is
      // what made these turns slow; this test then asserted the chapter
      // filled about as many pages as the plain one. That count is no
      // longer the right measure, since the cell no longer takes the pages.)
      const cellPages = await screens(page);
      expect(cellPages, `the chapter with the table is a few pages, not the cell's hundred (plain chapter ${plainPages})`).toBeLessThan(plainPages);
      const cellBox = await bookPage(page).evaluate(doc => {
        const table = doc.querySelector('table');
        return { scrollHeight: table.scrollHeight, clientHeight: table.clientHeight };
      });
      expect(cellBox.scrollHeight, 'the cell holds more than a page, scrolled inside the table').toBeGreaterThan(cellBox.clientHeight * 3);

      // every page across the cell: the place, the footer and the text
      await page.emulateMedia({ reducedMotion: 'reduce' });
      await page.keyboard.press('Home');
      await expect.poll(async () => (await where(page)).fraction).toBe(0);
      await barsDown(page);
      const first = await where(page);
      let lastFraction = -1, lastBook = -1, lastTag = -1, pages = 0;
      for (let k = 0; k < 400; k++) {
        const now = await where(page);
        const foot = await footerOf(page);
        expect(foot.readout, `footer at ${now.text}`).toBe(footerReadout(mode, now));
        // the place: one screen on each turn
        if (mode === 'pages') expect(now.p, `page after ${k} turns`).toBe(first.p + k);
        expect(now.fraction, `page ${k}`).toBeGreaterThanOrEqual(lastFraction);
        const percent = +/^(\d+|<1)%/.exec(foot.book)[1].replace('<1', '0');
        expect(percent, `book percent at ${now.text}`).toBeGreaterThanOrEqual(lastBook);
        lastBook = percent;
        // the text: the cell's paragraphs come in order
        const tag = await firstTagged(page, 'Cell');
        if (tag !== null) {
          expect(tag, `first paragraph on page ${k}`).toBeGreaterThanOrEqual(lastTag);
          lastTag = tag;
        }
        // the margins: the text clear of the footer, the footer of the inset
        const margins = await pageMargins(page);
        if (margins) expect(margins.short, `margins on page ${k}`).toEqual([]);
        lastFraction = now.fraction;
        pages++;
        if (now.end) break;
        await page.keyboard.press('ArrowRight');
        // scrolled, the percentage is whole and a screen may not change it: the scroll does
        await expect.poll(async () => (await where(page)).fraction).not.toBe(now.fraction);
      }
      expect((await where(page)).end, 'the end of the cell is reached').toBe(true);
      // the rest of the cell is reached by scrolling the table
      const lastInCell = await bookPage(page).evaluate((doc, last) => {
        const table = doc.querySelector('table');
        table.scrollTop = table.scrollHeight;
        const box = table.getBoundingClientRect();
        const paragraph = [...table.querySelectorAll('p')].find(p => p.textContent.startsWith(`Cell ${last} `));
        const at = paragraph.getBoundingClientRect();
        // its last line is in view (a paragraph can be taller than a phone's table)
        const reached = at.bottom <= box.bottom + 1 && at.bottom > box.top;
        return { reached, paragraph: [at.top, at.bottom], table: [box.top, box.bottom], scrolled: [table.scrollTop, table.scrollHeight, table.clientHeight] };
      }, CELL_PARAGRAPHS - 1);
      expect(lastInCell.reached, `the last paragraph of the cell is reached by scrolling the table: ${JSON.stringify(lastInCell)}`).toBe(true);
      console.log(`${mode}: ${pages} pages across the cell, the plain chapter ${plainPages}`);
      expect(errors).toEqual([]);
    });
  }
});

// ---- search, selection and speech, as the specs of those areas drive them ----

const searchPanel = page => dialog(page, 'Search in book');
const searchBar = page => page.getByRole('toolbar', { name: 'Search results' });

/** Searches the book for word: the panel's summary, once it has one */
async function searchFor(page, word) {
  await page.keyboard.press('/');
  const box = searchPanel(page).getByRole('searchbox', { name: 'Search in book' });
  await expect(box).toBeFocused();
  await box.fill(word);
  return searchPanel(page).getByRole('status');
}

/** Goes to the first result of the search just made, and waits for the
    match to be marked on the page */
async function goToResult(page) {
  await searchPanel(page).getByRole('region', { name: 'Results' }).getByRole('button').first().click();
  await expect(searchPanel(page)).toBeHidden();
  await expect.poll(async () => (await marks(page)).size).toBe(1);
}

/** Closes a search's result bar, back to reading */
async function closeSearch(page) {
  await searchBar(page).getByRole('button', { name: 'Close search' }).click();
  await expect(searchBar(page)).toBeHidden();
}

/** Selects the first characters of the last paragraph shown with its text
    starting `start` (the chapter's closing paragraph, after End) */
async function selectIn(page, start, length) {
  await bookPage(page).evaluate((doc, [start, length]) => {
    const p = [...doc.querySelectorAll('p')].find(e => e.textContent.startsWith(start));
    const walker = document.createTreeWalker(p, NodeFilter.SHOW_TEXT);
    const text = walker.nextNode();
    const range = document.createRange();
    range.setStart(text, 0);
    range.setEnd(text, length);
    const selection = getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }, [start, length]);
}

/** Speech that is recorded and ended by hand (reader.spec.js's) */
async function fakeSpeech(page) {
  await page.addInitScript(() => {
    window.spoken = [];
    window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
    const voices = [{ name: 'Reader', lang: 'en-US', voiceURI: 'reader-en', default: true }];
    const synth = {
      current: null,
      getVoices: () => voices,
      speak(u) { window.spoken.push({ text: u.text }); this.current = u; },
      cancel() { const u = this.current; this.current = null; if (u && u.onerror) u.onerror({ error: 'interrupted' }); },
      addEventListener() {},
    };
    Object.defineProperty(window, 'speechSynthesis', { value: synth });
    window.sentenceSpoken = () => { const u = synth.current; synth.current = null; if (u && u.onend) u.onend({}); };
  });
}
const spoken = page => page.evaluate(() => window.spoken.map(s => s.text));

// ---- a single-file book ----

/** Whether the page indicator says the end of the chapter (run in the page) */
const atEndOfChapter = () => {
  const text = document.getElementById('indicator-pages').textContent.trim();
  const across = /^(\d+)(?:–(\d+))? of (\d+) in chapter$/.exec(text);
  if (across) return +(across[2] || across[1]) === +across[3];
  const down = /^(\d+)% of chapter$/.exec(text);
  return !!down && +down[1] === 100;
};
const atStartOfChapter = () => {
  const text = document.getElementById('indicator-pages').textContent.trim();
  return /^1(?:–2)? of \d+ in chapter$/.test(text) || /^0% of chapter$/.test(text);
};

/** One highlight or search match is painted (run in the page) */
const oneMark = () => {
  let ranges = 0;
  for (const [, highlight] of CSS.highlights) ranges += highlight.size;
  return ranges === 1;
};

/** Milliseconds from a card's tap to the chapter's heading on the page */
const opened = (page, title, heading) => elapsedUntil(page,
  () => page.getByRole('region', { name: /^(Continue reading|Books)$/ }).getByRole('group').filter({ hasText: title }).first().click(),
  (heading) => {
    const doc = document.querySelector('[role=document][aria-label=Page]');
    return !!doc && doc.checkVisibility() && doc.textContent.startsWith(heading) && /chapter$/.test(document.getElementById('indicator-pages').textContent.trim());
  }, heading);

/** The operations a long chapter slows, on the book open at its start, in
    ms: a turn (first frame, instant and animated), a jump to the end, a
    search for the word on the last page (found, then gone to) and a
    highlight near the end */
async function operations(page) {
  const turns = await turnBudget(page);
  const end = await elapsedUntil(page, () => page.keyboard.press('End'), atEndOfChapter);
  // the closing paragraph is on the page, whatever the arrangement
  await expect.poll(() => bookPage(page).evaluate(doc => doc.textContent.includes('last Zanzibarquartz') && [...doc.querySelectorAll('p')].some(p => p.textContent.includes('last Zanzibarquartz') && [...p.getClientRects()].some(r => { const c = doc.getBoundingClientRect(); return r.right > c.left && r.left < c.right && r.bottom > c.top && r.top < c.bottom; })))).toBe(true);
  await page.keyboard.press('Home');
  await page.waitForFunction(atStartOfChapter, null, { polling: 10, timeout: 30000 });
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  const summary = await (async () => {
    const started = Date.now();
    const status = await searchFor(page, TAIL_WORD);
    await expect(status).toHaveText('1 result');
    return Date.now() - started;
  })();
  const found = await elapsedUntil(page, () => goToResult(page).catch(() => {}), oneMark);
  await expect.poll(async () => (await marks(page)).text).toBe(TAIL_WORD);
  await expect.poll(async () => (await where(page)).end).toBe(true);
  await closeSearch(page);
  await page.keyboard.press('End');
  await page.waitForFunction(atEndOfChapter, null, { polling: 10, timeout: 30000 });
  await selectIn(page, 'Novel last', 5);
  await expect(selectionButton(page, 'Highlight')).toBeVisible();
  const highlight = await elapsedUntil(page, () => selectionButton(page, 'Highlight').click(), oneMark);
  return { turns, end, summary, found, highlight };
}

test.describe('a single-file book of 5 MB', () => {
  // The yardstick is the same book's shape at 300 KB (page-turn.spec.js's
  // chapter): the same operations, in the same page, timed the same way. A
  // 5 MB chapter holds about 17 times the text, so an operation that costs
  // time in proportion to the text stays within 17 times the small one's;
  // one that costs more (a walk repeated for each page, say) is what
  // slows "everything that touches the chapter". Twice that is allowed,
  // for the costs that do not grow with the text and the machine's noise
  // (a quadratic cost is 17 times that again), and the small one's time
  // counts as at least 150 ms, the grain of the steps that wait.
  const least = 150;
  const smallBook = () => book('Small Novel', [singleFileChapter(NOVEL_SMALL_BYTES, 'Novel'), plainChapter(3, 'After', false)]);

  for (const mode of MODES) {
    test(`${mode}: opening, the first turn, a jump to the end, a search and a highlight each cost in proportion to the text`, async ({ page }) => {
      // one more layout and frame of the 5 MB chapter, for the open budget
      test.setTimeout(120000);
      const errors = await start(page);
      // the arrangement is chosen on the small book, and kept for the big one
      await readBook(page, smallBook());
      await arrange(page, mode);
      await settled(page);
      await toLibrary(page);
      const smallOpen = await opened(page, 'Small Novel', 'Novel chapter');
      await settled(page);
      const small = await operations(page);
      await toLibrary(page);
      const importStarted = Date.now();
      const bigBytes = Math.round(NOVEL_BYTES * sizedTo(page));
      const ratio = 2 * bigBytes / NOVEL_SMALL_BYTES;
      await importFiles(page, [epubFile(novelBook(bigBytes))], 2);
      const importMs = Date.now() - importStarted;
      const bigOpen = await opened(page, 'Single File', 'Novel chapter');
      await settled(page);
      const big = await operations(page);
      const log = `${mode}: import ${importMs} ms; open ${smallOpen} -> ${bigOpen}; end ${small.end} -> ${big.end}; ` +
        `search ${small.summary} -> ${big.summary}, go ${small.found} -> ${big.found}; highlight ${small.highlight} -> ${big.highlight}; ` +
        `turns animated ${ms(small.turns.animated)} -> ${ms(big.turns.animated)}, instant ${ms(small.turns.instant)} -> ${ms(big.turns.instant)}`;
      console.log(log);
      // Paged, Chrome's own cost of drawing a page of this chapter is not
      // in proportion to the text either (below: a second a page at 5 MB,
      // against about 10 ms at 300 KB: its columns times its boxes), and the
      // operations draw a few pages (a jump, a mark), so each is allowed
      // two of them, as this run measured one
      const drawn = mode === 'scrolled' ? 0 : 2 * big.turns.instant[2];
      const within = (what, now, before) => expect.soft(now, `${what}: ${log}`).toBeLessThanOrEqual(Math.max(before, least) * ratio + drawn);
      within('opening', bigOpen, smallOpen);
      within('the jump to the end', big.end, small.end);
      within('the search', big.summary, small.summary);
      within('going to the result', big.found, small.found);
      within('the highlight', big.highlight, small.highlight);
      // a turn: as soon as an instant one, as page-turn.spec.js holds it
      expect.soft(big.turns.animated[2], log).toBeLessThanOrEqual(big.turns.instant[2] + slack(big.turns.instant[2]));
      await expectOpenBudget(page, [['opening the 5 MB chapter', bigOpen]]);
      // and as soon as the small chapter's. Scrolled, the first frame is
      // compared. Paged (a scroll across 1800 columns), Chrome itself takes
      // about a second to draw the next page of this chapter whatever the
      // app does: `scrollLeft += width` alone, in a page with no app script
      // and its pointer events off, took 1.0 to 1.1 s four times in a row
      // here (measured with DevTools; the same chapter scrolled down takes
      // 30 ms), and no CSS tried (contain, isolation, will-change,
      // overflow, max-width, content-visibility) changed it. So what is
      // held to the small chapter's within 30 ms there is the app's own
      // script, which was 200 to 280 ms on this chapter before #423 and is
      // 20 to 30 ms now; the first frame is printed.
      // (scrolled, a trace of a key on this chapter on the desktop: 19 ms of
      // the app's script, then 37 ms of Chrome's PrePaint of its 30,000
      // boxes and 27 ms of paint, which grow with the chapter: the margin is
      // the 30 ms of the script's and the same again for the browser's)
      if (mode === 'scrolled') expect.soft(big.turns.instant[2], log).toBeLessThanOrEqual(small.turns.instant[2] + 60);
      else expect.soft(big.turns.instant.scripts[2], log).toBeLessThanOrEqual(small.turns.instant.scripts[2] + 30);
      expect(errors).toEqual([]);
    });
  }
});

// ---- deep nesting ----

test.describe('a thousand nested elements', () => {
  // render, search and the script read aloud are each a walk of the tree
  // (CLAUDE.md names them): a recursion that goes one frame a level, with
  // a thousand levels in a paragraph, would blow the wasm stack and leave
  // the page with an error, or with no chapter at all
  for (const mode of MODES) {
    test(`${mode}: divs, spans and both are shown, found by search and read aloud`, async ({ page }) => {
      test.setTimeout(85000);
      await fakeSpeech(page);
      const errors = await start(page);
      await readBook(page, nestedBook());
      await arrange(page, mode);
      await settled(page);
      // shown: chapter 1's heading and its last paragraph are in the document
      await expect(bookPage(page)).toContainText('Divs chapter');
      expect(await bookPage(page).evaluate(doc => doc.querySelectorAll('div div div div div').length)).toBeGreaterThan(500);
      // searched: the word at the bottom of each is found, in all three chapters
      const summary = await searchFor(page, DEEP_WORD);
      await expect(summary).toHaveText('3 results');
      await goToResult(page);
      for (const chapter of [1, 2, 3]) {
        await expect(indicator(page)).toContainText(`Chapter ${chapter}`);
        await expect.poll(async () => (await marks(page)).text).toBe(DEEP_WORD);
        // read aloud, from the page's first sentence: the sentence holding
        // the word is reached
        await closeSearch(page);
        await showChrome(page);
        await control(page, 'Read aloud').click();
        await expect(control(page, 'Read aloud')).toHaveAttribute('aria-pressed', 'true');
        let said = [];
        for (let k = 0; k < 12 && !said.some(text => text.includes(DEEP_WORD)); k++) {
          await expect.poll(async () => (await spoken(page)).length).toBeGreaterThan(k);
          said = await spoken(page);
          await page.evaluate(() => window.sentenceSpoken());
        }
        expect(said.some(text => text.includes(DEEP_WORD)), `chapter ${chapter} read aloud: ${JSON.stringify(said)}`).toBe(true);
        await showChrome(page);
        await control(page, 'Read aloud').click();
        await expect(control(page, 'Read aloud')).toHaveAttribute('aria-pressed', 'false');
        await page.evaluate(() => { window.spoken.length = 0; });
        if (chapter < 3) {
          // on to the next result, which is in the next chapter
          await searchFor(page, DEEP_WORD);
          await searchPanel(page).getByRole('region', { name: 'Results' }).getByRole('button').nth(chapter).click();
          await expect(searchPanel(page)).toBeHidden();
          await expect.poll(async () => (await marks(page)).size).toBe(1);
        }
      }
      expect(errors).toEqual([]);
    });
  }
});

// ---- a chapter of ten thousand paragraphs, and one of a megabyte without a space ----

/** How many screens the chapter fills, once it fills more than one */
async function screensOf(page) {
  await expect.poll(() => screens(page), { message: 'the chapter fills more than one screen: text that has no place to break must be broken, or the rest of it is out of reach' }).toBeGreaterThan(1);
  return screens(page);
}

test.describe('ten thousand short paragraphs in one chapter', () => {
  for (const mode of MODES) {
    test(`${mode}: shown, paged, turned within budget and searchable`, async ({ page }) => {
      test.setTimeout(85000);
      const errors = await start(page);
      const openMs = await openTimed(page, shortParagraphsBook());
      const arrangeMs = await arrange(page, mode);
      await settled(page);
      // shown and paged: the first paragraphs are on the page and the chapter fills many screens
      await expect(bookPage(page)).toContainText('Short chapter');
      expect(await screensOf(page), 'screens').toBeGreaterThan(mode === 'scrolled' ? 50 : 100);
      const turns = await turnBudget(page);
      const log = `${mode}: turns animated ${ms(turns.animated)} instant ${ms(turns.instant)}`;
      console.log(log);
      expect.soft(turns.animated[2], log).toBeLessThanOrEqual(turns.instant[2] + slack(turns.instant[2]));
      // searched: a paragraph in the middle, and the closing one
      const middle = await searchFor(page, `Short ${SHORT_PARAGRAPHS / 2}`);
      await expect(middle).toHaveText('1 result');
      await goToResult(page);
      expect((await marks(page)).text).toBe(`Short ${SHORT_PARAGRAPHS / 2}`);
      const half = (await where(page)).fraction;
      expect(half, `the middle paragraph is about half way: ${(await where(page)).text}`).toBeGreaterThan(0.4);
      expect(half).toBeLessThan(0.6);
      await closeSearch(page);
      await searchFor(page, TAIL_WORD);
      await expect(searchPanel(page).getByRole('status')).toHaveText('1 result');
      await goToResult(page);
      expect((await marks(page)).text).toBe(TAIL_WORD);
      await expect.poll(async () => (await where(page)).end).toBe(true);
      await expectOpenBudget(page, [['opening', openMs], [`choosing ${mode}`, arrangeMs]]);
      expect(errors).toEqual([]);
    });
  }
});

test.describe('one paragraph of a megabyte without a space', () => {
  for (const mode of MODES) {
    test(`${mode}: shown, paged, turned within budget and searchable`, async ({ page }) => {
      // a phone fits a third of the text a page, so a megabyte is three
      // times the columns and Chrome takes about 2 s to draw each page of it
      // (six turns instant and six animated, then the search): twice the time
      test.setTimeout(sizedTo(page) < 0.5 ? 420000 : 300000);
      const errors = await start(page);
      // a hosted runner takes a minute to lay out a megabyte of one word:
      // the waits of this test are as long as the test itself
      const openMs = await openTimed(page, unbrokenBook());
      const arrangeMs = await arrange(page, mode);
      await settled(page);
      await slow(bookPage(page)).toContainText('Unbroken chapter');
      // the run is broken to the page's width, as a line with no place to
      // break is, so it fills the pages a megabyte of letters should
      expect(await screensOf(page), 'screens').toBeGreaterThan(mode === 'scrolled' ? 100 : 200);
      const turns = await turnBudget(page);
      const log = `${mode}: turns animated ${ms(turns.animated)} instant ${ms(turns.instant)}`;
      console.log(log);
      expect.soft(turns.animated[2], log).toBeLessThanOrEqual(turns.instant[2] + slack(turns.instant[2]));
      // searched: the word in the middle of the run, which is half way through the chapter
      const found = await searchFor(page, NEEDLE_WORD);
      await slow(found).toHaveText('1 result');
      await goToResult(page);
      expect((await marks(page)).text).toBe(NEEDLE_WORD);
      const half = (await where(page)).fraction;
      expect(half, `half way: ${(await where(page)).text}`).toBeGreaterThan(0.4);
      expect(half).toBeLessThan(0.6);
      await closeSearch(page);
      // and to the end
      await page.keyboard.press('End');
      await slow.poll(async () => (await where(page)).end).toBe(true);
      await slow(bookPage(page)).toContainText(TAIL_WORD);
      await expectOpenBudget(page, [['opening', openMs], [`choosing ${mode}`, arrangeMs]]);
      expect(errors).toEqual([]);
    });
  }
});
