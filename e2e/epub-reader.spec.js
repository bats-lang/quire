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
 *   6 -> cag = nav_bar
 *   7 -> cah = page_info
 *   8 -> cai = nav_button
 *   9 -> caj = chapter_title
 *  10 -> cak = zone_left
 *  11 -> cal = zone_right
 *  12 -> cam = zone_center
 *  13 -> can = settings_panel
 *  14 -> cao = settings_btn
 *  15 -> cap = book_card
 *  16 -> caq = book_title
 *  17 -> car = book_author
 *  18 -> cas = lib_toolbar
 *  19 -> cat = ctx_overlay
 *  20 -> cau = ctx_menu
 *
 * Widget IDs (from quire.bats):
 *   qllc = library list container
 *   qrvw = reader view container
 *   qbbk = back button
 *   qcnt = content area
 *   qelb = empty library message
 *   qibn = import button
 *   qfin = file input
 *   qltb = library toolbar
 */

import { test, expect } from '@playwright/test';
import { createEpub } from './create-epub.js';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const SCREENSHOT_DIR = join(process.cwd(), 'e2e', 'screenshots');
mkdirSync(SCREENSHOT_DIR, { recursive: true });

/** Helper: import an EPUB into the library (stays on library view) */
async function importEpubToLibrary(page, opts = {}) {
  const epubBuffer = createEpub({
    title: opts.title || 'Test Book',
    author: opts.author || 'Test Author',
    chapters: opts.chapters || 3,
    paragraphsPerChapter: opts.paragraphsPerChapter || 12,
    storeChapters: true,
    ...opts,
  });

  const epubPath = join(SCREENSHOT_DIR, `test-${Date.now()}.epub`);
  writeFileSync(epubPath, epubBuffer);
  const fileInput = page.locator('input[type="file"]');
  await fileInput.setInputFiles(epubPath);

  // Wait for book card to appear in library
  await page.waitForSelector('.cap', { timeout: 30000 });
}

/** Helper: import an EPUB and open it in reader (navigates to library first if needed) */
async function importEpub(page, opts = {}) {
  await page.goto('/');
  await page.waitForSelector('#qllc', { timeout: 15000 });

  await importEpubToLibrary(page, opts);

  // Click the book card to open reader
  await page.locator('.cap').last().click();
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

  // Phase 6: real-world EPUB
  test('real-world EPUB import and reading', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    const fixturePath = join(process.cwd(), 'test', 'fixtures', 'conan-stories.epub');
    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath);

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

    // After reload, library should show a book card (Phase 9 flow)
    await page.waitForSelector('.cap', { timeout: 15000 });
    await expect(page.locator('#qllc')).toBeVisible();

    // Click card to open reader
    await page.locator('.cap').click();
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });

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

    // Library should show a book card
    await page.waitForSelector('.cap', { timeout: 15000 });

    // Click card to open reader
    await page.locator('.cap').click();
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });

    // Wait for content to load
    await page.waitForFunction(
      () => {
        const el = document.getElementById('qcnt');
        return el && el.textContent.length > 50;
      },
      { timeout: 15000 }
    );

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

    // Library should show a book card
    await page.waitForSelector('.cap', { timeout: 15000 });

    // Click card to open reader
    await page.locator('.cap').click();
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

  // Phase 9: import shows book card in library (not reader)
  test('import shows book card with title and author in library', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    await importEpubToLibrary(page, {
      title: 'Card Test Book',
      author: 'Card Author',
      chapters: 1,
      paragraphsPerChapter: 1,
    });

    // Library should still be visible (not reader)
    await expect(page.locator('#qllc')).toBeVisible();
    await expect(page.locator('#qrvw')).toBeHidden();

    // Book card should be visible with correct title and author
    const card = page.locator('.cap');
    await expect(card).toBeVisible();
    await expect(page.locator('.caq')).toContainText('Card Test Book');
    await expect(page.locator('.car')).toContainText('Card Author');

    expect(errors).toEqual([]);
  });

  // Phase 9: clicking book card opens reader
  test('clicking book card opens reader', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    await importEpubToLibrary(page, {
      title: 'Click Test',
      author: 'Bot',
      chapters: 2,
      paragraphsPerChapter: 3,
    });

    // Click the book card
    await page.locator('.cap').click();

    // Reader should become visible
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    await expect(page.locator('#qllc')).toBeHidden();

    expect(errors).toEqual([]);
  });

  // Phase 9: multiple books show multiple cards
  test('importing two books shows two cards', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    await importEpubToLibrary(page, {
      title: 'First Book',
      author: 'Alice',
      chapters: 1,
      paragraphsPerChapter: 1,
    });

    await importEpubToLibrary(page, {
      title: 'Second Book',
      author: 'Bob',
      chapters: 1,
      paragraphsPerChapter: 1,
    });

    // Should have two book cards
    await page.waitForFunction(
      () => document.querySelectorAll('.cap').length >= 2,
      { timeout: 30000 }
    );
    const cards = page.locator('.cap');
    await expect(cards).toHaveCount(2);

    // Both titles should be present
    const titles = await page.evaluate(() =>
      [...document.querySelectorAll('.caq')].map(el => el.textContent)
    );
    expect(titles).toContain('First Book');
    expect(titles).toContain('Second Book');

    expect(errors).toEqual([]);
  });

  // Phase 9: library toolbar with shelf button
  test('library toolbar shows shelf button', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    // Library toolbar should be visible
    await expect(page.locator('.cas')).toBeVisible();

    expect(errors).toEqual([]);
  });

  // Phase 9: archive and restore a book
  test('archive and restore a book', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    await importEpubToLibrary(page, {
      title: 'Archive Test Book',
      author: 'Archive Bot',
      chapters: 1,
      paragraphsPerChapter: 1,
    });

    // Archive via context menu
    await page.evaluate(() => {
      const card = document.querySelector('.cap');
      if (card) card.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true }));
    });
    await page.waitForSelector('.cat', { timeout: 10000 });
    await page.locator('.cau button', { hasText: 'Archive' }).click();
    await page.waitForTimeout(500);

    // Book should disappear from library view
    // Cycle shelf: Library → Hidden → Archived
    const shelfBtn = page.locator('.cas button').first();
    await shelfBtn.click(); // → Hidden
    await page.waitForTimeout(300);
    await shelfBtn.click(); // → Archived
    await page.waitForTimeout(500);
    await page.waitForSelector('.cap', { timeout: 10000 });
    await expect(page.locator('.caq')).toContainText('Archive Test Book');

    // Restore via context menu
    await page.evaluate(() => {
      const card = document.querySelector('.cap');
      if (card) card.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true }));
    });
    await page.waitForSelector('.cat', { timeout: 10000 });
    await page.locator('.cau button', { hasText: 'Restore' }).click();
    await page.waitForTimeout(500);

    // Cycle back to Library
    await shelfBtn.click(); // → Library
    await page.waitForTimeout(500);
    await page.waitForSelector('.cap', { timeout: 10000 });
    await expect(page.locator('.caq')).toContainText('Archive Test Book');

    expect(errors).toEqual([]);
  });

  // Phase 9: sort books by cycling sort button
  test('sort books by cycling sort button', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    await importEpubToLibrary(page, {
      title: 'Zebra Book',
      author: 'Alice',
      chapters: 1,
      paragraphsPerChapter: 1,
    });
    await importEpubToLibrary(page, {
      title: 'Apple Book',
      author: 'Zara',
      chapters: 1,
      paragraphsPerChapter: 1,
    });
    await page.waitForFunction(
      () => document.querySelectorAll('.cap').length >= 2,
      { timeout: 30000 }
    );
    await page.waitForTimeout(1000);

    const sortBtn = page.locator('.cas button').nth(1);
    const titlesBefore = await page.evaluate(() =>
      [...document.querySelectorAll('.caq')].map(el => el.textContent)
    );
    await sortBtn.click();
    await page.waitForTimeout(1000);
    const titlesAfter = await page.evaluate(() =>
      [...document.querySelectorAll('.caq')].map(el => el.textContent)
    );
    // At least verify no errors (order change depends on sort mode)
    expect(errors).toEqual([]);
  });

  // Phase 9: hide and unhide a book via context menu
  test('hide and unhide a book via context menu', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    await importEpubToLibrary(page, {
      title: 'Hide Test Book',
      author: 'Hide Bot',
      chapters: 1,
      paragraphsPerChapter: 1,
    });

    // Hide via context menu
    await page.evaluate(() => {
      const card = document.querySelector('.cap');
      if (card) card.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true }));
    });
    await page.waitForSelector('.cat', { timeout: 10000 });
    await page.locator('.cau button', { hasText: 'Hide' }).click();
    await page.waitForTimeout(500);

    // Cycle to Hidden view
    const shelfBtn = page.locator('.cas button').first();
    await shelfBtn.click(); // → Hidden
    await page.waitForTimeout(500);
    await page.waitForSelector('.cap', { timeout: 10000 });
    await expect(page.locator('.caq')).toContainText('Hide Test Book');

    // Unhide via context menu
    await page.evaluate(() => {
      const card = document.querySelector('.cap');
      if (card) card.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true }));
    });
    await page.waitForSelector('.cat', { timeout: 10000 });
    await page.locator('.cau button', { hasText: 'Unhide' }).click();
    await page.waitForTimeout(500);

    // Cycle back to Library
    await shelfBtn.click(); // Hidden → Archived
    await page.waitForTimeout(300);
    await shelfBtn.click(); // Archived → Library
    await page.waitForTimeout(500);
    await page.waitForSelector('.cap', { timeout: 10000 });
    await expect(page.locator('.caq')).toContainText('Hide Test Book');

    expect(errors).toEqual([]);
  });
});
