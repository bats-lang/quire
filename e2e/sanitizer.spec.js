/**
 * The app's browser under AddressSanitizer (#575): the class "memory corruption in Chromium" is seen by running a
 * sanitizer build, which names the bad access where a release build hangs or dies later. check.yml's sanitizer step
 * (the e2e group reading-tools) downloads Chromium's public ASan build, points QUIRE_BROWSER_EXECUTABLE at it and
 * QUIRE_SANITIZER_LOGS at a directory, and runs this spec; any report in that directory fails the step, with the report.
 * The induced half (a sanitizer's report reaching the artifact) is in evidence.spec.js and always runs. Keyword: sanitizer.
 */

import { readdirSync } from 'node:fs';
import { test, expect } from './fixtures.js';
import { sanitizerReports } from './evidence.js';

// only the sanitizer step runs this spec on the sanitizer build; elsewhere the project's browser is the release one
const required = !!process.env.QUIRE_REQUIRE_SANITIZER;

test('the app opens and answers under AddressSanitizer, and the sanitizer reports nothing', async ({ page, browser }) => {
  test.skip(!required && !process.env.QUIRE_BROWSER_EXECUTABLE, 'run by check.yml\'s sanitizer step, with the ASan Chromium (QUIRE_REQUIRE_SANITIZER=1)');
  expect(process.env.QUIRE_SANITIZER_LOGS, 'the step names where the reports go').toBeTruthy();
  await page.goto('/');
  await expect(page.locator('#library-title')).toBeVisible({ timeout: 60000 });
  expect(await page.evaluate(() => 1 + 1)).toBe(2);
  // an ASan build says so in its launch line: a release browser would make this run prove nothing
  expect(process.env.QUIRE_BROWSER_EXECUTABLE, 'the browser is the sanitizer build').toMatch(/ASAN|asan/);
  expect(browser.version()).toBeTruthy();
  const found = sanitizerReports();
  expect(found.map((each) => each.summary), `reports in ${process.env.QUIRE_SANITIZER_LOGS}: ${readdirSync(process.env.QUIRE_SANITIZER_LOGS)}`).toEqual([]);
});
