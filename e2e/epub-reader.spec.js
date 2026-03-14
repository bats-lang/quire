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

  // Phase 3: chapter loads successfully
  test('chapter loading shows content in reader', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Content Test',
      author: 'Bot',
      chapters: 2,
      paragraphsPerChapter: 4,
    });

    // Wait for reader view
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });

    // Content area should show rendered chapter HTML
    const content = page.locator('#qcnt');
    await expect(content).toBeVisible();
    // Wait for chapter content (paragraph text from create-epub)
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 50;
      },
      { timeout: 15000 }
    );

    expect(errors.length).toBe(0);
  });

  // Phase 4: page navigation
  test('page navigation with buttons and click zones', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Nav Test',
      author: 'Bot',
      chapters: 3,
      paragraphsPerChapter: 40,
    });

    // Wait for reader view and content
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 200;
      },
      { timeout: 15000 }
    );
    // Let CSS column layout settle
    await page.waitForTimeout(1000);

    // Verify nav bar elements
    const navBar = page.locator('#qrnv');
    await expect(navBar).toBeVisible();

    const backBtn = page.locator('#qbbk');
    await expect(backBtn).toBeVisible();

    const pageInfo = page.locator('#qpgi');
    await expect(pageInfo).toBeVisible();

    const prevBtn = page.locator('#qprv');
    const nextBtn = page.locator('#qnxt');
    await expect(prevBtn).toBeVisible();
    await expect(nextBtn).toBeVisible();

    // Page indicator shows "Ch N · p. N/M" format
    const pageText = await pageInfo.textContent();
    expect(pageText).toMatch(/^Ch \d+ · p\. \d+\/\d+$/);
    expect(pageText).toMatch(/^Ch 1 /);

    // Content area has multi-page content (scrollWidth > clientWidth)
    const content = page.locator('#qcnt');
    const dims = await content.evaluate(el => ({
      scrollWidth: el.scrollWidth,
      clientWidth: el.clientWidth,
    }));
    expect(dims.scrollWidth).toBeGreaterThan(dims.clientWidth);

    // Column width matches viewport width
    const vpWidth = page.viewportSize().width;
    expect(dims.scrollWidth % vpWidth).toBe(0);

    // --- Test next button navigation ---
    await nextBtn.click();
    await page.waitForTimeout(500);

    const pageTextAfterNext = await pageInfo.textContent();
    expect(pageTextAfterNext).toMatch(/\s+2\/\d+$/);

    // scrollLeft should have changed
    const scrollAfterNext = await content.evaluate(el => el.scrollLeft);
    expect(scrollAfterNext).toBe(vpWidth);

    // --- Test prev button navigation ---
    await prevBtn.click();
    await page.waitForTimeout(500);

    const pageTextAfterPrev = await pageInfo.textContent();
    expect(pageTextAfterPrev).toMatch(/\s+1\/\d+$/);

    // --- Click zone navigation ---
    const rightZone = page.locator('#qczr');
    const leftZone = page.locator('#qczl');

    // Right zone → next page
    await rightZone.click({ force: true });
    await page.waitForTimeout(500);

    const pageTextAfterZoneRight = await pageInfo.textContent();
    expect(pageTextAfterZoneRight).toMatch(/\s+2\/\d+$/);

    // Left zone → prev page
    await leftZone.click({ force: true });
    await page.waitForTimeout(500);

    const pageTextAfterZoneLeft = await pageInfo.textContent();
    expect(pageTextAfterZoneLeft).toMatch(/\s+1\/\d+$/);

    // --- Keyboard navigation ---
    // ArrowRight → next page
    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(500);

    const pageTextAfterArrowRight = await pageInfo.textContent();
    expect(pageTextAfterArrowRight).toMatch(/\s+2\/\d+$/);

    // ArrowLeft → prev page
    await page.keyboard.press('ArrowLeft');
    await page.waitForTimeout(500);

    const pageTextAfterArrowLeft = await pageInfo.textContent();
    expect(pageTextAfterArrowLeft).toMatch(/\s+1\/\d+$/);

    // Space → next page
    await page.keyboard.press('Space');
    await page.waitForTimeout(500);

    const pageTextAfterSpace = await pageInfo.textContent();
    expect(pageTextAfterSpace).toMatch(/\s+2\/\d+$/);

    expect(errors.length).toBe(0);
  });

  // Phase 5: chapter navigation
  test('next chapter navigation', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Chapter Nav Test',
      author: 'Bot',
      chapters: 3,
      paragraphsPerChapter: 8,
    });

    // Wait for reader view and content
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 50;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(1000);

    const pageInfo = page.locator('#qpgi');
    await expect(pageInfo).toBeVisible();

    // Should start at chapter 1
    const initialText = await pageInfo.textContent();
    expect(initialText).toMatch(/^Ch 1 /);

    // Get total pages in chapter 1
    const totalMatch = initialText.match(/(\d+)\/(\d+)$/);
    const totalPages = parseInt(totalMatch[2]);

    // Navigate to the last page of chapter 1
    const nextBtn = page.locator('#qnxt');
    for (let i = 1; i < totalPages; i++) {
      await nextBtn.click();
      await page.waitForTimeout(300);
    }

    // Verify we're on the last page
    const lastPageText = await pageInfo.textContent();
    expect(lastPageText).toMatch(new RegExp(`${totalPages}/${totalPages}$`));

    // Click next to advance to chapter 2
    await nextBtn.click();
    await page.waitForTimeout(2000); // wait for async chapter load

    // Wait for chapter 2 content to load
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qpgi');
        return el && /^Ch 2 /.test(el.textContent);
      },
      { timeout: 15000 }
    );

    const ch2Text = await pageInfo.textContent();
    expect(ch2Text).toMatch(/^Ch 2 · p\. 1\/\d+$/);

    expect(errors.length).toBe(0);
  });

  test('chapter progress display', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Progress Test',
      author: 'Bot',
      chapters: 2,
      paragraphsPerChapter: 8,
    });

    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 50;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(1000);

    const pageInfo = page.locator('#qpgi');
    await expect(pageInfo).toBeVisible();

    // Chapter 1 displays correctly
    const ch1Text = await pageInfo.textContent();
    expect(ch1Text).toMatch(/^Ch 1 · p\. 1\/\d+$/);

    expect(errors.length).toBe(0);
  });

  // Future phases
  test.skip('library persists across page reload', async ({ page }) => {});
  test.skip('reading position is restored', async ({ page }) => {});
});
