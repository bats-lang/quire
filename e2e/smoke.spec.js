/**
 * Smoke test: quick sanity check that WASM loads and library renders.
 */

import { test, expect } from '@playwright/test';

test.describe('Smoke', () => {
  test('WASM loads and shows library', async ({ page }) => {
    const errors = [];
    const logs = [];
    page.on('pageerror', err => {
      errors.push(err.message);
      console.error('PAGE ERROR:', err.message);
    });
    page.on('console', msg => {
      logs.push(`[${msg.type()}] ${msg.text()}`);
    });

    await page.goto('/');

    // Give WASM time to load and execute
    await page.waitForTimeout(3000);

    // Debug: dump page content
    const html = await page.content();
    console.log('PAGE HTML (first 2000 chars):', html.substring(0, 2000));
    console.log('CONSOLE LOGS:', logs);
    console.log('PAGE ERRORS:', errors);

    // Check for bats-root
    const root = page.locator('#bats-root');
    const rootHTML = await root.innerHTML();
    console.log('BATS-ROOT innerHTML:', rootHTML);

    await page.waitForSelector('.library-list', { timeout: 15000 });

    const emptyMsg = page.locator('.empty-lib');
    await expect(emptyMsg).toBeVisible();
    await expect(emptyMsg).toContainText('No books yet');

    const importBtn = page.locator('.import-btn');
    await expect(importBtn).toBeVisible();

    expect(errors.length).toBe(0);
  });
});
