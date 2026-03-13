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

    // Intercept bridge.js to trace key functions
    await page.route('**/bridge.js', async (route) => {
      const response = await route.fetch();
      let body = await response.text();
      body = body.replace(
        'function batsJsFileOpen(idPtr, idLen, resolverId) {',
        'function batsJsFileOpen(idPtr, idLen, resolverId) { console.log("TRACE: batsJsFileOpen resolverId=" + resolverId);'
      );
      // Trace file_open callback
      body = body.replace(
        'instance.exports.bats_on_file_open(resolverId, handle, data.length)',
        '(console.log("TRACE: bats_on_file_open handle=" + handle + " len=" + data.length), instance.exports.bats_on_file_open(resolverId, handle, data.length))'
      );
      // Trace file read
      body = body.replace(
        'function batsJsFileRead(handle, offset, len, outPtr) {',
        'function batsJsFileRead(handle, offset, len, outPtr) { console.log("TRACE: batsJsFileRead handle=" + handle + " offset=" + offset + " len=" + len);'
      );
      body = body.replace(
        'function batsJsDecompress(dataPtr, dataLen, method, resolverId) {',
        'function batsJsDecompress(dataPtr, dataLen, method, resolverId) { console.log("TRACE: batsJsDecompress len=" + dataLen + " method=" + method);'
      );
      body = body.replace(
        'function batsDomFlush(bufPtr, len) {',
        'function batsDomFlush(bufPtr, len) { console.log("TRACE: batsDomFlush len=" + len);'
      );
      // Trace stash_int (file size is stored here)
      body = body.replace(
        'function batsJsStashInt(slot, value) {',
        'function batsJsStashInt(slot, value) { console.log("TRACE: batsJsStashInt slot=" + slot + " value=" + value);'
      );
      await route.fulfill({ response, body });
    });

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

    // Wait for async import pipeline
    await page.waitForTimeout(5000);

    // Dump debug info
    console.log('Browser logs (' + logs.length + '):');
    for (const l of logs) console.log('  ' + l);
    if (errors.length > 0) console.log('Page errors:', errors.join('\n'));

    const domInfo = await page.evaluate(() => {
      const rv = document.getElementById('qrvw');
      const ll = document.getElementById('qllc');
      const cnt = document.getElementById('qcnt');
      return {
        rvHidden: rv?.hidden,
        llHidden: ll?.hidden,
        cntText: cnt?.textContent?.substring(0, 100),
      };
    });
    console.log('DOM state:', JSON.stringify(domInfo));

    // After import, reader view should appear
    await expect(page.locator('#qrvw')).toBeVisible({ timeout: 15000 });
    // Library should be hidden
    await expect(page.locator('#qllc')).toBeHidden();

    expect(errors.length).toBe(0);
  });
});
