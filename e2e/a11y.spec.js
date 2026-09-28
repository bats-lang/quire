// Accessibility: an automated audit (axe) of every view finds nothing,
// and the reader works from the keyboard alone.

import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { start, epubFile, importFiles, readBook, place, showChrome, chapters } from './helpers.js';

const audit = async page => {
  const r = await new AxeBuilder({ page }).analyze();
  return r.violations.map(v => `${v.id}: ${v.nodes.map(n => n.target.join(' ')).join(', ')}`);
};

test('no view has accessibility violations', async ({ page }) => {
  await start(page);
  expect(await audit(page)).toEqual([]);
  await importFiles(page, [epubFile({ title: 'Audited', author: 'Axe', coverImage: true, rawChapters: chapters(2) })], 1);
  expect(await audit(page)).toEqual([]);
  await page.locator('#qlst .card').first().click();
  await expect(page.locator('#qrvw')).toBeVisible();
  expect(await audit(page)).toEqual([]);
  await showChrome(page);
  await page.locator('#qset').click();
  expect(await audit(page)).toEqual([]);
  await page.keyboard.press('Escape');
  await showChrome(page);
  await page.locator('#qtcb').click();
  expect(await audit(page)).toEqual([]);
  await page.keyboard.press('Escape');
  await page.keyboard.press('/');
  expect(await audit(page)).toEqual([]);
});

test('the library\'s controls are reached with Tab and work with Enter', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Keyboard Only', author: 'K', rawChapters: chapters(2) })], 1);
  const focused = () => page.evaluate(() => document.activeElement && document.activeElement.id);
  let seen = [];
  for (let k = 0; k < 12 && !seen.includes('k0'); k++) {
    await page.keyboard.press('Tab');
    seen.push(await focused());
  }
  expect(seen).toContain('qsrt');
  expect(seen).toContain('k0');
  await page.keyboard.press('Enter');
  await expect(page.locator('#qrvw')).toBeVisible();
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(2);
});

test('icon buttons have names', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Named Buttons', author: 'N', rawChapters: chapters(1, 5) });
  await showChrome(page);
  for (const id of ['qbbk', 'qbmk', 'qsch', 'qprv', 'qnxt', 'qtcb', 'qset', 'qanb']) {
    const name = await page.locator('#' + id).evaluate(e => e.getAttribute('aria-label') || e.textContent.trim());
    expect(name.length, id).toBeGreaterThan(0);
  }
  expect(await page.locator('#qbbk').getAttribute('aria-label')).toBeTruthy();
});
