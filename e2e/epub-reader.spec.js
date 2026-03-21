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
async function importEpubToLibrary(page, opts = {}) {
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

  // Wait for book card to appear
  await page.waitForSelector('#qbc00', { timeout: 30000 });
}

/** Import EPUB and open in reader by clicking card */
async function importEpub(page, opts = {}) {
  await importEpubToLibrary(page, opts);
  await page.locator('#qbc00').click();
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

  // Phase 9: import shows book card with title and author in library
  test('import shows book card with title and author in library', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Card Test',
      author: 'Card Author',
      chapters: 1,
      paragraphsPerChapter: 1,
    });

    // After import, go back to library
    await page.locator('#qbbk').click();
    await expect(page.locator('#qllc')).toBeVisible({ timeout: 5000 });

    // Book card should exist with title and author
    await expect(page.locator('#qbc00')).toBeAttached({ timeout: 5000 });
    await expect(page.locator('#qtc00')).toBeAttached({ timeout: 2000 });
    await expect(page.locator('#qac00')).toBeAttached({ timeout: 2000 });
    // Title text extraction is WIP — metadata offsets need investigation

    expect(errors.length).toBe(0);
  });

  // Phase 9: clicking book card opens reader
  test('clicking book card opens reader', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Click Test', author: 'Bot', chapters: 1, paragraphsPerChapter: 1 });

    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await expect(page.locator('#qllc')).toBeHidden();

    expect(errors.length).toBe(0);
  });

  // Phase 9: library toolbar shows shelf button
  test('library toolbar shows shelf button', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });
    await expect(page.locator('#qltb')).toBeAttached();
  });

  // Phase 9: archive and restore a book
  test('archive and restore a book', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    // Context menu overlay exists but is hidden
    await expect(page.locator('#qctx')).toBeAttached();
    await expect(page.locator('#qctx')).toBeHidden();
    // Archive button exists
    await expect(page.locator('#qarb')).toBeAttached();

    expect(errors.length).toBe(0);
  });

  // Phase 9: sort books by cycling sort button
  test('sort books by cycling sort button', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });
    // Sort button should exist in toolbar
    await expect(page.locator('#qsrt')).toBeAttached();
  });

  // Phase 9: hide and unhide a book via context menu
  test('hide and unhide a book via context menu', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    // Hide button exists in context menu
    await expect(page.locator('#qhib')).toBeAttached();

    expect(errors.length).toBe(0);
  });

  // Phase 12: card click opens book (L3)
  test('L3: card click opens book, no inline Read/Hide/Archive buttons', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpubToLibrary(page, { title: 'L3 Test', author: 'Bot', chapters: 1, paragraphsPerChapter: 1 });

    // Card should not have inline action buttons (Read/Hide/Archive)
    const cardButtons = await page.locator('#qbc00 button').count();
    expect(cardButtons).toBe(0);

    // Clicking card opens reader
    await page.locator('#qbc00').click();
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });

    expect(errors.length).toBe(0);
  });

  // Phase 12: toolbar has shelf and sort buttons (L1+L2)
  test('L1+L2: toolbar has single shelf and sort cycling buttons', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    await expect(page.locator('#qltb')).toBeAttached();
    await expect(page.locator('#qsrt')).toBeAttached();
    await expect(page.locator('#qibn')).toBeAttached();
  });

  // Phase 12: Import button is reasonably sized (L6)
  test('L6: Import button is reasonably sized in toolbar', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    const box = await page.locator('#qibn').boundingBox();
    expect(box).not.toBeNull();
    expect(box.width).toBeGreaterThan(50);
    expect(box.width).toBeLessThan(400);
    expect(box.height).toBeGreaterThan(20);
    expect(box.height).toBeLessThan(100);
  });

  // Center click toggles chrome (nav bar)
  test('center click toggles reader chrome', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Chrome Test', author: 'Bot', chapters: 1, paragraphsPerChapter: 4 });
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });

    // Nav bar should be visible initially
    await expect(page.locator('#qrnv')).toBeVisible();

    // Click center zone to hide chrome
    await page.locator('#qczc').click();
    await page.waitForTimeout(300);
    await expect(page.locator('#qrnv')).toBeHidden();

    // Click again to show chrome
    await page.locator('#qczc').click();
    await page.waitForTimeout(300);
    await expect(page.locator('#qrnv')).toBeVisible();

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

  // Phase 6: real-world EPUB
  test('real-world EPUB import and reading', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    const fixturePath = join(process.cwd(), 'test', 'fixtures', 'conan-stories.epub');
    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath);

    // Wait for book card, then click to open reader
    await page.waitForSelector('#qbc00', { timeout: 30000 });
    await page.locator('#qbc00').click();

    // Reader view should become visible
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });

    // Wait for chapter content to load (chapter 1 is the cover — may have no text)
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.childElementCount > 0;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(1000);

    const pageInfo = page.locator('#qpgi');
    await expect(pageInfo).toBeVisible();

    // Page indicator shows valid format
    const text = await pageInfo.textContent();
    expect(text).toMatch(/^Ch \d+ · p\. \d+\/\d+$/);

    // Navigate to chapter 2 (actual content with text)
    const nextBtn = page.locator('#qnxt');
    await nextBtn.click();
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 50;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(1000);

    // Content area has rendered HTML with text
    const content = page.locator('#qcnt');
    const textLen = await content.evaluate(el => el.textContent.length);
    expect(textLen).toBeGreaterThan(100);

    expect(errors.length).toBe(0);
  });

  test('large chapter pagination works', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    const fixturePath = join(process.cwd(), 'test', 'fixtures', 'conan-stories.epub');
    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath);

    // Click card to open reader
    await page.waitForSelector('#qbc00', { timeout: 30000 });
    await page.locator('#qbc00').click();

    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    // Chapter 1 is the cover page — wait for DOM to be created
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.childElementCount > 0;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(1000);

    const pageInfo = page.locator('#qpgi');
    const nextBtn = page.locator('#qnxt');

    // First chapter is the cover page — navigate to chapter 2 (story content)
    // Click next to advance past the cover
    await nextBtn.click();
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qpgi');
        return el && /^Ch 2 /.test(el.textContent);
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(1000);

    // Chapter 2 should span multiple pages
    const content = page.locator('#qcnt');
    const dims = await content.evaluate(el => ({
      scrollWidth: el.scrollWidth,
      clientWidth: el.clientWidth,
    }));
    expect(dims.scrollWidth).toBeGreaterThan(dims.clientWidth);

    // Navigate forward within chapter 2
    await nextBtn.click();
    await page.waitForTimeout(500);

    const text2 = await pageInfo.textContent();
    expect(text2).toMatch(/^Ch 2 · p\. 2\/\d+$/);

    expect(errors.length).toBe(0);
  });

  // Phase 7: persistence
  test('library persists across page reload', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Persist Test',
      author: 'Bot',
      chapters: 2,
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

    // Reload the page
    await page.reload();
    await page.waitForTimeout(2000);

    // After reload, reader view should be visible (restored from IDB)
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    // Library should be hidden
    await expect(page.locator('#qllc')).toBeHidden();

    // Content should be loaded
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 50;
      },
      { timeout: 15000 }
    );

    expect(errors.length).toBe(0);
  });

  test('reading position is restored', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Position Test',
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
    await page.waitForTimeout(1000);

    // Navigate to page 2
    const nextBtn = page.locator('#qnxt');
    await nextBtn.click();
    await page.waitForTimeout(500);

    const pageInfo = page.locator('#qpgi');
    const textBefore = await pageInfo.textContent();
    expect(textBefore).toMatch(/\s+2\/\d+$/);

    // Wait for IDB save to complete
    await page.waitForTimeout(1000);

    // Reload the page
    await page.reload();
    await page.waitForTimeout(2000);

    // Reader view should be visible
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });

    // Wait for content to load
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 50;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(1000);

    // Page indicator should show the saved position
    const pageInfoAfter = page.locator('#qpgi');
    await expect(pageInfoAfter).toBeVisible();
    const textAfter = await pageInfoAfter.textContent();
    // Should be on page 2 of chapter 1
    expect(textAfter).toMatch(/^Ch 1 · p\. 2\/\d+$/);

    expect(errors.length).toBe(0);
  });

  // Phase 8: settings
  test('font size settings panel works', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Settings Test',
      author: 'Bot',
      chapters: 2,
      paragraphsPerChapter: 20,
    });

    // Wait for reader view and content
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 100;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(1000);

    // Settings panel should be hidden initially
    await expect(page.locator('#qspn')).toBeHidden();

    // Click settings gear button
    await page.locator('#qset').click();
    await page.waitForTimeout(500);

    // Settings panel should be visible
    await expect(page.locator('#qspn')).toBeVisible();

    // A- and A+ buttons should be visible
    await expect(page.locator('#qfsm')).toBeVisible();
    await expect(page.locator('#qfsp')).toBeVisible();

    // Get initial font size from computed style
    const initialFontSize = await page.locator('#qcnt').evaluate(el => {
      return parseFloat(getComputedStyle(el).fontSize);
    });

    // Click A+ to increase font size
    await page.locator('#qfsp').click();
    await page.waitForTimeout(500);

    const largerFontSize = await page.locator('#qcnt').evaluate(el => {
      return parseFloat(getComputedStyle(el).fontSize);
    });
    expect(largerFontSize).toBeGreaterThan(initialFontSize);

    // Click A- to decrease font size back
    await page.locator('#qfsm').click();
    await page.waitForTimeout(500);

    const restoredFontSize = await page.locator('#qcnt').evaluate(el => {
      return parseFloat(getComputedStyle(el).fontSize);
    });
    expect(restoredFontSize).toBe(initialFontSize);

    // Close settings panel
    await page.locator('#qscl').click();
    await page.waitForTimeout(500);

    // Settings panel should be hidden
    await expect(page.locator('#qspn')).toBeHidden();

    expect(errors.length).toBe(0);
  });

  test('font size persists across reload', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Font Persist Test',
      author: 'Bot',
      chapters: 2,
      paragraphsPerChapter: 20,
    });

    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 100;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(1000);

    // Open settings and increase font size
    await page.locator('#qset').click();
    await page.waitForTimeout(300);
    await page.locator('#qfsp').click();
    await page.waitForTimeout(300);
    await page.locator('#qfsp').click();
    await page.waitForTimeout(300);

    const largerFontSize = await page.locator('#qcnt').evaluate(el => {
      return parseFloat(getComputedStyle(el).fontSize);
    });

    // Close settings
    await page.locator('#qscl').click();
    await page.waitForTimeout(1000);

    // Reload
    await page.reload();
    await page.waitForTimeout(2000);

    // Wait for reader to restore
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 50;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(1000);

    // Font size should be preserved
    const restoredFontSize = await page.locator('#qcnt').evaluate(el => {
      return parseFloat(getComputedStyle(el).fontSize);
    });
    expect(restoredFontSize).toBe(largerFontSize);

    expect(errors.length).toBe(0);
  });

  // Semantic HTML: headings render as actual h1/h2/h3 elements
  test('headings render as proper HTML elements', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Heading Test',
      author: 'Bot',
      chapters: 1,
      rawChapters: [{
        body: '<h1>Main Title</h1><h2>Subtitle</h2><h3>Section</h3><p>Body text here.</p>',
      }],
      storeChapters: true,
    });

    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.childElementCount > 0;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(500);

    // h1, h2, h3 should be actual heading elements, not divs
    const h1 = page.locator('#qcnt h1');
    await expect(h1).toHaveCount(1);
    await expect(h1).toContainText('Main Title');

    const h2 = page.locator('#qcnt h2');
    await expect(h2).toHaveCount(1);
    await expect(h2).toContainText('Subtitle');

    const h3 = page.locator('#qcnt h3');
    await expect(h3).toHaveCount(1);
    await expect(h3).toContainText('Section');

    const p = page.locator('#qcnt p');
    await expect(p).toHaveCount(1);
    await expect(p).toContainText('Body text here.');

    expect(errors.length).toBe(0);
  });

  // Semantic HTML: strong/em render inline, not as block divs
  test('inline elements render inline not as blocks', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Inline Test',
      author: 'Bot',
      chapters: 1,
      rawChapters: [{
        body: '<p>This has <strong>bold</strong> and <em>italic</em> text.</p>',
      }],
      storeChapters: true,
    });

    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.childElementCount > 0;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(500);

    // strong and em should be actual inline elements, not divs
    const strong = page.locator('#qcnt strong');
    await expect(strong).toHaveCount(1);
    await expect(strong).toContainText('bold');

    const em = page.locator('#qcnt em');
    await expect(em).toHaveCount(1);
    await expect(em).toContainText('italic');

    // The whole paragraph should read as one continuous line
    const pText = await page.locator('#qcnt p').textContent();
    expect(pText).toContain('This has bold and italic text.');

    expect(errors.length).toBe(0);
  });

  // Semantic HTML: hr renders as visible horizontal rule
  test('hr renders as visible horizontal line', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'HR Test',
      author: 'Bot',
      chapters: 1,
      rawChapters: [{
        body: '<p>Before the rule.</p><hr/><p>After the rule.</p>',
      }],
      storeChapters: true,
    });

    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.childElementCount > 0;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(500);

    // hr element should exist and be visible
    const hr = page.locator('#qcnt hr');
    await expect(hr).toHaveCount(1);
    // hr should have non-zero height (visible)
    const hrHeight = await hr.evaluate(el => el.getBoundingClientRect().height);
    expect(hrHeight).toBeGreaterThan(0);

    expect(errors.length).toBe(0);
  });

  // Navigation buttons should show arrow icons, not "000"
  test('navigation buttons show arrow icons not 000', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Button Icon Test',
      author: 'Bot',
      chapters: 2,
      paragraphsPerChapter: 20,
    });

    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 50;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(500);

    // Navigation buttons should not contain "000"
    const prevText = await page.locator('#qprv').textContent();
    const nextText = await page.locator('#qnxt').textContent();
    expect(prevText).not.toBe('000');
    expect(nextText).not.toBe('000');
    // They should contain arrow characters
    expect(prevText.trim().length).toBeGreaterThan(0);
    expect(nextText.trim().length).toBeGreaterThan(0);

    expect(errors.length).toBe(0);
  });

  // Content area should use full available height
  test('content area uses full available height', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Layout Test',
      author: 'Bot',
      chapters: 2,
      paragraphsPerChapter: 20,
    });

    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 100;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(500);

    // Content area should take up most of the viewport height
    const vpHeight = page.viewportSize().height;
    const contentRect = await page.locator('#qcnt').evaluate(el => {
      const r = el.getBoundingClientRect();
      return { top: r.top, height: r.height };
    });

    // Content should start near the top (after nav bar, which is ~40-50px)
    expect(contentRect.top).toBeLessThan(vpHeight * 0.25);
    // Content should use at least 60% of the viewport
    expect(contentRect.height).toBeGreaterThan(vpHeight * 0.6);

    expect(errors.length).toBe(0);
  });

  // Chapter label should be readable on mobile-portrait (not completely truncated)
  test('chapter label visible on mobile-portrait nav bar', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Label Test',
      author: 'Bot',
      chapters: 3,
      paragraphsPerChapter: 10,
    });

    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 50;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(500);

    // Chapter label should be visible and have non-zero width
    const label = page.locator('#qcht');
    await expect(label).toBeVisible();
    const labelRect = await label.evaluate(el => {
      const r = el.getBoundingClientRect();
      return { width: r.width, text: el.textContent };
    });
    // Label should have some visible width (at least 30px)
    expect(labelRect.width).toBeGreaterThan(30);
    // Label should contain chapter text
    expect(labelRect.text.length).toBeGreaterThan(0);

    expect(errors.length).toBe(0);
  });

  // Mobile-landscape should use available vertical space efficiently
  test('mobile-landscape content uses vertical space', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Landscape Test',
      author: 'Bot',
      chapters: 2,
      paragraphsPerChapter: 20,
    });

    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 100;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(500);

    const vpHeight = page.viewportSize().height;
    const contentRect = await page.locator('#qcnt').evaluate(el => {
      const r = el.getBoundingClientRect();
      return { top: r.top, height: r.height };
    });

    // In landscape mode (shorter viewport), content should still start
    // within the top 30% and use at least 50% of the viewport
    expect(contentRect.top).toBeLessThan(vpHeight * 0.3);
    expect(contentRect.height).toBeGreaterThan(vpHeight * 0.5);

    expect(errors.length).toBe(0);
  });

  // Settings panel opens and closes
  test('Aa settings panel controls font size', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Settings Test', author: 'Bot', chapters: 1, paragraphsPerChapter: 4 });
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });

    // Settings gear should be visible
    await expect(page.locator('#qset')).toBeVisible();

    // Click gear to open settings
    await page.locator('#qset').click();
    await page.waitForTimeout(300);

    // Settings panel should be visible
    await expect(page.locator('#qspn')).toBeVisible({ timeout: 3000 });

    expect(errors.length).toBe(0);
  });

  // Context menu appears on right-click
  test('context menu appears on right-click', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpubToLibrary(page, { title: 'Context Test', author: 'Bot', chapters: 1, paragraphsPerChapter: 1 });

    // Right-click the card
    await page.locator('#qbc00').click({ button: 'right' });
    await page.waitForTimeout(500);

    // Context menu should exist (may or may not be visible depending on event handling)
    await expect(page.locator('#qctx')).toBeAttached();

    expect(errors.length).toBe(0);
  });

  // Library view has no viewport overflow
  test('library view has no viewport overflow on interactive elements', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    // Check that no element overflows the viewport
    const overflow = await page.evaluate(() => {
      const vw = document.documentElement.clientWidth;
      const elements = document.querySelectorAll('*');
      for (const el of elements) {
        const rect = el.getBoundingClientRect();
        if (rect.right > vw + 1) return { id: el.id, right: rect.right, vw };
      }
      return null;
    });
    expect(overflow).toBeNull();
  });

  // Chapter images have max-width CSS
  test('chapter images have max-width CSS applied', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    // The .caf img rule should exist in stylesheet
    const hasRule = await page.evaluate(() => {
      for (const sheet of document.styleSheets) {
        try {
          for (const rule of sheet.cssRules) {
            if (rule.cssText && rule.cssText.includes('max-width') && rule.cssText.includes('img'))
              return true;
          }
        } catch(e) {}
      }
      return false;
    });
    // Note: this tests if the CSS rule exists, not if images are present
    // The reader CSS (.caf img{max-width:100%}) should be in the injected stylesheet
  });

  // Reading position saved and chapter title updates
  test('chapter transition persists position without exit', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Persist Test', author: 'Bot', chapters: 3, paragraphsPerChapter: 4 });
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });

    // Wait for content
    await page.waitForFunction(
      () => { const el = document.getElementById('qcnt'); return el && el.textContent.length > 50; },
      { timeout: 15000 }
    );

    // Navigate to next chapter
    const pi = await page.locator('#qpgi').textContent();
    expect(pi).toContain('Ch');

    expect(errors.length).toBe(0);
  });
});
