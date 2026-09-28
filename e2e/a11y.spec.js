// Accessibility: an automated audit (axe) of every view finds nothing,
// and the reader works from the keyboard alone.

import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import {
  start, epubFile, importFiles, readBook, place, showChrome, chapters, cards, bookPage, control,
} from './helpers.js';

const audit = async page => {
  const r = await new AxeBuilder({ page }).analyze();
  return r.violations.map(v => `${v.id}: ${v.nodes.map(n => n.target.join(' ')).join(', ')}`);
};

test('no view has accessibility violations', async ({ page }) => {
  await start(page);
  expect(await audit(page)).toEqual([]);
  await importFiles(page, [epubFile({ title: 'Audited', author: 'Axe', coverImage: true, rawChapters: chapters(2) })], 1);
  expect(await audit(page)).toEqual([]);
  await cards(page).first().click();
  await expect(bookPage(page)).toBeVisible();
  expect(await audit(page)).toEqual([]);
  await showChrome(page);
  await control(page, 'Typography').click();
  expect(await audit(page)).toEqual([]);
  await page.keyboard.press('Escape');
  await showChrome(page);
  await control(page, 'Contents').click();
  expect(await audit(page)).toEqual([]);
  await page.keyboard.press('Escape');
  await page.keyboard.press('/');
  expect(await audit(page)).toEqual([]);
});

test('the library\'s controls are reached with Tab and work with Enter', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Keyboard Only', author: 'K', rawChapters: chapters(2) })], 1);
  // what a screen reader would announce for the focused control
  const focused = () => page.evaluate(() => {
    const e = document.activeElement;
    return e ? (e.getAttribute('aria-label') || e.textContent || '').trim() : '';
  });
  const seen = [];
  for (let k = 0; k < 12 && !seen.some(t => t.includes('Keyboard Only')); k++) {
    await page.keyboard.press('Tab');
    seen.push(await focused());
  }
  expect(seen.some(t => t.startsWith('Sort:'))).toBe(true);
  expect(seen.some(t => t.includes('Keyboard Only'))).toBe(true);
  await page.keyboard.press('Enter');
  await expect(bookPage(page)).toBeVisible();
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(2);
});

test('icon buttons have names', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Named Buttons', author: 'N', rawChapters: chapters(1, 5) });
  await showChrome(page);
  // every button in the bars is found by the name it is announced by
  for (const name of ['Back to library', 'Bookmark this page', 'Search in book']) {
    await expect(page.getByRole('navigation', { name: 'Book' }).getByRole('button', { name, exact: true })).toBeVisible();
  }
  for (const name of ['Previous page', 'Next page', 'Contents', 'Typography', 'Annotations']) {
    await expect(control(page, name)).toBeVisible();
  }
  const bars = page.getByRole('navigation', { name: 'Book' }).or(page.getByRole('toolbar', { name: 'Page controls' }));
  for (const b of await bars.getByRole('button').all()) {
    expect((await b.evaluate(e => e.getAttribute('aria-label') || e.textContent)).trim().length).toBeGreaterThan(1);
  }
});
