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

  test('Generated EPUB is valid ZIP', async () => {
    const epubBuffer = createEpub({
      title: 'Smoke Test',
      author: 'Bot',
      chapters: 1,
      paragraphsPerChapter: 2,
      storeChapters: true,
    });

    const buf = new Uint8Array(epubBuffer);

    // Check EOCD signature at end
    const len = buf.length;
    let eocdOff = -1;
    for (let i = len - 22; i >= 0; i--) {
      const sig = buf[i] | (buf[i+1] << 8) | (buf[i+2] << 16) | (buf[i+3] << 24);
      if (sig === 0x06054B50) { eocdOff = i; break; }
    }
    expect(eocdOff).toBeGreaterThanOrEqual(0);

    // Parse EOCD
    const cdOffset = buf[eocdOff+16] | (buf[eocdOff+17] << 8) | (buf[eocdOff+18] << 16) | (buf[eocdOff+19] << 24);
    const cdCount = buf[eocdOff+10] | (buf[eocdOff+11] << 8);

    // Parse central directory entries
    let pos = cdOffset;
    for (let i = 0; i < cdCount; i++) {
      const sig = buf[pos] | (buf[pos+1] << 8) | (buf[pos+2] << 16) | (buf[pos+3] << 24);
      expect(sig).toBe(0x02014B50);
      const nameLen = buf[pos+28] | (buf[pos+29] << 8);
      const extraLen = buf[pos+30] | (buf[pos+31] << 8);
      const commentLen = buf[pos+32] | (buf[pos+33] << 8);
      pos += 46 + nameLen + extraLen + commentLen;
    }
  });

  test('EPUB import opens reader view', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    const epubBuffer = createEpub({
      title: 'Import Test',
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

    // After import, reader view should appear
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    // Library should be hidden
    await expect(page.locator('#qllc')).toBeHidden();

    expect(errors.length).toBe(0);
  });
});
