// Adjusting a selection and a highlight (quire#428): a long press on a
// word, the selection grown by the end handle, a selection across a column
// gap and an image, a selection in the footnote popup, a highlight
// re-selected to extend or shorten it, the toolbar and the handles, and a
// selection cancelled by a tap elsewhere.
//
// WHAT CAN BE PLAYED, and what cannot.
//
// Quire draws no selection handles: the browser does (Chrome's on Android
// and the WebView's), and Playwright cannot draw or press them. What the
// page can see of a handle drag is the selection it makes: the platform
// moves the selection's focus to the word under the finger. So:
//
//  * the long press is real. Chromium makes a touch gesture of mouse events
//    when `Emulation.setEmitTouchEventsForMouse` is on (`finger` below):
//    pointer events of type touch, touchstart, then, held, the long press
//    that selects a word and its contextmenu. CDP's own
//    `Input.dispatchTouchEvent` does not make a long press (the headless
//    shell's gesture detector gives none; probed), so it is not used.
//  * a handle drag is played as what it does, `Selection.setBaseAndExtent`
//    from the anchor to the end of the word under the finger (`handleTo`),
//    one word or line at a time, and every thing the app does about a
//    selection (its toolbar, the place, the marks) is checked after each
//    step. That Android's handle sends the same selectionchange is Chrome's
//    contract, not Quire's; it is tested here only as far as Quire reacts.
//  * a finger that drags (`finger.dragTo`) is real touch input: it is how
//    "the page-turn gesture does not start from a selection" and "dragging
//    past the page's edge does not turn the page" are checked.
//
// THE DECISIONS (by research, written down where they are made).
//
//  * Dragging a handle to the page's edge: the comparable readers differ.
//    Moon+ Reader scrolls on at the top or bottom edge (the request that
//    BookFusion lacked it:
//    https://bookfusion.featureos.app/p/support-highlighting-across-page-boundary-similar-to-moon-reader);
//    a Logos forum user says Kindle and Google Books on Android flip pages
//    while a handle is held (https://community.logos.com/discussion/comment/1084614),
//    which is one user's report; Apple's own support pages and iMore's
//    guide (touch and hold, then drag to the end of the text) say nothing
//    of crossing the page. Nothing found documents Apple Books or Play
//    Books. Quire's page is a CSS column, a selection is one range of
//    one chapter's DOM, and the issue asks that the page does not turn
//    while the selection is held: the page stays, the selection stops at the
//    page. A highlight across two pages is two highlights.
//  * Where the toolbar goes: Flutter's selection toolbar sits above the
//    selection and below it only where there is no room
//    (https://api.flutter.dev/flutter/material/TextSelectionToolbar/anchorAbove.html);
//    Firefox for Android moves its floating toolbar off the selection by
//    20dp so it does not lie over the bottom handles
//    (https://reviewboard.mozilla.org/r/60810/diff). So the toolbar lies over
//    neither the selected text nor the handles that hang HANDLE px under
//    its ends. Quire's bar is fixed (it does not follow the selection), so
//    "the toolbar follows" is read as "is shown, in the window, after each
//    change".
//  * A selection in the footnote popup is the popup's: the toolbar's
//    Highlight, Orange, Underline and Note cannot work on text that is not
//    the chapter's (annot_highlight finds no content node), and the project
//    rule is that a control that cannot work is not shown. So they are not
//    offered there, and nothing is saved.
//  * Tapping a highlight selects it, with the toolbar. Apple Books and
//    the Kindle apps show a highlight's menu on a tap on it (Apple Books:
//    https://www.idownloadblog.com/2020/01/22/highlights-notes-apple-books-app/;
//    the Kindle: tap the highlighted text for its Delete and Note,
//    https://tomsguide.com/how-to/how-to-highlight-text-and-make-notes-on-your-kindle);
//    on a Kobo the same tap offers handles on the highlight, which the
//    thread the issue cites calls terrible, since the handles will not move
//    while the menu is up and take a second try
//    (https://www.mobileread.com/forums/showthread.php?p=3803381). Quire
//    has one toolbar: the tap makes the highlight the selection, and the
//    selection that is changed and saved with Highlight replaces the old
//    range of that annotation (one annotation, its note kept), and an Undo
//    puts the old range back (the project's rule: nothing is lost at a
//    click). The Kobo thread is why the toolbar and the handles are tested
//    not to get in each other's way.
//  * A tap elsewhere only ends the selection: it neither turns the page
//    nor counts as a reading action. Nothing found documents this for
//    Apple Books, Play Books or the Kindle; it is the platform's own rule
//    for text selection (a tap outside clears it and does nothing else),
//    and a page turned by the tap that dismissed a menu would lose the
//    place the reader was selecting in. Judgement after the search, said so.

import { test, expect } from './fixtures.js';
import {
  start, readBook, place, placeChanged, bookPage, control, showChrome, dialog, selectionButton, marks, oneColumn,
  openReadingSettings, readingSettings,
} from './helpers.js';
import { cutOff, insetsShort, labelInName, coveredByBanner } from './controls-shown.js';
import { selectionBooks } from './selection-books.js';

const toolbar = page => page.getByRole('toolbar', { name: 'Selection' });
const panel = page => dialog(page, 'Annotations');
const noteDialog = page => dialog(page, 'Note');
// how far a handle hangs under the end of the selection it holds (Firefox
// for Android keeps its toolbar 20dp clear of the bottom handles)
const HANDLE = 20;

// ------------------------------------------------------------------
// what plays a finger and a mouse

/** A finger: mouse events made touch events by Chromium, which is the way
    to a long press in Chromium. Not awaited on a press, which is not
    answered until the long press has been decided. */
async function fingerOn(page) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Emulation.setEmitTouchEventsForMouse', { enabled: true, configuration: 'mobile' });
  let down = false;
  const send = (type, x, y) => cdp.send('Input.dispatchMouseEvent', {
    type, x, y, button: down || type === 'mouseReleased' ? 'left' : 'none', buttons: down ? 1 : 0, clickCount: 1,
  }).catch(() => {});
  // none of the commands is awaited: once a long press has begun Chromium
  // answers the next mouse command only after the release (probed), and
  // the commands are carried out in the order they are sent
  const finger = {
    async down(x, y) { send('mouseMoved', x, y); down = true; send('mousePressed', x, y); },
    async moveTo(x, y) { send('mouseMoved', x, y); },
    async up(x, y) { down = false; send('mouseReleased', x, y); await page.waitForTimeout(50); },
    /** The mouse is the mouse again: while it is a finger, Playwright's own
        clicks wait for a long press to be decided and never return */
    async off() {
      await cdp.send('Emulation.setEmitTouchEventsForMouse', { enabled: false }).catch(() => {});
      await cdp.detach().catch(() => {});
    },
    async tap(x, y) { await finger.down(x, y); await page.waitForTimeout(60); await finger.up(x, y); },
    /** Held for the long press: the word is selected while the finger is down */
    async longPress(x, y) {
      await finger.down(x, y);
      await expect.poll(() => page.evaluate(() => getSelection().toString())).not.toBe('');
      return finger;
    },
    /** From (x, y) to (x2, y2) in steps of 20 px, the finger staying down */
    async dragTo(x, y, x2, y2) {
      const steps = Math.max(2, Math.ceil(Math.hypot(x2 - x, y2 - y) / 20));
      for (let k = 1; k <= steps; k++) {
        await finger.moveTo(x + (x2 - x) * k / steps, y + (y2 - y) * k / steps);
        await page.waitForTimeout(16);
      }
    },
  };
  return finger;
}

/** Whether this project is played with a finger: the phones' (the desktop is
    played with the mouse) */
const touch = testInfo => ['android', 'mobile-portrait'].includes(testInfo.project.name);

/** A word on the page, as a pointer finds it: its text, where it is on the
    screen and where it is in the page's text (the text node's number among the
    page's, and the offsets) */
async function pageWords(page) {
  return bookPage(page).evaluate(doc => {
    const box = doc.getBoundingClientRect();
    const nodes = [];
    const walker = document.createTreeWalker(doc, NodeFilter.SHOW_TEXT);
    for (let t; (t = walker.nextNode());) nodes.push(t);
    const words = [];
    nodes.forEach((t, node) => {
      if (t.parentElement.closest('a, rt, rp')) return;
      for (const m of t.data.matchAll(/\S+/g)) {
        const r = document.createRange();
        r.setStart(t, m.index);
        r.setEnd(t, m.index + m[0].length);
        const b = r.getClientRects()[0];
        if (!b) continue;
        // wholly on the page shown (and clear of its running footer and top edge)
        if (b.left < box.left + 1 || b.right > box.right - 1 || b.top < box.top + 40 || b.bottom > box.bottom - 40) continue;
        words.push({
          text: m[0], node, start: m.index, end: m.index + m[0].length,
          x: b.x + b.width / 2, y: b.y + b.height / 2, left: b.left, right: b.right, top: b.top, bottom: b.bottom,
        });
      }
    });
    return words;
  });
}

/** The words of the page in lines: the words of each line, top to bottom */
async function pageLines(page) {
  const lines = [];
  for (const w of await pageWords(page)) {
    const line = lines.find(l => Math.abs(l[0].y - w.y) < 4);
    if (line) line.push(w); else lines.push([w]);
  }
  return lines;
}

/** The words in the page's middle third (a press there is no tap on a turn
    zone) that are at least `below` px down the page, in reading order: a long
    press on one of them is no tap, but a double click is two clicks, and a
    click in a side zone turns the page */
async function middleWords(page, below) {
  const box = await bookPage(page).boundingBox();
  const found = (await pageWords(page)).filter(w => w.y >= below && w.y < box.height - 140 && w.x > box.x + box.width * 0.3 && w.x < box.x + box.width * 0.7 && w.text.length >= 4);
  expect(found.length, 'words to press on in the page\'s middle').toBeGreaterThan(3);
  return found;
}

/** The nth of them */
async function middleWord(page, below, n = 0) {
  return (await middleWords(page, below))[n];
}

/** A word in the middle third, on the line nearest to anchor's: what is
    pressed to start a selection that a handle then takes to anchor */
async function middleNear(page, anchor) {
  const found = await middleWords(page, 0);
  return found.reduce((best, w) => Math.abs(w.y - anchor.y) < Math.abs(best.y - anchor.y) ? w : best);
}

/** What a handle does: the selection from anchor (a word) to the end of
    word, as the platform sets it as the finger moves */
async function handleTo(page, anchor, word) {
  await bookPage(page).evaluate((doc, [anchor, word]) => {
    const nodes = [];
    const walker = document.createTreeWalker(doc, NodeFilter.SHOW_TEXT);
    for (let t; (t = walker.nextNode());) nodes.push(t);
    getSelection().setBaseAndExtent(nodes[anchor.node], anchor.start, nodes[word.node], word.end);
  }, [anchor, word]);
}

/** The selected text */
const selected = page => page.evaluate(() => getSelection().toString());

/** The text of the page from the start of the anchor word to the end of the
    word, as the selection should have it (words joined by one space) */
function wordsFrom(words, anchor, word) {
  const a = words.findIndex(w => w.node === anchor.node && w.start === anchor.start);
  const b = words.findIndex(w => w.node === word.node && w.start === word.start);
  return words.slice(a, b + 1).map(w => w.text).join(' ');
}

const squash = text => text.replace(/\s+/g, ' ').trim();
/** Text without its white space: a Range's text has nothing between two
    paragraphs where a Selection's has a line feed */
const bare = text => text.replace(/\s+/g, '');

/** Presses (a long press, or a double click with the mouse) on word and
    waits for the toolbar */
async function pressOn(page, testInfo, word) {
  if (touch(testInfo)) {
    const finger = await fingerOn(page);
    await finger.longPress(word.x, word.y);
    await finger.up(word.x, word.y);
    await finger.off();
    await expect(toolbar(page)).toBeVisible();
    return null;
  }
  await page.mouse.dblclick(word.x, word.y);
  await expect(toolbar(page)).toBeVisible();
  return null;
}

/** Whether the bottom bar's controls are up */
const barsUp = page => control(page, 'Previous page').isVisible();

/** Waits until the layout has settled: the chapter's pages are counted
    again for a few seconds after it is shown (and when a font arrives), and
    a word's place is only a place once two looks 500 ms apart agree */
async function settled(page) {
  let last = '';
  await expect.poll(async () => {
    const now = JSON.stringify((await pageWords(page)).map(w => [w.text, Math.round(w.x), Math.round(w.y)]));
    const same = now === last;
    last = now;
    await page.waitForTimeout(500);
    return same;
  }, { timeout: 20000 }).toBe(true);
}

/** Opens a book of selection-books.js on its first page with the bars away */
async function open(page, name, opts = {}) {
  await start(page);
  await readBook(page, selectionBooks[name].opts);
  // hyphenation depends on the browser's dictionaries, which a machine may
  // or may not have, and a line that begins with the rest of a hyphenated
  // word moves where a drag to the line's start ends: the text is set
  // without it, as on every machine
  await openReadingSettings(page, 'Page');
  const hyphenation = readingSettings(page).getByRole('button', { name: 'Hyphenation', exact: true });
  if ((await hyphenation.getAttribute('aria-pressed')) === 'true') await hyphenation.click();
  await expect(hyphenation).toHaveAttribute('aria-pressed', 'false');
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
  if (opts.oneColumn) await oneColumn(page);
  // the bars are up as the book opens, and go in a few seconds
  await expect(control(page, 'Previous page')).toBeHidden({ timeout: 20000 });
  await settled(page);
}

/** The rectangle of the toolbar, and of what must stay clear of it: each
    end of the selection and the handle that hangs under it */
async function clearance(page) {
  return page.evaluate(({ HANDLE }) => {
    const r = getSelection().getRangeAt(0);
    const rects = [...r.getClientRects()].filter(b => b.width > 0);
    const first = rects[0], last = rects[rects.length - 1];
    const tb = document.querySelector('[role=toolbar][aria-label=Selection]').getBoundingClientRect();
    const hit = (a, b) => a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
    const zones = {
      'the selected text': rects,
      'the start handle': [{ left: first.left - HANDLE / 2, right: first.left + HANDLE / 2, top: first.bottom, bottom: first.bottom + HANDLE }],
      'the end handle': [{ left: last.right - HANDLE / 2, right: last.right + HANDLE / 2, top: last.bottom, bottom: last.bottom + HANDLE }],
    };
    return {
      toolbar: { left: tb.left, right: tb.right, top: tb.top, bottom: tb.bottom },
      covered: Object.entries(zones).filter(([, rs]) => rs.some(z => hit(tb, z))).map(([name]) => name),
    };
  }, { HANDLE });
}

/** The panel of annotations, with the bars up */
async function openPanel(page) {
  await showChrome(page);
  await control(page, 'Annotations').click();
  await expect(panel(page)).toBeVisible();
}

async function closePanel(page) {
  await panel(page).getByRole('button', { name: 'Close' }).click();
  await expect(panel(page)).toBeHidden();
}

/** How many highlights the panel lists (each has a Delete) */
async function highlightCount(page) {
  // (Highlight leaves the text selected, which a tap on a picture does not
  // end, and a tap with a selection brings up no bars: so it is ended here)
  await page.evaluate(() => getSelection().removeAllRanges());
  await openPanel(page);
  const count = await panel(page).getByRole('button', { name: 'Delete' }).count();
  await closePanel(page);
  return count;
}

async function writeNote(page, text) {
  await expect(noteDialog(page).getByRole('textbox', { name: 'Note' })).toBeVisible();
  await noteDialog(page).getByRole('textbox', { name: 'Note' }).fill(text);
  await noteDialog(page).getByRole('button', { name: 'Save' }).click();
}

// ------------------------------------------------------------------
// 1. A long press on a word

test('a long press on a word selects it, shows the toolbar, and neither turns the page nor brings up the bars', async ({ page }, testInfo) => {
  test.skip(!touch(testInfo), 'a long press is touch; the mouse\'s double click is the next test');
  await open(page, 'prose');
  const before = await place(page);
  const word = await middleWord(page, 150);
  const finger = await fingerOn(page);
  await finger.down(word.x, word.y);
  // held: the word is selected, the toolbar up, and nothing else moved
  await expect.poll(() => selected(page)).toBe(word.text);
  await expect(toolbar(page)).toBeVisible();
  expect(await barsUp(page), 'the bars stay away while the word is held').toBe(false);
  expect(await place(page)).toEqual(before);
  await finger.up(word.x, word.y);
  // and let go
  await expect(toolbar(page)).toBeVisible();
  expect(await selected(page)).toBe(word.text);
  await page.waitForTimeout(400);
  expect(await barsUp(page), 'the bars stay away after the press').toBe(false);
  expect(await place(page)).toEqual(before);
  await finger.off();
});

test('a double click on a word selects it, shows the toolbar, and does not turn the page', async ({ page }, testInfo) => {
  test.skip(touch(testInfo), 'the mouse is the desktop\'s; a phone is played with a finger');
  await open(page, 'prose');
  const before = await place(page);
  const word = await middleWord(page, 150);
  await page.mouse.dblclick(word.x, word.y);
  await expect.poll(() => selected(page).then(squash)).toBe(word.text);
  await expect(toolbar(page)).toBeVisible();
  await page.waitForTimeout(400);
  // (the bars are not asserted: the first click of the two is a tap on the
  // page's middle, which brings the bars up, as one does for every click
  // there; a long press is no tap, and its test says the bars stay away)
  expect(await place(page)).toEqual(before);
});

test('the page-turn gesture does not start from a selection: the finger that holds the word, dragged on across the page, turns nothing', async ({ page }, testInfo) => {
  test.skip(!touch(testInfo), 'a drag with a finger');
  await open(page, 'prose', { oneColumn: true });
  const before = await place(page);
  const word = await middleWord(page, 150);
  const finger = await fingerOn(page);
  await finger.longPress(word.x, word.y);
  await finger.dragTo(word.x, word.y, 8, word.y);
  await finger.up(8, word.y);
  await page.waitForTimeout(500);
  expect(await place(page), 'the held finger\'s drag turned the page').toEqual(before);
  await finger.off();
  expect(await selected(page)).toBe(word.text);
  await expect(toolbar(page)).toBeVisible();
});

test('the page-turn gesture does not start from a selection: a finger put down on the selected text and dragged on turns nothing', async ({ page }, testInfo) => {
  test.skip(!touch(testInfo), 'a drag with a finger');
  await open(page, 'prose', { oneColumn: true });
  const before = await place(page);
  const word = await middleWord(page, 150);
  await pressOn(page, testInfo, word);
  const finger = await fingerOn(page);
  await finger.down(word.x, word.y);
  await finger.dragTo(word.x, word.y, page.viewportSize().width * 0.1, word.y);
  await finger.up(page.viewportSize().width * 0.1, word.y);
  await page.waitForTimeout(500);
  expect(await place(page), 'a drag from the selection turned the page').toEqual(before);
  await finger.off();
});

// ------------------------------------------------------------------
// 2. The end handle

test('dragging the end handle extends the selection by words, across lines, to the page\'s last line; the toolbar stays up in the window', async ({ page }, testInfo) => {
  await open(page, 'prose', { oneColumn: true });
  const before = await place(page);
  const anchor = await middleWord(page, 100);
  await pressOn(page, testInfo, anchor);
  const words = await pageWords(page);
  const lines = await pageLines(page);
  const from = lines.findIndex(l => l.some(w => w.node === anchor.node && w.start === anchor.start));
  const inWindow = async () => {
    const b = await toolbar(page).boundingBox();
    const v = page.viewportSize();
    expect(b.x).toBeGreaterThanOrEqual(0);
    expect(b.y).toBeGreaterThanOrEqual(0);
    expect(b.x + b.width).toBeLessThanOrEqual(v.width);
    expect(b.y + b.height).toBeLessThanOrEqual(v.height);
  };
  // the end handle at: the next word, the end of the next line, two lines on, the page's last word
  const stops = [
    words[words.findIndex(w => w.node === anchor.node && w.start === anchor.start) + 1],
    lines[from + 1].at(-1),
    lines[Math.min(from + 3, lines.length - 1)][1],
    lines.at(-1).at(-1),
  ];
  let length = anchor.text.length;
  for (const stop of stops) {
    await handleTo(page, anchor, stop);
    const text = squash(await selected(page));
    expect(text, `the selection from "${anchor.text}" to "${stop.text}"`).toBe(wordsFrom(words, anchor, stop));
    expect(text.length).toBeGreaterThan(length);
    length = text.length;
    await expect(toolbar(page)).toBeVisible();
    await inWindow();
    expect(await place(page)).toEqual(before);
  }
  // the last line of the page is in it
  expect(squash(await selected(page)).endsWith(lines.at(-1).at(-1).text)).toBe(true);
  // and it can be shortened again, by the same handle
  await handleTo(page, anchor, stops[1]);
  expect(squash(await selected(page))).toBe(wordsFrom(words, anchor, stops[1]));
  await expect(toolbar(page)).toBeVisible();
});

test('with the mouse, a shift-click on a later word extends the selection to it, as the end handle does; the toolbar stays up', async ({ page }, testInfo) => {
  test.skip(touch(testInfo), 'the mouse is the desktop\'s; a phone has the handles');
  await open(page, 'prose', { oneColumn: true });
  const before = await place(page);
  const anchor = await middleWord(page, 100);
  await pressOn(page, testInfo, anchor);
  // a word on a later line, in the middle third (a click in a side zone turns the page)
  const later = (await middleWords(page, anchor.y + 40)).find(w => w.y > anchor.y + 40);
  expect(later, 'a later word to click on').toBeDefined();
  await page.keyboard.down('Shift');
  await page.mouse.click(later.right - 2, later.y);
  await page.keyboard.up('Shift');
  const text = squash(await selected(page));
  const words = await pageWords(page);
  expect(text.startsWith(anchor.text), 'the selection still starts at the pressed word').toBe(true);
  expect(text.length).toBeGreaterThan(anchor.text.length * 3);
  expect(words.map(w => w.text).join(' ')).toContain(text.slice(0, 40));
  expect(text.endsWith(later.text) || text.endsWith(later.text.slice(0, -1))).toBe(true);
  await expect(toolbar(page)).toBeVisible();
  expect(await place(page)).toEqual(before);
});

test('dragging past the page\'s edge does not turn the page while the selection is held: the selection stops at the page', async ({ page }, testInfo) => {
  await open(page, 'prose', { oneColumn: true });
  // on the second page, so that a turn either way would be seen
  const first = await place(page);
  await page.keyboard.press('ArrowRight');
  await placeChanged(page, first);
  await settled(page);
  const before = await place(page);
  expect(before.p).toBe(2);
  const width = page.viewportSize().width;
  const height = page.viewportSize().height;
  const anchor = await middleWord(page, 100);
  const lines = await pageLines(page);
  const last = lines.at(-1).at(-1);
  if (touch(testInfo)) {
    // the finger that holds the word goes on to the right edge and under
    // the page's last line, where a turn would be asked for
    const finger = await fingerOn(page);
    await finger.longPress(anchor.x, anchor.y);
    await finger.dragTo(anchor.x, anchor.y, width - 2, anchor.y);
    await finger.dragTo(width - 2, anchor.y, width - 2, height - 2);
    await finger.dragTo(width - 2, height - 2, width - 2, anchor.y);
    await finger.dragTo(width - 2, anchor.y, 2, anchor.y);
    await handleTo(page, anchor, last);
    await page.waitForTimeout(600);
    expect(await place(page)).toEqual(before);
    await finger.up(2, anchor.y);
    await finger.off();
  } else {
    await page.mouse.move(anchor.left + 1, anchor.y);
    await page.mouse.down();
    await page.mouse.move(width - 2, height - 2, { steps: 15 });
    await page.mouse.move(2, anchor.y, { steps: 15 });
    await page.waitForTimeout(600);
    expect(await place(page)).toEqual(before);
    await page.mouse.up();
  }
  await page.waitForTimeout(600);
  expect(await place(page), 'the page turned while the selection was dragged to its edge').toEqual(before);
  // the selection is still the page's own: it ends on this page
  const text = squash(await selected(page));
  expect(text).not.toBe('');
  const words = await pageWords(page);
  expect(words.some(w => text.endsWith(w.text)), `the selection ends in ${JSON.stringify(text.slice(-40))}, the page's words include ${JSON.stringify(words.slice(0, 6).map(w => w.text))}`).toBe(true);
  await expect(toolbar(page)).toBeVisible();
});

// ------------------------------------------------------------------
// 3. A selection across a column gap, an image, and in the footnote popup

/** The highlight made of the selection by the toolbar, and what it marks */
async function highlightSelection(page) {
  await selectionButton(page, 'Highlight').click();
  await expect(toolbar(page)).toBeHidden();
}

test('a selection across the gap between two columns is whole, and is one highlight', async ({ page }, testInfo) => {
  await open(page, 'prose');
  await openReadingSettings(page, 'Page');
  await readingSettings(page).getByRole('group', { name: 'Pages on screen' }).getByRole('button', { name: 'Two', exact: true }).click();
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
  await expect(control(page, 'Previous page')).toBeHidden({ timeout: 20000 });
  await settled(page);
  const words = await pageWords(page);
  const width = page.viewportSize().width;
  const left = words.filter(w => w.right < width / 2 - 2);
  const right = words.filter(w => w.left > width / 2 + 2);
  expect(left.length, 'words in the left column').toBeGreaterThan(10);
  expect(right.length, 'words in the right column').toBeGreaterThan(10);
  // from the left column's last line to the right column's first
  const anchor = left.filter(w => w.text.length >= 4).at(-3);
  const end = right[4];
  // the long press selects the anchor's word; the handle then takes the end across
  const pressed = await middleNear(page, anchor);
  await pressOn(page, testInfo, pressed);
  await handleTo(page, anchor, end);
  const text = squash(await selected(page));
  expect(text, 'no word lost or doubled at the gap').toBe(wordsFrom(words, anchor, end));
  const rects = await page.evaluate(() => [...getSelection().getRangeAt(0).getClientRects()].map(r => [r.left, r.right]));
  expect(rects.some(([l, r]) => r <= width / 2), 'the selection has text in the left column ' + JSON.stringify(rects)).toBe(true);
  expect(rects.some(([l]) => l >= width / 2), 'the selection has text in the right column ' + JSON.stringify(rects) + JSON.stringify([anchor, end])).toBe(true);
  await expect(toolbar(page)).toBeVisible();
  await highlightSelection(page);
  await expect.poll(() => marks(page)).toMatchObject({ size: 1 });
  expect(squash((await marks(page)).text)).toBe(text);
  expect(await highlightCount(page)).toBe(1);
});

test('a selection across an image is whole: the text before it, the picture and the text after', async ({ page }, testInfo) => {
  await open(page, 'picture', { oneColumn: true });
  await expect.poll(() => bookPage(page).getByRole('img', { name: 'the map' }).evaluate(i => i.naturalWidth)).toBe(120);
  const words = await pageWords(page);
  const picture = await bookPage(page).getByRole('img', { name: 'the map' }).boundingBox();
  const above = words.filter(w => w.bottom <= picture.y);
  const below = words.filter(w => w.top >= picture.y + picture.height);
  const anchor = above.find(w => w.text === 'picture');
  const end = below.find(w => w.text === 'selection');
  expect(anchor && end, 'words above and below the picture').toBeTruthy();
  await pressOn(page, testInfo, await middleNear(page, anchor));
  await handleTo(page, anchor, end);
  const text = squash(await selected(page));
  expect(text.startsWith('picture there')).toBe(true);
  expect(text.endsWith('selection')).toBe(true);
  expect(text).toContain('After the picture');
  // the picture is inside the range
  expect(await page.evaluate(() => getSelection().getRangeAt(0).cloneContents().querySelector('img') !== null)).toBe(true);
  await expect(toolbar(page)).toBeVisible();
  await highlightSelection(page);
  await expect.poll(() => marks(page)).toMatchObject({ size: 1 });
  expect(bare((await marks(page)).text)).toBe(bare(text));
  expect(await highlightCount(page)).toBe(1);
  // and the annotation lists the whole of it
  await openPanel(page);
  await expect(panel(page)).toContainText('After the picture');
  await closePanel(page);
});

test('a selection in the footnote popup is the popup\'s: no highlight is offered or made', async ({ page }, testInfo) => {
  await open(page, 'footnote', { oneColumn: true });
  await bookPage(page).getByRole('link', { name: '1', exact: true }).click();
  const popup = dialog(page, 'Footnote');
  await expect(popup).toBeVisible();
  const word = await popup.evaluate(el => {
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    for (let t; (t = walker.nextNode());) {
      const at = t.data.indexOf('several');
      if (at < 0) continue;
      const r = document.createRange();
      r.setStart(t, at);
      r.setEnd(t, at + 7);
      const b = r.getBoundingClientRect();
      return { x: b.x + b.width / 2, y: b.y + b.height / 2 };
    }
    return null;
  });
  expect(word, 'the note\'s words in the popup').not.toBeNull();
  if (touch(testInfo)) {
    const finger = await fingerOn(page);
    await finger.longPress(word.x, word.y);
    await finger.up(word.x, word.y);
    await finger.off();
  } else {
    await page.mouse.dblclick(word.x, word.y);
  }
  // the selection is in the popup
  await expect.poll(() => selected(page).then(squash)).toBe('several');
  expect(await page.evaluate(() => document.querySelector('[role=dialog][aria-label=Footnote]').contains(getSelection().anchorNode))).toBe(true);
  // the page's highlight controls are not offered over it
  for (const name of ['Highlight', 'Orange', 'Underline', 'Note']) {
    await expect(selectionButton(page, name), `${name} on text that is not the chapter's`).toBeHidden();
  }
  expect((await marks(page)).size).toBe(0);
  await expect(popup).toBeVisible();
  await popup.getByRole('button', { name: 'Close', exact: true }).click();
  await expect(popup).toBeHidden();
  expect(await highlightCount(page)).toBe(0);
});

// ------------------------------------------------------------------
// 4. A highlight, re-selected

/** A highlight with a note on the words from the anchor's to the end's,
    made as a reader makes one: selected, Note, the note written, saved */
async function highlightWithNote(page, testInfo, anchor, end, note) {
  await pressOn(page, testInfo, await middleNear(page, anchor));
  await handleTo(page, anchor, end);
  await selectionButton(page, 'Note').click();
  await writeNote(page, note);
  await expect(noteDialog(page)).toBeHidden();
  await expect.poll(() => marks(page)).toMatchObject({ size: 1 });
}

/** Taps (touch) or clicks (mouse) at a place on the page */
async function tapAt(page, testInfo, { x, y }) {
  if (touch(testInfo)) {
    const finger = await fingerOn(page);
    await finger.tap(x, y);
    await finger.off();
  } else await page.mouse.click(x, y);
}

/** The list's one annotation: its quoted text and note, read from the panel */
async function theAnnotation(page) {
  await openPanel(page);
  const rows = await panel(page).getByRole('button', { name: 'Delete' }).count();
  const text = await panel(page).innerText();
  await closePanel(page);
  return { rows, text };
}

// A tap between the sides' zones on a highlight selects its range (bridge's
// `select_range`) and brings up the toolbar; the end handle takes the
// selection to the new range; Highlight replaces that annotation's range (its
// note kept) behind an Undo offer (`HighlightRangeChanged`), and ends the
// selection (`clear_selection`).
for (const how of ['extend', 'shorten']) {
  test(`a highlight is re-selected to ${how} it: tapping it shows its toolbar, and the new range replaces the old with its note kept, undoably`, async ({ page }, testInfo) => {
    await open(page, 'prose', { oneColumn: true });
    const words = await pageWords(page);
    // the highlight is three words round the page's middle (so a tap on
    // it is no tap on a turn zone): extended by three more, or shortened by one
    const middle = (await middleWord(page, 150));
    const m = words.findIndex(w => w.node === middle.node && w.start === middle.start);
    const anchor = words[m - 1], shorter = words[m], first = words[m + 1], longer = words[m + 4];
    const end = how === 'extend' ? first : longer;
    const target = how === 'extend' ? longer : shorter;
    await highlightWithNote(page, testInfo, anchor, end, 'My thought');
    const old = wordsFrom(words, anchor, end);
    expect(squash((await marks(page)).text)).toBe(old);
    await expect(control(page, 'Previous page')).toBeHidden({ timeout: 20000 });

    // tapping the highlight shows the toolbar with the highlight selected
    await tapAt(page, testInfo, middle);
    await expect(toolbar(page), 'tapping a highlight shows its toolbar').toBeVisible();
    expect(squash(await selected(page)), 'the highlight is the selection').toBe(old);

    // the end handle takes it to the new end; Highlight saves it
    await handleTo(page, anchor, target);
    const now = wordsFrom(words, anchor, target);
    expect(squash(await selected(page))).toBe(now);
    await selectionButton(page, 'Highlight').click();
    await expect.poll(async () => squash((await marks(page)).text)).toBe(now);
    expect((await marks(page)).size, 'one mark, not two').toBe(1);
    const changed = await theAnnotation(page);
    expect(changed.rows, 'one annotation, not two').toBe(1);
    expect(changed.text).toContain('My thought');
    expect(changed.text).toContain(now);

    // undone: the old range is back, with its note
    await expect(page.getByRole('button', { name: 'Undo' })).toBeVisible();
    await page.getByRole('button', { name: 'Undo' }).click();
    await expect.poll(async () => squash((await marks(page)).text)).toBe(old);
    const undone = await theAnnotation(page);
    expect(undone.rows).toBe(1);
    expect(undone.text).toContain('My thought');
    expect(undone.text).toContain(old);
  });
}

// ------------------------------------------------------------------
// 5. The toolbar and the handles

test('the toolbar lies over neither the selected text nor the handles at its ends, wherever the selection is on the page', async ({ page }, testInfo) => {
  await open(page, 'prose', { oneColumn: true });
  const lines = await pageLines(page);
  const height = page.viewportSize().height;
  const covered = [];
  // a word near the top, the middle and the bottom of the page: three selections
  for (const at of [0.2, 0.5, 0.8]) {
    const line = lines.reduce((best, l) => Math.abs(l[0].y - height * at) < Math.abs(best[0].y - height * at) ? l : best);
    const anchor = line.find(w => w.text.length >= 4 && w.x > page.viewportSize().width * 0.3 && w.x < page.viewportSize().width * 0.7);
    const end = line.at(-1);
    // (pressed in the page's middle, where a click is safe from the bars
    // the first of two clicks brings up; the handle takes it where it is to be)
    await pressOn(page, testInfo, await middleNear(page, anchor));
    await handleTo(page, anchor, end);
    await expect(toolbar(page)).toBeVisible();
    const { covered: hidden } = await clearance(page);
    if (hidden.length) covered.push(`a selection at ${Math.round(at * 100)}% of the page's height: the toolbar covers ${hidden.join(' and ')}`);
    await page.evaluate(() => getSelection().removeAllRanges());
    await expect(toolbar(page)).toBeHidden();
  }
  expect(covered).toEqual([]);
});

test('on a 320 px window the toolbar\'s buttons are all in the window, reachable and whole', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 320, height: 640 });
  await open(page, 'prose', { oneColumn: true });
  const word = await middleWord(page, 150);
  await pressOn(page, testInfo, word);
  const names = await toolbar(page).getByRole('button').evaluateAll(buttons => buttons.map(b => b.textContent.trim()));
  expect(names).toEqual(expect.arrayContaining(['Highlight', 'Orange', 'Underline', 'Note', 'Copy']));
  for (const name of names) {
    const button = selectionButton(page, name);
    if (!(await button.isVisible())) continue;
    const box = await button.boundingBox();
    expect(box.x, `${name} starts inside the window`).toBeGreaterThanOrEqual(0);
    expect(box.x + box.width, `${name} ends inside the window`).toBeLessThanOrEqual(320);
    expect(box.y, `${name} starts inside the window`).toBeGreaterThanOrEqual(0);
    expect(box.y + box.height, `${name} ends inside the window`).toBeLessThanOrEqual(640);
    // reachable: what a finger at its centre touches is the button itself
    const reached = await button.evaluate(b => {
      const r = b.getBoundingClientRect();
      const top = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
      return top === b || b.contains(top);
    });
    expect(reached, `${name} is under something else`).toBe(true);
  }
  // as layout.spec.js's fits: nothing cut off, nothing nearer its container's edge than the scale allows
  expect(await cutOff(page), 'cut off with the selection toolbar up').toEqual([]);
  expect(await insetsShort(page), 'controls nearer their container\'s edge than the least inset').toEqual([]);
  expect(await labelInName(page), 'buttons whose name is not their words').toEqual([]);
  expect(await coveredByBanner(page)).toEqual([]);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});

// ------------------------------------------------------------------
// 6. Cancelled by a tap elsewhere

for (const where of ['in the middle of the page', 'in the zone that turns the page']) {
  test(`a selection cancelled by a tap ${where} leaves the place and the highlights as they were`, async ({ page }, testInfo) => {
    await open(page, 'prose', { oneColumn: true });
    const before = await place(page);
    const word = await middleWord(page, 150);
    await pressOn(page, testInfo, word);
    expect(await selected(page)).toBe(word.text);
    const width = page.viewportSize().width;
    const lines = await pageLines(page);
    // a spot with no text under it, clear of the toolbar (which lies over
    // or under the selection, wherever that is): the page's top margin, or
    // the margin under its last line
    const x = where === 'in the middle of the page' ? width / 2 : width - 12;
    const bar = await toolbar(page).boundingBox();
    const clear = y => y > 0 && !(x >= bar.x - 4 && x <= bar.x + bar.width + 4 && y >= bar.y - 4 && y <= bar.y + bar.height + 4);
    const y = [Math.max(lines[0][0].top - 20, 60), lines.at(-1)[0].bottom + 20].find(clear);
    expect(y, 'a spot clear of the toolbar and of text').toBeDefined();
    await tapAt(page, testInfo, { x, y });
    await expect(toolbar(page)).toBeHidden();
    expect(await selected(page)).toBe('');
    await page.waitForTimeout(500);
    expect(await place(page), 'the tap that cancelled the selection turned the page').toEqual(before);
    expect((await marks(page)).size).toBe(0);
    expect(await highlightCount(page)).toBe(0);
    expect(await place(page)).toEqual(before);
  });
}
