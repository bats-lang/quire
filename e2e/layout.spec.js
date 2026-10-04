// Layout at every screen size (the configuration runs this file in all
// its projects, down to narrow's 320 px, WCAG 1.4.10's width): nothing
// spills out of the window, the page fills it, the bars' controls fit,
// and no control's name or text is cut off on any screen (#265).

import { test, expect } from './fixtures.js';
import {
  start, epubFile, importFiles, readBook, showChrome, chapters, cards, importInput, bookPage,
  chapterTitle, indicator, libraryMenu, menuItem, dialog, librarySettings, settingsScreen,
  settingsButton, bookMenu, clickControl, openSettings, toLibrary, topBar,
  readingSettings, openReadingSettings,
} from './helpers.js';

/** The names of the visible controls among locators that reach out of
    the window's width */
async function outside(page, locators) {
  const width = page.viewportSize().width;
  const bad = [];
  for (const loc of locators) {
    for (const e of await loc.all()) {
      if (!(await e.isVisible())) continue;
      const r = await e.boundingBox();
      if (r.x < -1 || r.x + r.width > width + 1) bad.push(await e.evaluate(e => e.getAttribute('aria-label') || e.textContent));
    }
  }
  return bad;
}

/** What is cut off on the screen shown: each visible control whose
    content is wider or taller than its box (its label clipped, cut by an
    ellipsis, or spilling over its edges), and each visible element of
    text whose text spills out of it (an ellipsis that shortens a title
    on purpose is not counted: the title is whole elsewhere). The book's
    own page is left out: its columns run past it by design */
async function cutOff(page) {
  return page.evaluate(() => {
    const controls = 'button, a[href], label, [role=button], [role=menuitem], [role=tab], [role=link], [role=switch], [role=checkbox], [role=radio]';
    const book = document.querySelector('[role=document]');
    const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const named = e => (e.getAttribute('aria-label') || e.textContent || e.id || e.tagName).trim().slice(0, 40);
    const bad = [];
    for (const e of document.querySelectorAll('body *')) {
      if (book && book.contains(e)) continue;
      if (!shown(e)) continue;
      const style = getComputedStyle(e);
      // what scrolls holds more than it shows by design
      if (/auto|scroll/.test(style.overflowX + style.overflowY)) continue;
      // read out, not shown (1 px and clipped)
      if (e.clientWidth <= 1 && e.clientHeight <= 1) continue;
      const wide = e.scrollWidth > e.clientWidth + 1;
      const tall = e.scrollHeight > e.clientHeight + 1;
      if (e.matches(controls)) {
        if (wide || tall) bad.push(`${named(e)} (${e.clientWidth}x${e.clientHeight} holds ${e.scrollWidth}x${e.scrollHeight})`);
      } else if (wide && style.overflowX === 'visible' && [...e.childNodes].some(n => n.nodeType === 3 && n.textContent.trim())) {
        bad.push(`${named(e)} (text ${e.scrollWidth} px in ${e.clientWidth})`);
      }
    }
    return bad;
  });
}

/** Expects nothing cut off on the screen shown, and nothing wider than
    the window, naming the screen when something is */
async function fits(page, screen) {
  expect(await cutOff(page), `cut off on ${screen}`).toEqual([]);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${screen} is wider than the window`).toBe(true);
}

test('the library fits the window', async ({ page }) => {
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'A Rather Long Title For A Book That Goes On', author: 'Someone With A Long Name' }),
    epubFile({ title: 'Short', author: 'S' }),
  ], 2);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  expect(await outside(page, [page.getByRole('button'), page.getByRole('searchbox'), importInput(page), cards(page)])).toEqual([]);
  const ib = await importInput(page).boundingBox();
  expect(ib.height).toBeGreaterThanOrEqual(32);
});

test('the page fills the window, and the bars fit it', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Full Page', author: 'L', rawChapters: chapters(2) });
  const v = page.viewportSize();
  const c = await bookPage(page).boundingBox();
  expect(c.width).toBeGreaterThan(v.width * 0.95);
  expect(c.height).toBeGreaterThan(v.height * 0.9);
  // the text is not cut at the page's sides
  const cut = await bookPage(page).evaluate(doc => {
    const c = doc.getBoundingClientRect();
    return [...doc.querySelectorAll('p')].some(p => {
      const r = p.getClientRects();
      return [...r].some(x => x.left < c.left - 1 && x.right > c.left + 1);
    });
  });
  expect(cut).toBe(false);
  await showChrome(page);
  await expect(chapterTitle(page)).toBeVisible();
  expect(await outside(page, [
    page.getByRole('navigation', { name: 'Book' }).getByRole('button'),
    page.getByRole('toolbar', { name: 'Page controls' }).getByRole('button'),
    indicator(page),
    page.getByRole('slider', { name: 'Place in book' }),
  ])).toEqual([]);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});

/** The reader's bars as laid out now, measured at once (they hide
    themselves after 5 s): each visible button's box and name, the
    label's parts' boxes, the slider's box, and each label part's text
    whole or not */
async function bars(page) {
  return page.evaluate(() => {
    const toolbar = document.querySelector('[role=toolbar][aria-label="Page controls"]');
    const shown = e => e.checkVisibility() && e.getClientRects().length > 0;
    const box = e => { const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height, name: e.getAttribute('aria-label') || e.textContent.trim() }; };
    const status = toolbar.querySelector('[role=status]');
    const percent = status.parentElement.lastElementChild;
    return {
      buttons: [...toolbar.querySelectorAll('button')].filter(shown).map(box),
      label: [status, percent].filter(shown).map(box),
      // (the title and " · page " are read out, not shown, on a phone: 1 px)
      slider: box(toolbar.querySelector('[role=slider]')),
      cut: [status, ...status.children, percent].filter(shown).filter(e => e.clientWidth > 1 && e.scrollWidth > e.clientWidth + 1).map(e => e.textContent),
    };
  });
}

const overlap = (a, b) => a.x < b.x + b.width - 1 && b.x < a.x + a.width - 1 && a.y < b.y + b.height - 1 && b.y < a.y + a.height - 1;

// #274: the bottom bar in two rows, the place ("6 of 40 in chapter ·
// 1%") whole over the scrubber with the page turns at its ends, and the
// tools in a row of their own, each a 48 px target, nothing over another
test("the reader's bottom bar: the progress row over the tools row, nothing cut or overlapping", async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Bars', author: 'L', rawChapters: chapters(12, 40) });
  await showChrome(page);
  const measured = await bars(page);
  expect(measured.cut, 'cut off in the label').toEqual([]);
  const all = [...measured.buttons, ...measured.label, measured.slider];
  for (let i = 0; i < all.length; i++) {
    for (let j = i + 1; j < all.length; j++) {
      expect(overlap(all[i], all[j]), `${all[i].name} over ${all[j].name}`).toBe(false);
    }
  }
  const width = page.viewportSize().width;
  for (const b of all) expect(b.x >= -1 && b.x + b.width <= width + 1, `${b.name} out of the window`).toBe(true);
  const button = name => measured.buttons.find(b => b.name === name);
  const previous = button('Previous page'), next = button('Next page');
  const middle = b => b.y + b.height / 2;
  // the page turns at the scrubber's ends, on its row
  expect(previous.x + previous.width).toBeLessThanOrEqual(measured.slider.x + 1);
  expect(next.x).toBeGreaterThanOrEqual(measured.slider.x + measured.slider.width - 1);
  expect(Math.abs(middle(previous) - middle(measured.slider))).toBeLessThan(4);
  expect(Math.abs(middle(next) - middle(measured.slider))).toBeLessThan(4);
  // the label over it
  for (const part of measured.label) expect(part.y + part.height).toBeLessThanOrEqual(measured.slider.y + 1);
  // the tools under it, in one row, each at least 48 px
  const tools = ['Contents', 'Reading settings', 'Annotations'].map(button);
  for (const tool of tools) {
    expect(tool.y).toBeGreaterThanOrEqual(measured.slider.y + measured.slider.height - 1);
    expect(tool.width).toBeGreaterThanOrEqual(48);
    expect(tool.height).toBeGreaterThanOrEqual(48);
    expect(Math.abs(middle(tool) - middle(tools[0]))).toBeLessThan(2);
  }
  await fits(page, 'the reader with its bars');
});

// #274: every icon is a glyph of the bundled icon face, drawn in the
// bar's own text colour; none is an emoji, which a platform may draw as
// a colour picture
test("no bar button's text is an emoji, and the icons' face is there", async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Icons', author: 'L', rawChapters: chapters(2) });
  const texts = await page.evaluate(() => [...document.querySelectorAll('[role=navigation][aria-label=Book] button, [role=toolbar][aria-label="Page controls"] button')]
    .map(e => ({ name: e.getAttribute('aria-label') || e.textContent, text: e.textContent })));
  // the bars' buttons, narration's included, shown or not
  expect(texts.length).toBeGreaterThanOrEqual(12);
  for (const { name, text } of texts) {
    expect(/\p{Extended_Pictographic}|\u{FE0F}/u.test(text), `${name}: ${JSON.stringify(text)} is an emoji`).toBe(false);
  }
  const icons = texts.filter(t => /^[\u{E000}-\u{F8FF}]$/u.test(t.text));
  expect(icons.length).toBeGreaterThanOrEqual(11);
  const loaded = await page.evaluate(async glyphs => (await document.fonts.load("24px 'Material Symbols'", glyphs)).length, icons.map(t => t.text).join(''));
  expect(loaded, 'the icon face is loaded').toBe(1);
});

test('nothing is cut off in the library, its menus and its screens', async ({ page }) => {
  await start(page);
  await fits(page, 'the empty library');
  await importFiles(page, [
    epubFile({ title: 'A Rather Long Title For A Book That Goes On And On', author: 'Someone With A Rather Long Name' }),
    epubFile({ title: 'Short', author: 'S' }),
  ], 2);
  await fits(page, 'the library');
  // a collection, so its row shows
  await bookMenu(page, 'Short');
  await menuItem(page, 'Collections').click();
  const collections = dialog(page, 'Collections');
  await collections.getByRole('button', { name: 'New collection' }).click();
  const name = dialog(page, 'New collection').getByRole('textbox', { name: 'Name' });
  await fits(page, 'the new collection dialog');
  await name.fill('Books to read on the long journey home');
  await name.press('Enter');
  await expect(collections.getByRole('button', { name: 'Books to read on the long journey home' })).toBeVisible();
  await fits(page, 'the collections panel');
  await collections.getByRole('button', { name: 'Done' }).click();
  await expect(page.getByRole('group', { name: 'Collection' })).toBeVisible();
  await fits(page, 'the library with a collection');
  await page.getByRole('button', { name: 'Grid' }).click();
  await fits(page, 'the library as a grid');
  await page.getByRole('button', { name: 'List' }).click();
  await bookMenu(page, 'Short');
  await fits(page, 'the book menu');
  await menuItem(page, 'Book info').click();
  await expect(dialog(page, 'Book info')).toBeVisible();
  await fits(page, 'book info');
  await page.keyboard.press('Escape');
  await libraryMenu(page);
  await fits(page, 'the library menu');
  await menuItem(page, 'Reading statistics').click();
  await expect(dialog(page, 'Reading statistics')).toBeVisible();
  await fits(page, 'the reading statistics');
  await page.keyboard.press('Escape');
  await libraryMenu(page);
  await menuItem(page, 'Catalogues').click();
  await expect(dialog(page, 'Catalogues')).toBeVisible();
  await fits(page, 'the catalogues');
  await page.keyboard.press('Escape');
  await librarySettings(page);
  await fits(page, 'Settings');
  // the Reading screen (#289): how pages are turned and read aloud
  await settingsButton(page, 'Reading ›').click();
  await expect(page.getByRole('dialog', { name: 'Reading', exact: true })).toBeVisible();
  await fits(page, 'Reading');
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog', { name: 'Reading', exact: true })).toBeHidden();
  await settingsButton(page, 'Sync ›').click();
  await expect(dialog(page, 'Sync')).toBeVisible();
  await fits(page, 'Sync');
  await page.keyboard.press('Escape');
  await settingsButton(page, 'Dictionaries ›').click();
  await expect(dialog(page, 'Dictionaries')).toBeVisible();
  await fits(page, 'Dictionaries');
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await expect(settingsScreen(page)).toBeHidden();
  // the one red question
  await bookMenu(page, 'Short');
  await menuItem(page, 'Move to Trash').click();
  await libraryMenu(page);
  await menuItem(page, 'Empty Trash').click();
  await expect(dialog(page, 'Empty the Trash?')).toBeVisible();
  await fits(page, 'the Empty the Trash dialog');
});

test('nothing is cut off in the reader, its bars and its panels', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'A Rather Long Title For A Book That Goes On And On', author: 'L', rawChapters: chapters(3) });
  await showChrome(page);
  await fits(page, 'the reader with its bars');
  await clickControl(page, 'Contents');
  await expect(dialog(page, 'Contents')).toBeVisible();
  await fits(page, 'Contents');
  await page.keyboard.press('Escape');
  await openSettings(page);
  await fits(page, 'Reading settings');
  // each of its tabs (#288)
  for (const tab of ['Look', 'Page', 'Turning', 'Read aloud']) {
    await openReadingSettings(page, tab);
    await fits(page, `Reading settings, ${tab}`);
  }
  await page.keyboard.press('Escape');
  await clickControl(page, 'Annotations');
  await expect(dialog(page, 'Annotations')).toBeVisible();
  await fits(page, 'Annotations');
  await page.keyboard.press('Escape');
  await showChrome(page);
  await topBar(page).getByRole('button', { name: 'Search in book' }).click();
  await expect(dialog(page, 'Search in book')).toBeVisible();
  await fits(page, 'Search in book');
  await page.keyboard.press('Escape');
  await showChrome(page);
  await topBar(page).getByRole('button', { name: 'Settings' }).click();
  await expect(settingsScreen(page)).toBeVisible();
  await fits(page, 'Settings over the reader');
  await settingsButton(page, 'Reading ›').click();
  await expect(page.getByRole('dialog', { name: 'Reading', exact: true })).toBeVisible();
  await fits(page, 'Reading over the reader');
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await toLibrary(page);
});

/** The book's text on the page shown: each line box of the page's
    paragraphs that is on screen (the page's other columns lie beside
    it, out of sight) */
async function shownLines(page) {
  return bookPage(page).evaluate(doc => {
    const box = doc.getBoundingClientRect();
    const lines = [];
    for (const p of doc.querySelectorAll('p')) {
      for (const r of p.getClientRects()) {
        if (r.width > 0 && r.right > box.left + 1 && r.left < box.right - 1) lines.push({ left: r.left, right: r.right, top: r.top, bottom: r.bottom });
      }
    }
    return lines;
  });
}

// A screen's cutout (a camera hole, a notch) and rounded corners, as
// the browser reads them out (env(safe-area-inset-*)): Android's
// WebView gives the page the cutout's insets, in full screen too, and
// the page's text keeps out of them on every side (#275). Chromium's
// DevTools set the insets here, as a phone with a cutout at its top
// (in portrait) or its side (in landscape) would
test('the page keeps its text out of the safe area: a cutout above or beside it', async ({ page }) => {
  const insets = { top: 64, left: 48, right: 24, bottom: 30 };
  const devtools = await page.context().newCDPSession(page);
  await devtools.send('Emulation.setSafeAreaInsetsOverride', { insets });
  await start(page);
  await readBook(page, { title: 'Cutout', author: 'L', rawChapters: chapters(3, 60) });
  const v = page.viewportSize();
  const twoColumns = v.width > v.height && v.width >= 960;
  for (const turn of [false, true]) {
    if (turn) await page.keyboard.press('ArrowRight');
    await expect.poll(async () => (await shownLines(page)).length).toBeGreaterThan(0);
    const lines = await shownLines(page);
    const outside = lines.filter(r => r.left < insets.left - 1 || r.right > v.width - insets.right + 1
      || r.top < insets.top - 1 || r.bottom > v.height - insets.bottom + 1);
    expect(outside, `text in the safe area's insets on ${turn ? 'the second' : 'the first'} page`).toEqual([]);
    // a spread still shows two columns beside a cutout
    const columns = new Set(lines.map(r => Math.round(r.left / 40)));
    if (twoColumns) expect(columns.size, 'a spread\'s two columns').toBeGreaterThanOrEqual(2);
  }
  await fits(page, 'the reader beside a cutout');
});

// The reading settings' sheet scrolls within the window, and its Close
// and tabs stay in reach however far it is scrolled, in full screen too
// (#275: in full screen the sheet could no longer be scrolled to Close)
test('the reading settings sheet scrolls within the window, Close always in reach, in full screen too', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Sheet', author: 'L', rawChapters: chapters(1) });
  await openReadingSettings(page, 'Page');
  await readingSettings(page).getByRole('button', { name: 'Full screen', exact: true }).click();
  await expect.poll(() => page.evaluate(() => !!document.fullscreenElement)).toBe(true);
  await openReadingSettings(page, 'Look');
  const panel = dialog(page, 'Reading settings');
  const close = panel.getByRole('button', { name: 'Close', exact: true });
  const tabs = panel.getByRole('tablist', { name: 'Reading settings' });
  const last = panel.getByRole('button', { name: 'Reset to defaults', exact: true });
  const within = () => panel.evaluate(e => {
    const r = e.getBoundingClientRect();
    return r.top >= -1 && r.bottom <= innerHeight + 1;
  });
  expect(await within(), 'the sheet within the window').toBe(true);
  // scrolled from its top to its end, by the wheel as a reader would
  await panel.evaluate(e => { e.scrollTop = 0; });
  await expect(close).toBeInViewport({ ratio: 1 });
  const box = await panel.boundingBox();
  // over the rows' names, not a control
  await page.mouse.move(box.x + 24, box.y + box.height / 2);
  for (let i = 0; i < 20; i++) await page.mouse.wheel(0, 400);
  await expect.poll(() => panel.evaluate(e => e.scrollTop + e.clientHeight >= e.scrollHeight - 1)).toBe(true);
  await expect(last).toBeInViewport({ ratio: 1 });
  await expect(close).toBeInViewport({ ratio: 1 });
  await expect(tabs).toBeInViewport({ ratio: 1 });
  await fits(page, 'Reading settings, in full screen');
  await close.click();
  await expect(panel).toBeHidden();
  await page.evaluate(() => document.exitFullscreen());
});
