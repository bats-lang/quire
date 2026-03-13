/**
 * E2E test: EPUB import and reading flow.
 *
 * CSS class mapping (from theme.bats class indices):
 *   0 -> caa = library_list
 *   1 -> cab = empty_lib
 *   2 -> cac = import_btn
 *   3 -> cad = reader_view
 *   4 -> cae = back_btn
 *   5 -> caf = content_area
 *
 * Widget IDs (from quire.bats):
 *   qllc = library list container
 *   qrvw = reader view container
 *   qbbk = back button
 *   qcnt = content area
 *   qelb = empty library message
 *   qibn = import button
 *   qfin = file input
 */

import { test, expect } from '@playwright/test';
import { createEpub } from './create-epub.js';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const SCREENSHOT_DIR = join(process.cwd(), 'e2e', 'screenshots');
mkdirSync(SCREENSHOT_DIR, { recursive: true });

/** Helper: import an EPUB file into quire */
async function importEpub(page, opts = {}) {
  const epubBuffer = createEpub({
    title: opts.title || 'Test Book',
    author: opts.author || 'Test Author',
    chapters: opts.chapters || 3,
    paragraphsPerChapter: opts.paragraphsPerChapter || 12,
    storeChapters: true,
    ...opts,
  });

  await page.goto('/');
  await page.waitForSelector('#qllc', { timeout: 15000 });

  const epubPath = join(SCREENSHOT_DIR, `test-${Date.now()}.epub`);
  writeFileSync(epubPath, epubBuffer);
  const fileInput = page.locator('input[type="file"]');
  await fileInput.setInputFiles(epubPath);
}

test.describe('EPUB Reader E2E', () => {
  // Phase 2: library view loads
  test('library view loads with empty state', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    // Library list is visible
    await expect(page.locator('#qllc')).toBeVisible();
    // Empty library message
    await expect(page.locator('#qelb')).toBeVisible();
    // Import button
    await expect(page.locator('#qibn')).toBeVisible();
    // Reader view is hidden
    await expect(page.locator('#qrvw')).toBeHidden();

    expect(errors.length).toBe(0);
  });

  // Phase 3: import opens reader view
  test('import epub switches to reader view', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'My Novel',
      author: 'Jane Doe',
      chapters: 2,
      paragraphsPerChapter: 4,
    });

    // Reader view should become visible
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    // Library should be hidden
    await expect(page.locator('#qllc')).toBeHidden();

    expect(errors.length).toBe(0);
  });

  // Phase 3: back button returns to library
  test('back button returns to library view', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Back Test',
      author: 'Bot',
      chapters: 1,
      paragraphsPerChapter: 2,
    });

    // Wait for reader view
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });

    // Click back button
    await page.locator('#qbbk').click();

    // Library should be visible again
    await expect(page.locator('#qllc')).toBeVisible({ timeout: 5000 });
    // Reader should be hidden
    await expect(page.locator('#qrvw')).toBeHidden();

    expect(errors.length).toBe(0);
  });

  // Phase 3: content area shows loading state
  test('chapter loading shows content in reader', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Content Test',
      author: 'Bot',
      chapters: 2,
      paragraphsPerChapter: 2,
    });

    // Wait for reader view
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });

    // Content area should be visible with loading text
    const content = page.locator('#qcnt');
    await expect(content).toBeVisible();
    await expect(content).toHaveText('Loading chapter...', { timeout: 15000 });

    expect(errors.length).toBe(0);
  });

  // Future phases
  test.skip('chapter content renders HTML elements', async ({ page }) => {});
  test.skip('next chapter navigation', async ({ page }) => {});
  test.skip('chapter progress display', async ({ page }) => {});
  test.skip('library persists across page reload', async ({ page }) => {});
  test.skip('reading position is restored', async ({ page }) => {});
});
