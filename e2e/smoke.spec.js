/**
 * Smoke test: quick sanity check that WASM loads and import works.
 */

import { test, expect } from './fixtures.js';
import { createEpub } from './create-epub.js';
import { importInput, cards, bookPage, librarySearch, reload,
} from './helpers.js';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const SCREENSHOT_DIR = join(process.cwd(), 'e2e', 'screenshots');
mkdirSync(SCREENSHOT_DIR, { recursive: true });

test.describe('Smoke', () => {
  test('WASM loads and entry screen renders', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await expect(librarySearch(page)).toBeVisible({ timeout: 15000 });

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
    await page.goto('/');
    await expect(importInput(page)).toBeVisible();
    const epubPath = join(SCREENSHOT_DIR, `smoke-${Date.now()}.epub`);
    writeFileSync(epubPath, createEpub({ title: 'Smoke Test', author: 'Bot', chapters: 2, storeChapters: true }));
    await importInput(page).setInputFiles(epubPath);
    await cards(page).first().click();
    await expect(bookPage(page)).toBeVisible();
    await expect(bookPage(page)).toContainText('Chapter 1');
    expect(errors).toEqual([]);
  });

  test('a new build served while the app is open is offered, and loaded only on Reload', async ({ page }) => {
    let deployed = false;
    await page.route('**/app.wasm', route => {
      if (route.request().method() === 'HEAD') {
        const etag = deployed ? '"a-new-build"' : '"the-loaded-build"';
        return route.fulfill({ status: 200, headers: { etag }, body: '' });
      }
      return route.continue();
    });
    // the build is checked every 30 seconds: the clock is the test's
    await page.clock.install();
    await page.goto('/');
    await expect(librarySearch(page)).toBeVisible();
    // the page marks itself; a reload is a new page without the mark
    await page.evaluate(() => { window.__before = true; });
    deployed = true;
    await page.clock.runFor(31000);
    const offer = page.getByRole('status').filter({ hasText: 'A new version of Quire is ready.' });
    await expect(offer).toBeVisible();
    // offered, never forced: the page is the same one
    await page.clock.runFor(5000);
    expect(await page.evaluate(() => window.__before)).toBe(true);
    // Dismiss puts it away, and nothing reloads
    await offer.getByRole('button', { name: 'Dismiss' }).click();
    await expect(offer).toBeHidden();
    expect(await page.evaluate(() => window.__before)).toBe(true);
  });

  test('Reload on the offer of a new build loads it', async ({ page }) => {
    let deployed = false;
    await page.route('**/app.wasm', route => {
      if (route.request().method() === 'HEAD') {
        const etag = deployed ? '"a-new-build"' : '"the-loaded-build"';
        return route.fulfill({ status: 200, headers: { etag }, body: '' });
      }
      return route.continue();
    });
    await page.clock.install();
    await page.goto('/');
    await expect(librarySearch(page)).toBeVisible();
    await page.evaluate(() => { window.__before = true; });
    deployed = true;
    await page.clock.runFor(31000);
    const offer = page.getByRole('status').filter({ hasText: 'A new version of Quire is ready.' });
    const reloaded = page.waitForEvent('load');
    await offer.getByRole('button', { name: 'Reload' }).click();
    await reloaded;
    await expect(librarySearch(page)).toBeVisible();
    expect(await page.evaluate(() => window.__before)).toBeUndefined();
  });

  test('the app loads offline once it has been opened', async ({ page, context }) => {
    await page.goto('/');
    await expect(importInput(page)).toBeVisible();
    await page.evaluate(() => navigator.serviceWorker.ready);
    // a load the worker serves, so it keeps what it fetches
    await reload(page);
    await expect(importInput(page)).toBeVisible();
    await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller)).toBe(true);
    await context.setOffline(true);
    await reload(page);
    await expect(importInput(page)).toBeVisible();
    await context.setOffline(false);
  });
});
