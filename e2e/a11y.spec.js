// Accessibility: an automated audit (axe) of every view finds nothing,
// and the reader works from the keyboard alone.

import { test, expect } from './fixtures.js';
import AxeBuilder from '@axe-core/playwright';
import {
  start, epubFile, importFiles, readBook, place, showChrome, chapters, cards, bookPage, control, dialog,
  selectText, illegible, clickControl, pageShown,
} from './helpers.js';

const audit = async page => {
  const r = await new AxeBuilder({ page }).analyze();
  return r.violations.map(v => `${v.id}: ${v.nodes.map(n => n.target.join(' ')).join(', ')}`);
};

// Every element is made up front (app.bats) and found by its id, so two
// sharing one would make a control act for another
test('no two elements share an id', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Ids', author: 'A', rawChapters: chapters(2) })], 1);
  await cards(page).first().click();
  await expect(bookPage(page)).toBeVisible();
  const dups = await page.evaluate(() => {
    const seen = new Map();
    for (const e of document.querySelectorAll('[id]')) seen.set(e.id, (seen.get(e.id) || 0) + 1);
    return [...seen].filter(([, n]) => n > 1).map(([id]) => id);
  });
  expect(dups).toEqual([]);
});

// the palette's contrast is proven (style.bats); axe checks each theme
// as the browser draws it
test('every theme passes the audit', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Themed', author: 'Axe', rawChapters: chapters(2) })], 1);
  await cards(page).first().click();
  await expect(bookPage(page)).toBeVisible();
  await clickControl(page, 'Reading settings');
  for (const name of ['Light', 'Sepia', 'Dark', 'Night', 'Grey']) {
    const button = page.getByRole('button', { name, exact: true });
    await button.click();
    await expect(button).toHaveAttribute('aria-pressed', 'true');
    expect(await audit(page), name).toEqual([]);
  }
});

test('no view has accessibility violations', async ({ page }) => {
  await start(page);
  expect(await audit(page)).toEqual([]);
  await importFiles(page, [epubFile({ title: 'Audited', author: 'Axe', coverImage: true, rawChapters: chapters(2) })], 1);
  expect(await audit(page)).toEqual([]);
  await cards(page).first().click();
  await expect(bookPage(page)).toBeVisible();
  expect(await audit(page)).toEqual([]);
  await clickControl(page, 'Reading settings');
  expect(await audit(page)).toEqual([]);
  await page.keyboard.press('Escape');
  await clickControl(page, 'Contents');
  expect(await audit(page)).toEqual([]);
  await page.keyboard.press('Escape');
  await page.keyboard.press('/');
  expect(await audit(page)).toEqual([]);
  // the bars shown over the page: the selection's, and the search results'
  await page.keyboard.type('para');
  const results = dialog(page, 'Search in book').getByRole('region', { name: 'Results' }).getByRole('button');
  await results.first().click();
  await expect(page.getByRole('toolbar', { name: 'Search results' })).toBeVisible();
  expect(await audit(page)).toEqual([]);
  expect(await illegible(page.getByRole('toolbar', { name: 'Search results' }))).toEqual([]);
  await page.getByRole('toolbar', { name: 'Search results' }).getByRole('button', { name: 'Close search' }).click();
  await selectText(page, 0, 8);
  await expect(page.getByRole('toolbar', { name: 'Selection' })).toBeVisible();
  expect(await audit(page)).toEqual([]);
  // axe leaves the contrast of a bar over the page undecided: checked here
  expect(await illegible(page.getByRole('toolbar', { name: 'Selection' }))).toEqual([]);
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
  expect(seen.some(t => t === 'Sort and view')).toBe(true);
  expect(seen.some(t => t.includes('Keyboard Only'))).toBe(true);
  await page.keyboard.press('Enter');
  await pageShown(page);
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
  for (const name of ['Previous page', 'Next page', 'Contents', 'Reading settings', 'Annotations']) {
    await expect(control(page, name)).toBeVisible();
  }
  const bars = page.getByRole('navigation', { name: 'Book' }).or(page.getByRole('toolbar', { name: 'Page controls' }));
  for (const b of await bars.getByRole('button').all()) {
    expect((await b.evaluate(e => e.getAttribute('aria-label') || e.textContent)).trim().length).toBeGreaterThan(1);
  }
});
