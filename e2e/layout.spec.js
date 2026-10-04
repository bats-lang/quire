// Layout at every screen size (the configuration runs this file in all
// its projects): nothing spills out of the window, the page fills it,
// and the bars' controls fit.

import { test, expect } from './fixtures.js';
import {
  start, epubFile, importFiles, readBook, showChrome, chapters, cards, importInput, bookPage,
  chapterTitle, indicator,
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
