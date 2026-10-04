// Layout at every screen size (the configuration runs this file in all
// its projects, down to narrow's 320 px, WCAG 1.4.10's width): nothing
// spills out of the window, the page fills it, the bars' controls fit,
// and no control's name or text is cut off on any screen (#265).

import { test, expect } from './fixtures.js';
import {
  start, epubFile, importFiles, readBook, showChrome, chapters, cards, importInput, bookPage,
  chapterTitle, indicator, libraryMenu, menuItem, dialog, librarySettings, settingsScreen,
  settingsButton, bookMenu, clickControl, openSettings, toLibrary, topBar,
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
  await fits(page, 'Typography and theme');
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
  await page.keyboard.press('Escape');
  await toLibrary(page);
});
