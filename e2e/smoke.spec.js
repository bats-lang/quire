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
  test('WASM loads and empty library renders', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const emptyLib = page.locator('.empty-lib');
    await expect(emptyLib).toBeVisible();
    await expect(emptyLib).toContainText('No books yet');

    const importBtn = page.locator('.import-btn');
    await expect(importBtn).toBeVisible();

    expect(errors.length).toBe(0);
  });
});
