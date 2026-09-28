// Layout at every screen size (the configuration runs this file in all
// its projects): nothing spills out of the window, the page fills it,
// and the bars' controls fit.

import { test, expect } from '@playwright/test';
import { start, epubFile, importFiles, readBook, showChrome, chapters } from './helpers.js';

const inWindow = (page, sel) => page.evaluate(sel => {
  const bad = [];
  for (const e of document.querySelectorAll(sel)) {
    const r = e.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) continue;
    if (r.left < -1 || r.right > innerWidth + 1) bad.push(e.id || e.className);
  }
  return bad;
}, sel);

test('the library fits the window', async ({ page }) => {
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'A Rather Long Title For A Book That Goes On', author: 'Someone With A Long Name' }),
    epubFile({ title: 'Short', author: 'S' }),
  ], 2);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  expect(await inWindow(page, '#qltb button, #qltb input, #qibn, #qlst .card')).toEqual([]);
  const ib = await page.locator('#qibn').boundingBox();
  expect(ib.height).toBeGreaterThanOrEqual(32);
});

test('the page fills the window, and the bars fit it', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Full Page', author: 'L', rawChapters: chapters(2) });
  const v = page.viewportSize();
  const c = await page.locator('#qcnt').boundingBox();
  expect(c.width).toBeGreaterThan(v.width * 0.95);
  expect(c.height).toBeGreaterThan(v.height * 0.9);
  // the text is not cut at the page's sides
  const cut = await page.evaluate(() => {
    const c = document.getElementById('qcnt').getBoundingClientRect();
    return [...document.querySelectorAll('#qcnt p')].some(p => {
      const r = p.getClientRects();
      return [...r].some(x => x.left < c.left - 1 && x.right > c.left + 1);
    });
  });
  expect(cut).toBe(false);
  await showChrome(page);
  await expect(page.locator('#qcht')).toBeVisible();
  expect(await inWindow(page, '#qrnv button, #qrbb button, #qpgi, #qtrk')).toEqual([]);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});
