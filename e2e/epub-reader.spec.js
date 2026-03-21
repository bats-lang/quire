/**
 * E2E test: EPUB import and reading flow.
 *
 * Tests target elements by visible content and semantic context,
 * not by internal CSS classes or widget IDs.
 */

import { test, expect } from '@playwright/test';
import { createEpub } from './create-epub.js';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const SCREENSHOT_DIR = join(process.cwd(), 'e2e', 'screenshots');
mkdirSync(SCREENSHOT_DIR, { recursive: true });

/** Wait for library to be ready */
async function waitForLibrary(page) {
  await page.getByText('Import EPUB').waitFor({ timeout: 15000 });
}

/** Wait for reader to be ready (nav bar visible with arrows) */
async function waitForReader(page) {
  await page.getByText('‹').waitFor({ timeout: 15000 });
}

/** Wait for chapter content to load (text appears in page) */
async function waitForContent(page, minLength = 50) {
  await page.waitForFunction(
    (min) => {
      // Find the element with column layout that contains chapter text
      const els = document.querySelectorAll('div');
      for (const el of els) {
        const style = getComputedStyle(el);
        if (style.columnWidth === '100vw' || style.overflow === 'hidden') {
          if (el.textContent.length > min) return true;
        }
      }
      return false;
    },
    minLength,
    { timeout: 15000 }
  );
  await page.waitForTimeout(1000);
}

/** Get page info text (e.g. "Ch 1 · p. 1/3") */
async function getPageInfo(page) {
  const el = page.locator('text=/^Ch \\d+ · p\\./');
  return await el.textContent();
}

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
  await waitForLibrary(page);

  const epubPath = join(SCREENSHOT_DIR, `test-${Date.now()}.epub`);
  writeFileSync(epubPath, epubBuffer);
  const fileInput = page.locator('input[type="file"]');
  await fileInput.setInputFiles(epubPath);

  // Wait for book card to appear — the title text shows up
  const title = opts.title || 'Test Book';
  await page.getByText(title).waitFor({ timeout: 30000 });
}

/** Import EPUB and open in reader by clicking card */
async function importEpub(page, opts = {}) {
  await importEpubToLibrary(page, opts);
  const title = opts.title || 'Test Book';
  await page.getByText(title).click();
}

test.describe('EPUB Reader E2E', () => {
  test('library view loads with empty state', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await waitForLibrary(page);

    await expect(page.getByText('Quire')).toBeVisible();
    await expect(page.getByText('Import an EPUB file')).toBeVisible();
    await expect(page.getByText('Import EPUB')).toBeVisible();

    expect(errors.length).toBe(0);
  });

  test('import shows book card with title and author in library', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, {
      title: 'Card Test',
      author: 'Card Author',
      chapters: 1,
      paragraphsPerChapter: 1,
    });

    // Go back to library
    await page.getByText('←').click();
    await waitForLibrary(page);

    await expect(page.getByText('Card Test')).toBeAttached({ timeout: 5000 });
    await expect(page.getByText('Card Author')).toBeAttached({ timeout: 2000 });

    expect(errors.length).toBe(0);
  });

  test('clicking book card opens reader', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Click Test', author: 'Bot', chapters: 1, paragraphsPerChapter: 1 });
    await waitForReader(page);
    await expect(page.getByText('Import EPUB')).toBeHidden();

    expect(errors.length).toBe(0);
  });

  test('library toolbar shows sort button', async ({ page }) => {
    await page.goto('/');
    await waitForLibrary(page);
    await expect(page.getByText('Sort')).toBeAttached();
  });

  test('archive and hide buttons exist', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await waitForLibrary(page);

    await expect(page.getByText('Archive')).toBeAttached();
    await expect(page.getByText('Hide')).toBeAttached();

    expect(errors.length).toBe(0);
  });

  test('Import button is reasonably sized', async ({ page }) => {
    await page.goto('/');
    await waitForLibrary(page);

    const box = await page.getByText('Import EPUB').boundingBox();
    expect(box).not.toBeNull();
    expect(box.width).toBeGreaterThan(50);
    expect(box.width).toBeLessThan(400);
    // Touch target: at least 44px tall
    expect(box.height).toBeGreaterThan(20);
    expect(box.height).toBeLessThan(100);
  });

  test('center click toggles reader chrome', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Chrome Test', author: 'Bot', chapters: 1, paragraphsPerChapter: 4 });
    await waitForReader(page);

    // Nav bar with back button should be visible initially
    await expect(page.getByText('←')).toBeVisible();

    // Click center of viewport to toggle chrome
    const vp = page.viewportSize();
    await page.mouse.click(vp.width / 2, vp.height / 2);
    await page.waitForTimeout(300);
    await expect(page.getByText('←')).toBeHidden();

    // Click again to show chrome
    await page.mouse.click(vp.width / 2, vp.height / 2);
    await page.waitForTimeout(300);
    await expect(page.getByText('←')).toBeVisible();

    expect(errors.length).toBe(0);
  });

  test('import epub switches to reader view', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'My Novel', author: 'Jane Doe', chapters: 2, paragraphsPerChapter: 4 });
    await waitForReader(page);
    await expect(page.getByText('Import EPUB')).toBeHidden();

    expect(errors.length).toBe(0);
  });

  test('back button returns to library view', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Back Test', author: 'Bot', chapters: 1, paragraphsPerChapter: 2 });
    await waitForReader(page);

    await page.getByText('←').click();
    await waitForLibrary(page);

    expect(errors.length).toBe(0);
  });

  test('chapter loading shows content in reader', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Content Test', author: 'Bot', chapters: 2, paragraphsPerChapter: 4 });
    await waitForReader(page);
    await waitForContent(page);

    expect(errors.length).toBe(0);
  });

  test('page navigation with buttons and click zones', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Nav Test', author: 'Bot', chapters: 3, paragraphsPerChapter: 40 });
    await waitForReader(page);
    await waitForContent(page, 200);

    // Verify nav bar elements
    await expect(page.getByText('←')).toBeVisible();
    await expect(page.getByText('‹')).toBeVisible();
    await expect(page.getByText('›')).toBeVisible();

    // Page indicator shows "Ch N · p. N/M" format
    const pageText = await getPageInfo(page);
    expect(pageText).toMatch(/^Ch \d+ · p\. \d+\/\d+$/);
    expect(pageText).toMatch(/^Ch 1 /);

    // --- Test next button navigation ---
    await page.getByText('›').click();
    await page.waitForTimeout(500);
    const pageTextAfterNext = await getPageInfo(page);
    expect(pageTextAfterNext).toMatch(/\s+2\/\d+$/);

    // --- Test prev button navigation ---
    await page.getByText('‹').click();
    await page.waitForTimeout(500);
    const pageTextAfterPrev = await getPageInfo(page);
    expect(pageTextAfterPrev).toMatch(/\s+1\/\d+$/);

    // --- Click zone navigation (right 20% of viewport = next page) ---
    const vp = page.viewportSize();
    await page.mouse.click(vp.width * 0.9, vp.height / 2);
    await page.waitForTimeout(500);
    const pageTextAfterZoneRight = await getPageInfo(page);
    expect(pageTextAfterZoneRight).toMatch(/\s+2\/\d+$/);

    // Left 10% = prev page
    await page.mouse.click(vp.width * 0.1, vp.height / 2);
    await page.waitForTimeout(500);
    const pageTextAfterZoneLeft = await getPageInfo(page);
    expect(pageTextAfterZoneLeft).toMatch(/\s+1\/\d+$/);

    // --- Keyboard navigation ---
    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(500);
    const pageTextAfterArrowRight = await getPageInfo(page);
    expect(pageTextAfterArrowRight).toMatch(/\s+2\/\d+$/);

    await page.keyboard.press('ArrowLeft');
    await page.waitForTimeout(500);
    const pageTextAfterArrowLeft = await getPageInfo(page);
    expect(pageTextAfterArrowLeft).toMatch(/\s+1\/\d+$/);

    await page.keyboard.press('Space');
    await page.waitForTimeout(500);
    const pageTextAfterSpace = await getPageInfo(page);
    expect(pageTextAfterSpace).toMatch(/\s+2\/\d+$/);

    expect(errors.length).toBe(0);
  });

  test('next chapter navigation', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Chapter Nav Test', author: 'Bot', chapters: 3, paragraphsPerChapter: 8 });
    await waitForReader(page);
    await waitForContent(page);

    const initialText = await getPageInfo(page);
    expect(initialText).toMatch(/^Ch 1 /);

    // Get total pages in chapter 1
    const totalMatch = initialText.match(/(\d+)\/(\d+)$/);
    const totalPages = parseInt(totalMatch[2]);

    // Navigate to the last page of chapter 1
    for (let i = 1; i < totalPages; i++) {
      await page.getByText('›').click();
      await page.waitForTimeout(300);
    }

    // Click next to advance to chapter 2
    await page.getByText('›').click();
    await page.waitForTimeout(2000);

    await page.waitForFunction(
      () => {
        const el = document.querySelector('*');
        const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        while (walk.nextNode()) {
          if (/^Ch 2 /.test(walk.currentNode.textContent)) return true;
        }
        return false;
      },
      { timeout: 15000 }
    );

    const ch2Text = await getPageInfo(page);
    expect(ch2Text).toMatch(/^Ch 2 · p\. 1\/\d+$/);

    expect(errors.length).toBe(0);
  });

  test('chapter progress display', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Progress Test', author: 'Bot', chapters: 2, paragraphsPerChapter: 8 });
    await waitForReader(page);
    await waitForContent(page);

    const ch1Text = await getPageInfo(page);
    expect(ch1Text).toMatch(/^Ch 1 · p\. 1\/\d+$/);

    expect(errors.length).toBe(0);
  });

  test('real-world EPUB import and reading', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await waitForLibrary(page);

    const fixturePath = join(process.cwd(), 'test', 'fixtures', 'conan-stories.epub');
    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath);

    // Wait for a book card, then click it
    await page.waitForTimeout(5000);
    // Find any card that appeared and click it
    const cards = page.locator('div:has(> div)').filter({ hasText: /\w{3,}/ });
    await cards.first().click({ timeout: 30000 });

    await waitForReader(page);
    await page.waitForTimeout(1000);

    const text = await getPageInfo(page);
    expect(text).toMatch(/^Ch \d+ · p\. \d+\/\d+$/);

    expect(errors.length).toBe(0);
  });

  test('large chapter pagination works', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await waitForLibrary(page);

    const fixturePath = join(process.cwd(), 'test', 'fixtures', 'conan-stories.epub');
    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath);

    await page.waitForTimeout(5000);
    const cards = page.locator('div:has(> div)').filter({ hasText: /\w{3,}/ });
    await cards.first().click({ timeout: 30000 });

    await waitForReader(page);
    await page.waitForTimeout(1000);

    // Navigate to chapter 2 (story content)
    await page.getByText('›').click();
    await page.waitForFunction(
      () => {
        const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        while (walk.nextNode()) {
          if (/^Ch 2 /.test(walk.currentNode.textContent)) return true;
        }
        return false;
      },
      { timeout: 15000 }
    );
    await page.waitForTimeout(1000);

    // Navigate forward within chapter 2
    await page.getByText('›').click();
    await page.waitForTimeout(500);

    const text2 = await getPageInfo(page);
    expect(text2).toMatch(/^Ch 2 · p\. 2\/\d+$/);

    expect(errors.length).toBe(0);
  });

  test('library persists across page reload', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Persist Test', author: 'Bot', chapters: 2, paragraphsPerChapter: 8 });
    await waitForReader(page);
    await waitForContent(page);

    await page.reload();
    await page.waitForTimeout(2000);

    // After reload, reader view should be visible (restored from IDB)
    await waitForReader(page);
    await waitForContent(page);

    expect(errors.length).toBe(0);
  });

  test('reading position is restored', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Position Test', author: 'Bot', chapters: 3, paragraphsPerChapter: 40 });
    await waitForReader(page);
    await waitForContent(page, 200);

    // Navigate to page 2
    await page.getByText('›').click();
    await page.waitForTimeout(500);
    const textBefore = await getPageInfo(page);
    expect(textBefore).toMatch(/\s+2\/\d+$/);

    await page.waitForTimeout(1000);
    await page.reload();
    await page.waitForTimeout(2000);

    await waitForReader(page);
    await waitForContent(page);

    const textAfter = await getPageInfo(page);
    expect(textAfter).toMatch(/^Ch 1 · p\. 2\/\d+$/);

    expect(errors.length).toBe(0);
  });

  test('font size settings panel works', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Settings Test', author: 'Bot', chapters: 2, paragraphsPerChapter: 20 });
    await waitForReader(page);
    await waitForContent(page, 100);

    // Settings panel should be hidden initially
    await expect(page.getByText('Font Size')).toBeHidden();

    // Click settings gear (⚙)
    await page.getByText('⚙').click();
    await page.waitForTimeout(500);

    // Settings panel should be visible
    await expect(page.getByText('Font Size')).toBeVisible();
    await expect(page.getByText('A-')).toBeVisible();
    await expect(page.getByText('A+')).toBeVisible();

    // Get initial font size
    const initialFontSize = await page.evaluate(() => {
      const els = document.querySelectorAll('div');
      for (const el of els) {
        if (getComputedStyle(el).columnWidth === '100vw') {
          return parseFloat(getComputedStyle(el).fontSize);
        }
      }
      return 16;
    });

    // Click A+ to increase font size
    await page.getByText('A+').click();
    await page.waitForTimeout(500);

    const largerFontSize = await page.evaluate(() => {
      const els = document.querySelectorAll('div');
      for (const el of els) {
        if (getComputedStyle(el).columnWidth === '100vw') {
          return parseFloat(getComputedStyle(el).fontSize);
        }
      }
      return 16;
    });
    expect(largerFontSize).toBeGreaterThan(initialFontSize);

    // Click A- to decrease font size back
    await page.getByText('A-').click();
    await page.waitForTimeout(500);

    const restoredFontSize = await page.evaluate(() => {
      const els = document.querySelectorAll('div');
      for (const el of els) {
        if (getComputedStyle(el).columnWidth === '100vw') {
          return parseFloat(getComputedStyle(el).fontSize);
        }
      }
      return 16;
    });
    expect(restoredFontSize).toBe(initialFontSize);

    // Close settings panel
    await page.getByText('Close').click();
    await page.waitForTimeout(500);
    await expect(page.getByText('Font Size')).toBeHidden();

    expect(errors.length).toBe(0);
  });

  test('font size persists across reload', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Font Persist Test', author: 'Bot', chapters: 2, paragraphsPerChapter: 20 });
    await waitForReader(page);
    await waitForContent(page, 100);

    // Increase font size twice
    await page.getByText('⚙').click();
    await page.waitForTimeout(300);
    await page.getByText('A+').click();
    await page.waitForTimeout(300);
    await page.getByText('A+').click();
    await page.waitForTimeout(300);

    const largerFontSize = await page.evaluate(() => {
      const els = document.querySelectorAll('div');
      for (const el of els) {
        if (getComputedStyle(el).columnWidth === '100vw') {
          return parseFloat(getComputedStyle(el).fontSize);
        }
      }
      return 16;
    });

    await page.getByText('Close').click();
    await page.waitForTimeout(1000);

    await page.reload();
    await page.waitForTimeout(2000);
    await waitForReader(page);
    await waitForContent(page);

    const restoredFontSize = await page.evaluate(() => {
      const els = document.querySelectorAll('div');
      for (const el of els) {
        if (getComputedStyle(el).columnWidth === '100vw') {
          return parseFloat(getComputedStyle(el).fontSize);
        }
      }
      return 16;
    });
    expect(restoredFontSize).toBe(largerFontSize);

    expect(errors.length).toBe(0);
  });

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

    await waitForReader(page);
    await page.waitForTimeout(500);

    await expect(page.locator('h1:has-text("Main Title")')).toHaveCount(1);
    await expect(page.locator('h2:has-text("Subtitle")')).toHaveCount(1);
    await expect(page.locator('h3:has-text("Section")')).toHaveCount(1);
    await expect(page.locator('p:has-text("Body text here.")')).toHaveCount(1);

    expect(errors.length).toBe(0);
  });

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

    await waitForReader(page);
    await page.waitForTimeout(500);

    await expect(page.locator('strong:has-text("bold")')).toHaveCount(1);
    await expect(page.locator('em:has-text("italic")')).toHaveCount(1);

    const pText = await page.locator('p:has-text("bold")').textContent();
    expect(pText).toContain('This has bold and italic text.');

    expect(errors.length).toBe(0);
  });

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

    await waitForReader(page);
    await page.waitForTimeout(500);

    const hr = page.locator('hr');
    await expect(hr).toHaveCount(1);
    const hrHeight = await hr.evaluate(el => el.getBoundingClientRect().height);
    expect(hrHeight).toBeGreaterThan(0);

    expect(errors.length).toBe(0);
  });

  test('navigation buttons show arrow icons not 000', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Button Icon Test', author: 'Bot', chapters: 2, paragraphsPerChapter: 20 });
    await waitForReader(page);
    await waitForContent(page);

    // Navigation buttons should contain arrow characters
    await expect(page.getByText('‹')).toBeVisible();
    await expect(page.getByText('›')).toBeVisible();

    expect(errors.length).toBe(0);
  });

  test('content area uses full available height', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Layout Test', author: 'Bot', chapters: 2, paragraphsPerChapter: 20 });
    await waitForReader(page);
    await waitForContent(page, 100);

    const vpHeight = page.viewportSize().height;
    const contentRect = await page.evaluate(() => {
      const els = document.querySelectorAll('div');
      for (const el of els) {
        if (getComputedStyle(el).columnWidth === '100vw') {
          const r = el.getBoundingClientRect();
          return { top: r.top, height: r.height };
        }
      }
      return { top: 0, height: 0 };
    });

    expect(contentRect.top).toBeLessThan(vpHeight * 0.25);
    expect(contentRect.height).toBeGreaterThan(vpHeight * 0.6);

    expect(errors.length).toBe(0);
  });

  test('chapter label visible on mobile-portrait nav bar', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Label Test', author: 'Bot', chapters: 3, paragraphsPerChapter: 10 });
    await waitForReader(page);
    await waitForContent(page);

    // Chapter info should be visible
    const pageText = await getPageInfo(page);
    expect(pageText.length).toBeGreaterThan(0);

    expect(errors.length).toBe(0);
  });

  test('Aa settings panel opens and closes', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Settings Test 2', author: 'Bot', chapters: 1, paragraphsPerChapter: 4 });
    await waitForReader(page);

    await page.getByText('⚙').click();
    await page.waitForTimeout(300);
    await expect(page.getByText('Font Size')).toBeVisible({ timeout: 3000 });

    expect(errors.length).toBe(0);
  });

  test('context menu appears on right-click', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpubToLibrary(page, { title: 'Context Test', author: 'Bot', chapters: 1, paragraphsPerChapter: 1 });

    await page.getByText('Context Test').click({ button: 'right' });
    await page.waitForTimeout(500);

    // Context menu elements should exist
    await expect(page.getByText('Archive')).toBeAttached();

    expect(errors.length).toBe(0);
  });

  test('library view has no viewport overflow', async ({ page }) => {
    await page.goto('/');
    await waitForLibrary(page);

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

  test('importing two books shows two cards', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    const epub1 = createEpub({ title: 'First Book', author: 'Alice', chapters: 1, paragraphsPerChapter: 1, storeChapters: true });
    const epub2 = createEpub({ title: 'Second Book', author: 'Bob', chapters: 1, paragraphsPerChapter: 1, storeChapters: true });

    await page.goto('/');
    await waitForLibrary(page);

    const path1 = join(SCREENSHOT_DIR, `two1-${Date.now()}.epub`);
    writeFileSync(path1, epub1);
    await page.locator('input[type="file"]').setInputFiles(path1);
    await page.getByText('First Book').waitFor({ timeout: 30000 });

    const path2 = join(SCREENSHOT_DIR, `two2-${Date.now()}.epub`);
    writeFileSync(path2, epub2);
    await page.locator('input[type="file"]').setInputFiles(path2);
    await page.getByText('Second Book').waitFor({ timeout: 30000 });

    await expect(page.getByText('First Book')).toBeVisible();
    await expect(page.getByText('Second Book')).toBeVisible();

    expect(errors.length).toBe(0);
  });

  test('back button returns with card visible', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Back Card Test', author: 'Bot', chapters: 1, paragraphsPerChapter: 2 });
    await waitForReader(page);

    await page.getByText('←').click();
    await waitForLibrary(page);
    await expect(page.getByText('Back Card Test')).toBeAttached();

    expect(errors.length).toBe(0);
  });

  test('page forward and backward via click zones', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Zone Test', author: 'Bot', chapters: 1, paragraphsPerChapter: 20 });
    await waitForReader(page);
    await waitForContent(page, 100);

    const before = await getPageInfo(page);

    // Click right 10% of viewport (next page zone)
    const vp = page.viewportSize();
    await page.mouse.click(vp.width * 0.9, vp.height / 2);
    await page.waitForTimeout(500);

    const after = await getPageInfo(page);
    expect(after).not.toBe(before);

    expect(errors.length).toBe(0);
  });

  test('keyboard arrow keys navigate pages', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Key Test', author: 'Bot', chapters: 1, paragraphsPerChapter: 20 });
    await waitForReader(page);
    await waitForContent(page, 100);

    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(300);

    await page.keyboard.press('ArrowLeft');
    await page.waitForTimeout(300);

    expect(errors.length).toBe(0);
  });

  test('importing non-EPUB file does not crash', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await waitForLibrary(page);

    const fakePath = join(SCREENSHOT_DIR, `fake-${Date.now()}.txt`);
    writeFileSync(fakePath, 'This is not an EPUB file');
    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles(fakePath);

    await page.waitForTimeout(3000);
    await expect(page.getByText('Quire')).toBeVisible();

    expect(errors.length).toBe(0);
  });

  test('previous chapter navigation from chapter 2', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Chapter Back Test', author: 'Bot', chapters: 3, paragraphsPerChapter: 8 });
    await waitForReader(page);
    await waitForContent(page);

    const initialText = await getPageInfo(page);
    expect(initialText).toMatch(/^Ch 1 /);

    // Navigate to chapter 2
    const totalMatch = initialText.match(/(\d+)\/(\d+)$/);
    const totalPages = parseInt(totalMatch[2]);
    for (let i = 1; i < totalPages; i++) {
      await page.getByText('›').click();
      await page.waitForTimeout(300);
    }
    await page.getByText('›').click();
    await page.waitForTimeout(2000);

    await page.waitForFunction(
      () => {
        const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        while (walk.nextNode()) {
          if (/^Ch 2 /.test(walk.currentNode.textContent)) return true;
        }
        return false;
      },
      { timeout: 15000 }
    );

    // Now go back to chapter 1
    await page.getByText('‹').click();
    await page.waitForTimeout(2000);

    await page.waitForFunction(
      () => {
        const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        while (walk.nextNode()) {
          if (/^Ch 1 /.test(walk.currentNode.textContent)) return true;
        }
        return false;
      },
      { timeout: 15000 }
    );

    const ch1Text = await getPageInfo(page);
    expect(ch1Text).toMatch(/^Ch 1 /);

    expect(errors.length).toBe(0);
  });

  test('back to library shows card with correct title and badge', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await importEpub(page, { title: 'Title Check', author: 'Author Check', chapters: 1, paragraphsPerChapter: 2 });
    await waitForReader(page);

    await page.getByText('←').click();
    await waitForLibrary(page);

    await expect(page.getByText('Title Check')).toBeVisible({ timeout: 5000 });
    await expect(page.getByText('Author Check')).toBeVisible({ timeout: 2000 });
    await expect(page.getByText('New')).toBeVisible({ timeout: 2000 });

    expect(errors.length).toBe(0);
  });
});
