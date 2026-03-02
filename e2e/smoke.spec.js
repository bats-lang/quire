/**
 * Smoke test: quick sanity check that WASM loads and library renders.
 *
 * Tests are progressively uncommented as features are implemented.
 */

import { test, expect } from '@playwright/test';

test.describe('Smoke', () => {
  test('WASM loads and shows library', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => {
      errors.push(err.message);
      console.error('PAGE ERROR:', err.message);
    });

    // App loads and shows library
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Empty library message visible
    const emptyMsg = page.locator('.empty-lib');
    await expect(emptyMsg).toBeVisible();
    await expect(emptyMsg).toContainText('No books yet');

    // Import button visible
    const importBtn = page.locator('.import-btn');
    await expect(importBtn).toBeVisible();

    // No crashes
    expect(errors.length).toBe(0);
  });
});
