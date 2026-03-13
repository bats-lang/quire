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

    // Intercept bridge.js to add instrumentation
    await page.route('**/bridge.js', async (route) => {
      const response = await route.fetch();
      let body = await response.text();
      // Instrument batsJsFileOpen
      body = body.replace(
        'function batsJsFileOpen(idPtr, idLen, resolverId) {',
        'function batsJsFileOpen(idPtr, idLen, resolverId) { console.log("TRACE: batsJsFileOpen called, resolverId=" + resolverId);'
      );
      // Instrument batsJsFireEvent
      body = body.replace(
        'function batsJsFireEvent(listenerId, event, eventType) {',
        'function batsJsFireEvent(listenerId, event, eventType) { console.log("TRACE: batsJsFireEvent id=" + listenerId + " type=" + eventType);'
      );
      // Instrument bats_on_file_open callback
      body = body.replace(
        'instance.exports.bats_on_file_open(resolverId, handle, data.length)',
        '(console.log("TRACE: bats_on_file_open handle=" + handle + " len=" + data.length), instance.exports.bats_on_file_open(resolverId, handle, data.length))'
      );
      // Instrument batsDomFlush
      body = body.replace(
        'function batsDomFlush(bufPtr, len) {',
        'function batsDomFlush(bufPtr, len) { console.log("TRACE: batsDomFlush len=" + len);'
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

    // Instrument bridge to trace event flow
    await page.evaluate(() => {
      const fi = document.getElementById('qfin');
      if (fi) {
        fi.addEventListener('change', () => {
          console.log('TRACE: change event fired on qfin, files=' + fi.files.length);
        });
      }
      // Check WASM exports
      if (window._batsInstance) {
        const exports = Object.keys(window._batsInstance.exports).filter(k =>
          k.includes('event') || k.includes('file') || k.includes('listener'));
        console.log('TRACE: WASM event exports: ' + exports.join(', '));
      }
    });

    const epubPath = join(SCREENSHOT_DIR, 'smoke-test.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);

    // Wait a bit for the async import pipeline
    await page.waitForTimeout(3000);

    // Debug: print console logs
    console.log('Browser logs (' + logs.length + '):', logs.join('\n'));
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
        rvHidden: rv?.hidden,
        llClass: ll?.className,
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
