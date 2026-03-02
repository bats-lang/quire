/**
 * Smoke test: quick sanity check that WASM loads, import works,
 * and basic reader opens.
 *
 * Tests are progressively uncommented as features are implemented.
 */

import { test, expect } from '@playwright/test';
// import { createEpub } from './create-epub.js';
// import { writeFileSync, mkdirSync } from 'node:fs';
// import { join } from 'node:path';

// const SCREENSHOT_DIR = join(process.cwd(), 'e2e', 'screenshots');
// mkdirSync(SCREENSHOT_DIR, { recursive: true });

test.describe('Smoke', () => {
  test.skip('WASM loads and EPUB import works', async ({ page }) => {
    // ALL COMMENTED OUT — uncomment progressively as features land
    //
    // const errors = [];
    // page.on('pageerror', err => errors.push(err.message));
    //
    // const epubBuffer = createEpub({
    //   title: 'Smoke Test',
    //   author: 'Bot',
    //   chapters: 1,
    //   paragraphsPerChapter: 2,
    // });
    //
    // await page.goto('/');
    // await page.waitForSelector('.library-list', { timeout: 15000 });
    //
    // const fileInput = page.locator('input[type="file"]');
    // const epubPath = join(SCREENSHOT_DIR, 'smoke-test.epub');
    // writeFileSync(epubPath, epubBuffer);
    // await fileInput.setInputFiles(epubPath);
    //
    // await page.waitForSelector('.book-card', { timeout: 30000 });
    // const bookTitle = page.locator('.book-title');
    // await expect(bookTitle).toContainText('Smoke Test');
    //
    // await page.locator('.book-card').click();
    // await page.waitForSelector('.chapter-container', { timeout: 15000 });
    //
    // const pageInfo = page.locator('.page-info');
    // await expect(pageInfo).toBeVisible();
    //
    // expect(errors.length).toBe(0);
  });
});
