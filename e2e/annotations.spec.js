// Bookmarks, highlights and notes: made from the reader, listed, gone
// to, kept, and exported as Markdown.

import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import {
  start, readBook, place, showChrome, toLibrary, openBook, selectText, marks, chapters,
} from './helpers.js';

const book = { title: 'Marked Up', author: 'Annotations Tests', rawChapters: chapters(2) };

test('a highlight is marked, kept, and listed with its note', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, book);
  await selectText(page, '#qcnt p', 0, 8);
  await expect(page.locator('#qsel')).toBeVisible();
  await page.locator('#qslh').click();
  await expect(page.locator('#qsel')).toBeHidden();
  await expect.poll(() => marks(page, 1)).toEqual({ size: 1, text: 'Para 1.0' });
  // a note on it
  await showChrome(page);
  await page.locator('#qanb').click();
  await expect(page.locator('#qanp')).toBeVisible();
  await expect(page.locator('#qanl')).toContainText('Para 1.0');
  await page.locator('#qanl [id^=qn]').first().click();
  await expect(page.locator('#qmta')).toBeVisible();
  await page.locator('#qmta').fill('A thought, with "quotes"');
  await page.locator('#qmb2').click();
  await expect(page.locator('#qanl')).toContainText('A thought, with "quotes"');
  await page.locator('#qanc').click();
  // kept across a reload
  await toLibrary(page);
  await page.reload();
  await openBook(page, 'Marked Up');
  await expect.poll(() => marks(page, 1)).toEqual({ size: 1, text: 'Para 1.0' });
  await showChrome(page);
  await page.locator('#qanb').click();
  await expect(page.locator('#qanl')).toContainText('A thought, with "quotes"');
  expect(errors).toEqual([]);
});

test('a note can be made straight from a selection', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await selectText(page, '#qcnt p', 5, 8);
  await page.locator('#qsln').click();
  await expect(page.locator('#qmta')).toBeVisible();
  await page.locator('#qmta').fill('Straight away');
  await page.locator('#qmb2').click();
  await showChrome(page);
  await page.locator('#qanb').click();
  await expect(page.locator('#qanl')).toContainText('1.0');
  await expect(page.locator('#qanl')).toContainText('Straight away');
});

test('an annotation in the list is gone to, and can be deleted', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  await selectText(page, '#qcnt p', 0, 8);
  await page.locator('#qslh').click();
  await page.keyboard.press('Home');
  await page.keyboard.press('ArrowLeft');
  await expect.poll(async () => (await place(page)).ch).toBe(1);
  await showChrome(page);
  await page.locator('#qanb').click();
  await page.locator('#qanl .hrow .hgo').first().click();
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  await expect.poll(() => marks(page, 1)).toMatchObject({ size: 1 });
  await showChrome(page);
  await page.locator('#qanb').click();
  await page.locator('#qanl [id^=qd]').first().click();
  await expect(page.locator('#qanl .hrow')).toHaveCount(0);
  await expect(page.locator('#qanl')).toContainText('No highlights yet');
  await expect.poll(() => marks(page, 1)).toMatchObject({ size: 0 });
});

test('the export is Markdown with the book, its highlights and notes', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await selectText(page, '#qcnt p', 0, 8);
  await page.locator('#qsln').click();
  await page.locator('#qmta').fill('Exported note');
  await page.locator('#qmb2').click();
  await showChrome(page);
  await page.locator('#qanb').click();
  const download = page.waitForEvent('download');
  await page.locator('#qanx').click();
  const d = await download;
  expect(d.suggestedFilename()).toBe('quire-annotations.md');
  const md = readFileSync(await d.path(), 'utf8');
  expect(md).toMatch(/^# Marked Up\n## Annotations Tests\n/);
  expect(md).toContain('Para 1.0');
  expect(md).toContain('Exported note');
});

test('the star bookmarks the page, lists it, and unbookmarks it', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  await showChrome(page);
  await expect(page.locator('#qbmk')).toHaveAttribute('aria-pressed', 'false');
  await page.locator('#qbmk').click();
  await expect(page.locator('#qbmk')).toHaveAttribute('aria-pressed', 'true');
  // not on another page
  await page.keyboard.press('ArrowRight');
  await showChrome(page);
  await expect(page.locator('#qbmk')).toHaveAttribute('aria-pressed', 'false');
  // listed on the contents panel's bookmarks tab, and gone to from there
  await page.locator('#qtcb').click();
  await page.locator('#qtcm').click();
  await expect(page.locator('#qtcm')).toHaveAttribute('aria-selected', 'true');
  await expect(page.locator('#qtbl [id^=qb]').first()).toBeVisible();
  await page.locator('#qtbl [id^=qb]').first().click();
  await expect.poll(async () => (await place(page)).p).toBe(2);
  // the b key takes it off again
  await page.keyboard.press('b');
  await showChrome(page);
  await expect(page.locator('#qbmk')).toHaveAttribute('aria-pressed', 'false');
});
