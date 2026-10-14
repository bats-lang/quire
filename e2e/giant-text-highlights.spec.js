// A highlight in a text node of 64 KiB or more (#470). Such a text is drawn as
// pieces (class run, one content node each), cut by _text_cut after the last
// white space in a piece's last 512 bytes. A highlight is stored as a content
// node and a UTF-16 offset in that node's text, so it is stored against the
// piece it was made on, and the cut is a function of the text alone: render,
// search and read-aloud cut it alike. These tests make highlights at the end of
// a piece, at the start of the next, across a cut and in a third piece, in the
// three arrangements (pages, scrolled, two columns), and require the page to
// paint exactly the text that was selected after the chapter is shown again,
// after a backup is restored on another device and after a sync. The words
// carry accents and an emoji (two UTF-16 units, four bytes), so a byte offset
// taken for a unit one would move a mark.
//
// Decided (issue 470) by what the stored offset is relative to: the piece's
// text, in UTF-16 units (bridge's get_selection_range gives offsets into the
// text of the element with the id, which is the piece), so a stored place is
// exact for the cut it was made with. A cut is part of the format of a
// stored place, so it is not changed without a version of the record: the
// last test restores places stored by the build that made these cuts (GOLDEN,
// with the words each selected) and they must paint those words, so a changed
// cut fails here and not in a reader's book.

import { test, expect } from './fixtures.js';
import { writeFileSync } from 'node:fs';
import {
  start, epubFile, importFiles, card, toLibrary, reload, bookPage, dialog, marks, selectionButton,
  librarySettings, settingsButton, restoreInput, exportedBackup, openReadingSettings, readingSettings, indicator,
} from './helpers.js';
import { stores, NOON, minutesLater, hiddenSync, unexpected, painted } from './sync-devices.js';

const MODES = ['pages', 'scrolled', 'columns'];
const WORDS = 36000;

/** Word i: w and five digits, with an accent or an emoji after most */
const word = i => `w${String(i).padStart(5, '0')}${['é', '😀', '', 'ü✓'][i % 4]}`;
const giantText = () => Array.from({ length: WORDS }, (_, i) => word(i)).join(' ');

const giantBook = {
  title: 'Giant Text', author: 'Cuts', storeChapters: false,
  rawChapters: [{ body: `<h1>Giant chapter</h1><p>${giantText()}</p><p>Closing paragraph.</p>` }],
  toc: [{ label: 'Chapter 1', href: 'chapter1.xhtml' }],
};

/** The reading arrangement: Pages, Scroll, or Two columns */
async function arrange(page, mode) {
  await openReadingSettings(page, 'Page');
  if (mode === 'pages') {
    await readingSettings(page).getByRole('group', { name: 'Pages on screen' }).getByRole('button', { name: 'One', exact: true }).click();
  } else if (mode === 'scrolled') {
    await readingSettings(page).getByRole('group', { name: 'Layout' }).getByRole('button', { name: 'Scroll', exact: true }).click();
  } else {
    await readingSettings(page).getByRole('group', { name: 'Pages on screen' }).getByRole('button', { name: 'Two', exact: true }).click();
  }
  await page.keyboard.press('Escape');
  await expect(page.locator('#typography-panel')).toHaveAttribute('data-hide', '1');
  await expect(readingSettings(page)).toBeHidden();
  await expect.poll(() => indicator(page).textContent()).toMatch(mode === 'scrolled' ? /% of chapter/ : mode === 'columns' ? /pages 1–2 of/ : / page 1 of/);
}

/** A book opened from the library, whatever the arrangement (scrolled, the
    indicator counts a chapter in percent, not pages) */
async function openBook(page, title) {
  await card(page, title).click();
  await expect(bookPage(page)).toBeVisible();
  await expect(indicator(page)).toContainText(/ page \d|pages \d|% of chapter/);
}

const searchPanel = page => dialog(page, 'Search in book');
const searchBar = page => page.getByRole('toolbar', { name: 'Search results' });

/** Brings the word onto the page: searched for, and gone to */
async function goTo(page, target) {
  await page.keyboard.press('/');
  const box = searchPanel(page).getByRole('searchbox', { name: 'Search in book' });
  await expect(box).toBeFocused();
  await box.fill(target);
  await expect(searchPanel(page).getByRole('status')).toHaveText('1 result');
  await searchPanel(page).getByRole('region', { name: 'Results' }).getByRole('button').first().click();
  await expect(searchPanel(page)).toBeHidden();
  await expect.poll(async () => (await marks(page)).size).toBe(expectedMarks.count + 1);
  await searchBar(page).getByRole('button', { name: 'Close search' }).click();
  await expect(searchBar(page)).toBeHidden();
  // the search's own mark is gone, so the marks left are highlights
  await expect.poll(async () => (await marks(page)).size).toBe(await expectedMarks.count);
}
const expectedMarks = { count: 0 };

/** Selects from the start of the number first to the end of the number last;
    the text selected, as the page's Range gives it */
async function selectWords(page, first, last) {
  return page.evaluate(([from, to]) => {
    const owner = document.querySelector('[role=document][aria-label=Page] p');
    const find = target => {
      const walker = document.createTreeWalker(owner, NodeFilter.SHOW_TEXT);
      for (let t = walker.nextNode(); t; t = walker.nextNode()) {
        const at = t.data.indexOf(target);
        if (at >= 0) return [t, at];
      }
      throw new Error(`${target} is not in the paragraph`);
    };
    const [startNode, startAt] = find(from);
    const [endNode, endAt] = find(to);
    const range = document.createRange();
    range.setStart(startNode, startAt);
    range.setEnd(endNode, endAt + to.length);
    const selection = getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    return range.toString();
  }, [first, last]);
}

/** The first and last numbers of each piece of the giant paragraph, and how many pieces */
async function pieces(page) {
  return page.evaluate(() => {
    const owner = document.querySelector('[role=document][aria-label=Page] p');
    return [...owner.querySelectorAll(':scope > .run')].map(run => {
      const numbers = run.textContent.match(/w\d{5}/g);
      return { first: numbers.slice(0, 3), last: numbers.slice(-3), bytes: new TextEncoder().encode(run.textContent).length };
    });
  });
}

/** The highlights the test makes, from the cuts the page has */
function targets(cuts) {
  const [a, b, c] = cuts;
  return [
    { name: 'the end of the first piece', from: a.last[1], to: a.last[2] },
    { name: 'the start of the second piece', from: b.first[0], to: b.first[1] },
    { name: 'across the second cut', from: b.last[1], to: c.first[1] },
    { name: 'inside the third piece', from: c.first[2], to: 'w' + String(Number(c.first[2].slice(1)) + 3).padStart(5, '0') },
  ];
}

async function highlightAll(page, cuts) {
  const quotes = [];
  expectedMarks.count = 0;
  for (const target of targets(cuts)) {
    await goTo(page, target.from);
    quotes.push(await selectWords(page, target.from, target.to));
    await expect(selectionButton(page, 'Highlight')).toBeVisible();
    await selectionButton(page, 'Highlight').click();
    expectedMarks.count++;
    await expect.poll(async () => (await marks(page)).size).toBe(expectedMarks.count);
  }
  return quotes;
}

/** What is painted, as the texts of the ranges, sorted */
const paintedTexts = async page => (await painted(page)).map(line => line.replace(/^[^:]*: /, '')).sort();

async function expectPainted(page, quotes) {
  await expect.poll(() => paintedTexts(page)).toEqual([...quotes].sort());
}

const restoredDialog = page => dialog(page, 'Backup restored');

/** The places four highlights were stored at by the build that cut this text
    into the pieces below (content node and UTF-16 offset in that piece's text),
    with the words each selected: at the end of the first piece (node 8), at the
    start of the second (node 9), across the cut of the second and the third
    (nodes 9 and 10) and inside the third. A cut that moves would paint other
    words from these places, and this test would fail before a reader's book
    did (a highlight made before the change would move: #470). */
const GOLDEN = [
  { node: 8, offset: 55431, endNode: 8, endOffset: 55446, text: 'w06719ü✓ w06720' },
  { node: 9, offset: 0, endNode: 9, endOffset: 15, text: 'w06721😀 w06722' },
  { node: 9, offset: 55432, endNode: 10, endOffset: 13, text: 'w13440é w13441😀 w13442 w13443' },
  { node: 10, offset: 16, endNode: 10, endOffset: 46, text: 'w13444é w13445😀 w13446 w13447' },
];

for (const mode of MODES) {
  test(`${mode}: highlights at, across and after the cuts of a text over 64 KiB paint their own text, after a reload and a restored backup`, async ({ browser, page }, testInfo) => {
    const errors = await start(page);
    const file = epubFile(giantBook);
    await importFiles(page, [file], 1);
    await openBook(page, 'Giant Text');
    await arrange(page, mode);
    const cuts = await pieces(page);
    // three pieces or more, each under 64 KiB and cut where white space is
    expect(cuts.length).toBeGreaterThanOrEqual(3);
    for (const cut of cuts) expect(cut.bytes).toBeLessThan(65536);
    const quotes = await highlightAll(page, cuts);
    expect(quotes[2]).toContain(cuts[1].last[2]);
    await expectPainted(page, quotes);

    // the chapter shown again
    await toLibrary(page);
    await reload(page);
    await openBook(page, 'Giant Text');
    await expectPainted(page, quotes);

    // the backup restored on a device that has the book
    await toLibrary(page);
    await librarySettings(page);
    const backup = await exportedBackup(page);
    await settingsButton(page, 'Back').click();
    const path = testInfo.outputPath('giant-backup.json');
    writeFileSync(path, backup);
    const other = await browser.newContext({ viewport: page.viewportSize() });
    const second = await other.newPage();
    const secondErrors = await start(second);
    await importFiles(second, [file], 1);
    await librarySettings(second);
    await restoreInput(second).setInputFiles([path]);
    await expect(restoredDialog(second)).toBeVisible();
    await restoredDialog(second).getByRole('button').first().click();
    await openBook(second, 'Giant Text');
    // the backup holds the arrangement too
    await expect.poll(() => indicator(second).textContent()).toMatch(mode === 'scrolled' ? /% of chapter/ : mode === 'columns' ? /pages 1–2 of/ : / page 1 of/);
    await expectPainted(second, quotes);
    await other.close();
    expect(errors).toEqual([]);
    expect(secondErrors).toEqual([]);
  });

  test(`${mode}: highlights at, across and after the cuts of a text over 64 KiB are painted as made on the other device after a sync`, async ({ browser }) => {
    const store = stores.webdav;
    const server = store.make();
    const a = await store.device(browser, server, NOON);
    const b = await store.device(browser, server, minutesLater(NOON, 1));
    const file = epubFile(giantBook);
    for (const d of [a, b]) {
      await importFiles(d.page, [file], 1);
      await store.join(d, server);
    }
    await openBook(a.page, 'Giant Text');
    await arrange(a.page, mode);
    const cuts = await pieces(a.page);
    const quotes = await highlightAll(a.page, cuts);
    await hiddenSync(store, server, a);
    await openBook(b.page, 'Giant Text');
    await arrange(b.page, mode);
    await hiddenSync(store, server, b);
    await expectPainted(b.page, quotes);
    // and opened again from the library
    await toLibrary(b.page);
    await openBook(b.page, 'Giant Text');
    await expectPainted(b.page, quotes);
    expect(unexpected(a)).toEqual([]);
    expect(unexpected(b)).toEqual([]);
    await a.context.close();
    await b.context.close();
  });
}

test('places stored by the build that made the cuts paint the same words now', async ({ page }, testInfo) => {
  const errors = await start(page);
  const file = epubFile(giantBook);
  await importFiles(page, [file], 1);
  await librarySettings(page);
  const backup = JSON.parse(await exportedBackup(page));
  await settingsButton(page, 'Back').click();
  const [kept] = backup.books;
  // as a version before ids wrote them, so each is given its id from what it holds
  kept.annotations = GOLDEN.map(place => ({ kind: 'highlight', style: 'yellow', chapter: 0, page: 0, time: kept.added, note: '', ...place }));
  const path = testInfo.outputPath('golden-backup.json');
  writeFileSync(path, JSON.stringify(backup));
  await librarySettings(page);
  await restoreInput(page).setInputFiles([path]);
  await expect(restoredDialog(page)).toBeVisible();
  await restoredDialog(page).getByRole('button').first().click();
  await openBook(page, 'Giant Text');
  await expectPainted(page, GOLDEN.map(place => place.text));
  expect(errors).toEqual([]);
});


// A blank text of 64 KiB or more between the page's blocks makes no element,
// but takes the numbers its pieces would (render's _skip_spans), and search and
// read aloud count them by _skip_count, where a text that is shown is cut by
// _text_cut (#568). The two rules differ (65533 against 65535 or a break at
// white space), so what follows such a text is numbered right only while render,
// search and read aloud take the same count. These lengths are on both sides of
// where the two rules count different numbers of pieces (131068 and 131070
// spaces): the paragraph after the gap is found by search, marked on the right
// word, highlighted, and painted on the right word after the chapter is shown again.
for (const spaces of [65536, 131068, 131070, 196600]) {
  test(`the paragraph after a blank text of ${spaces} bytes is searched, highlighted and painted on its own words`, async ({ page }) => {
    const errors = await start(page);
    const gapBook = {
      title: 'Blank Gap', author: 'Cuts', storeChapters: false,
      rawChapters: [{ body: `<p>Before the gap.</p>${' '.repeat(spaces)}<p>After the gap: zebra quartz.</p>` }],
      toc: [{ label: 'Chapter 1', href: 'chapter1.xhtml' }],
    };
    await importFiles(page, [epubFile(gapBook)], 1);
    await openBook(page, 'Blank Gap');
    await page.keyboard.press('/');
    const box = searchPanel(page).getByRole('searchbox', { name: 'Search in book' });
    await expect(box).toBeFocused();
    await box.fill('zebra');
    await expect(searchPanel(page).getByRole('status')).toHaveText('1 result');
    await searchPanel(page).getByRole('region', { name: 'Results' }).getByRole('button').first().click();
    await expect(searchPanel(page)).toBeHidden();
    // the search's own mark is on the word searched for
    await expect.poll(async () => (await marks(page)).text).toBe('zebra');
    await searchBar(page).getByRole('button', { name: 'Close search' }).click();
    await expect(searchBar(page)).toBeHidden();
    await expect.poll(async () => (await marks(page)).size).toBe(0);
    const quote = await page.evaluate(() => {
      const owner = [...document.querySelectorAll('[role=document][aria-label=Page] p')].find(p => p.textContent.includes('zebra'));
      const walker = document.createTreeWalker(owner, NodeFilter.SHOW_TEXT);
      let found = null;
      for (let t = walker.nextNode(); t && !found; t = walker.nextNode()) if (t.data.includes('quartz')) found = t;
      const at = found.data.indexOf('quartz');
      const range = document.createRange();
      range.setStart(found, at);
      range.setEnd(found, at + 'quartz'.length);
      getSelection().removeAllRanges();
      getSelection().addRange(range);
      return range.toString();
    });
    expect(quote).toBe('quartz');
    await expect(selectionButton(page, 'Highlight')).toBeVisible();
    await selectionButton(page, 'Highlight').click();
    await expect.poll(async () => (await marks(page)).size).toBe(1);
    await expectPainted(page, ['quartz']);
    await toLibrary(page);
    await reload(page);
    await openBook(page, 'Blank Gap');
    await expectPainted(page, ['quartz']);
    expect(errors).toEqual([]);
  });
}
