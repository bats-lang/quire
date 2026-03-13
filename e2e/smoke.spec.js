/**
 * Smoke test: quick sanity check that WASM loads and import works.
 */

import { test, expect } from '@playwright/test';
import { createEpub } from './create-epub.js';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const SCREENSHOT_DIR = join(process.cwd(), 'e2e', 'screenshots');
mkdirSync(SCREENSHOT_DIR, { recursive: true });

test.describe('Smoke', () => {
  test('WASM loads and entry screen renders', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    expect(errors.length).toBe(0);
  });

  test('EPUB import opens reader view', async ({ page }) => {
    const errors = [];
    const logs = [];
    page.on('pageerror', err => errors.push(err.message));
    page.on('console', msg => logs.push(`[${msg.type()}] ${msg.text()}`));

    const epubBuffer = createEpub({
      title: 'Smoke Test',
      author: 'Bot',
      chapters: 1,
      paragraphsPerChapter: 2,
      storeChapters: true,
    });

    await page.goto('/');
    await page.waitForSelector('#qllc', { timeout: 15000 });

    const fileInput = page.locator('input[type="file"]');
    await expect(fileInput).toBeAttached();

    const epubPath = join(SCREENSHOT_DIR, 'smoke-test.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);

    // Wait a bit for the async import pipeline
    await page.waitForTimeout(3000);

    // Debug: print console logs
    if (logs.length > 0) console.log('Browser logs:', logs.join('\n'));
    if (errors.length > 0) console.log('Page errors:', errors.join('\n'));

    // Inspect DOM state
    const domInfo = await page.evaluate(() => {
      const rv = document.getElementById('qrvw');
      const ll = document.getElementById('qllc');
      const cnt = document.getElementById('qcnt');
      const fi = document.getElementById('qfin');
      const allEls = document.querySelectorAll('[id]');
      const ids = Array.from(allEls).map(e => `${e.tagName}#${e.id} class="${e.className}" hidden=${e.hidden}`);
      return {
        rvClass: rv?.className,
        rvClassBytes: rv ? Array.from(new TextEncoder().encode(rv.className)) : null,
        rvHidden: rv?.hidden,
        llClass: ll?.className,
        llClassBytes: ll ? Array.from(new TextEncoder().encode(ll.className)) : null,
        cntText: cnt?.textContent,
        fiExists: !!fi,
        fiType: fi?.type,
        fiFiles: fi?.files?.length,
        allIds: ids,
      };
    });
    console.log('DOM state:', JSON.stringify(domInfo, null, 2));

    // After import, reader view should appear
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    // Library should be hidden
    await expect(page.locator('#qllc')).toBeHidden();

    expect(errors.length).toBe(0);
  });
});
