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
    console.log('EPUB size:', buf.length);

    // Check EOCD signature at end
    const len = buf.length;
    let eocdOff = -1;
    for (let i = len - 22; i >= 0; i--) {
      const sig = buf[i] | (buf[i+1] << 8) | (buf[i+2] << 16) | (buf[i+3] << 24);
      if (sig === 0x06054B50) { eocdOff = i; break; }
    }
    console.log('EOCD offset:', eocdOff);
    expect(eocdOff).toBeGreaterThanOrEqual(0);

    // Parse EOCD
    const cdOffset = buf[eocdOff+16] | (buf[eocdOff+17] << 8) | (buf[eocdOff+18] << 16) | (buf[eocdOff+19] << 24);
    const cdCount = buf[eocdOff+10] | (buf[eocdOff+11] << 8);
    console.log('CD offset:', cdOffset, 'CD count:', cdCount);

    // Parse central directory entries
    let pos = cdOffset;
    for (let i = 0; i < cdCount; i++) {
      const sig = buf[pos] | (buf[pos+1] << 8) | (buf[pos+2] << 16) | (buf[pos+3] << 24);
      expect(sig).toBe(0x02014B50);
      const nameLen = buf[pos+28] | (buf[pos+29] << 8);
      const extraLen = buf[pos+30] | (buf[pos+31] << 8);
      const commentLen = buf[pos+32] | (buf[pos+33] << 8);
      const compression = buf[pos+10] | (buf[pos+11] << 8);
      const compSize = buf[pos+20] | (buf[pos+21] << 8) | (buf[pos+22] << 16) | (buf[pos+23] << 24);
      const name = new TextDecoder().decode(buf.slice(pos+46, pos+46+nameLen));
      console.log(`Entry ${i}: "${name}" compression=${compression} compSize=${compSize} nameLen=${nameLen}`);
      pos += 46 + nameLen + extraLen + commentLen;
    }
  });

  test('EPUB import opens reader view', async ({ page }) => {
    const errors = [];
    const logs = [];
    page.on('pageerror', err => errors.push(err.message));
    page.on('console', msg => logs.push(`[${msg.type()}] ${msg.text()}`));

    // Intercept bridge.js to trace key functions and catch WASM traps
    await page.route('**/bridge.js', async (route) => {
      const response = await route.fetch();
      let body = await response.text();

      // Wrap bats_on_file_open to catch WASM traps
      body = body.replace(
        'instance.exports.bats_on_file_open(resolverId, handle, data.length)',
        'try { console.log("TRACE: bats_on_file_open handle=" + handle + " len=" + data.length); instance.exports.bats_on_file_open(resolverId, handle, data.length); console.log("TRACE: bats_on_file_open returned OK"); } catch(e) { console.log("TRAP in bats_on_file_open: " + e.message); }'
      );
      body = body.replace(
        /instance\.exports\.bats_on_file_open\(resolverId, 0, 0\)/g,
        '(console.log("TRACE: bats_on_file_open(0,0) no-file case"), instance.exports.bats_on_file_open(resolverId, 0, 0))'
      );

      body = body.replace(
        'function batsJsFileOpen(idPtr, idLen, resolverId) {',
        'function batsJsFileOpen(idPtr, idLen, resolverId) { console.log("TRACE: batsJsFileOpen resolverId=" + resolverId);'
      );
      body = body.replace(
        'function batsJsFileRead(handle, fileOffset, len, outPtr) {',
        'function batsJsFileRead(handle, fileOffset, len, outPtr) { console.log("TRACE: batsJsFileRead handle=" + handle + " offset=" + fileOffset + " len=" + len);'
      );
      body = body.replace(
        'function batsJsDecompress(dataPtr, dataLen, method, resolverId) {',
        'function batsJsDecompress(dataPtr, dataLen, method, resolverId) { console.log("TRACE: batsJsDecompress len=" + dataLen + " method=" + method);'
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
