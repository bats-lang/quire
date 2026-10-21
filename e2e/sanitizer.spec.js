/**
 * The app's browser under AddressSanitizer (#575): the class "memory corruption in Chromium" is seen by running a
 * sanitizer build, which names the bad access where a release build hangs or dies later. check.yml's sanitizer step
 * (the e2e group reading-tools) downloads Chromium's public ASan build, points QUIRE_BROWSER_EXECUTABLE at it and
 * QUIRE_SANITIZER_LOGS at a directory, and runs this spec; any report in that directory fails the step, with the report.
 * The induced half (a sanitizer's report reaching the artifact) is in evidence.spec.js and always runs. Keyword: sanitizer.
 */

import { mkdirSync, readdirSync } from 'node:fs';
import { chromium } from '@playwright/test';
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

// The report path itself (#575): a renderer the sanitizer ends must leave its report in log_path, or "no report" proves nothing.
// chrome://memory-exhaust makes a renderer allocate until the sanitizer ends it. Each launch has a directory of its own, so these
// deliberate reports are not the first test's. The sandboxed launch is the question whether a sanitized renderer under Chromium's
// sandbox still reaches log_path (the sandbox limits what the process may open): its outcome is recorded, whichever it is.
for (const sandboxed of [false, true]) {
  test(`a renderer ended by the sanitizer leaves its report in log_path (${sandboxed ? 'sandboxed' : 'no sandbox'})`, async ({}, testInfo) => {
    test.skip(!required, 'run by check.yml\'s sanitizer step, with the ASan Chromium (QUIRE_REQUIRE_SANITIZER=1)');
    test.setTimeout(240000);
    const directory = testInfo.outputPath('asan-reports');
    mkdirSync(directory, { recursive: true });
    let browser;
    try {
      browser = await chromium.launch({
        executablePath: process.env.QUIRE_BROWSER_EXECUTABLE, chromiumSandbox: sandboxed, timeout: 60000,
        env: { ...process.env, ASAN_OPTIONS: `log_path=${directory}/asan:detect_leaks=0:symbolize=1` },
      });
    } catch (error) {
      const why = String(error && error.message || error).split('\n')[0].slice(0, 300);
      testInfo.annotations.push({ type: 'sandbox', description: `the sanitizer build did not start ${sandboxed ? 'sandboxed' : 'without the sandbox'}: ${why}` });
      console.error(`[sanitizer] ${sandboxed ? 'sandboxed' : 'no sandbox'}: the browser did not start: ${why}`);
      expect(sandboxed, 'the browser must start without the sandbox').toBe(true);
      return;
    }
    try {
      const page = await (await browser.newContext()).newPage();
      page.goto('chrome://memory-exhaust').catch(() => {});
      await expect.poll(() => readdirSync(directory).filter((name) => name.startsWith('asan')).length, { timeout: 120000, message: `a report in ${directory}` }).toBeGreaterThan(0);
      const summaries = sanitizerReports(directory).map((each) => each.summary);
      expect(summaries.length).toBeGreaterThan(0);
      testInfo.annotations.push({ type: 'sandbox', description: `${sandboxed ? 'sandboxed' : 'no sandbox'}: the report reached log_path: ${summaries[0]}` });
      console.error(`[sanitizer] ${sandboxed ? 'sandboxed' : 'no sandbox'}: the report reached log_path: ${summaries[0]}`);
    } finally { await browser.close().catch(() => {}); }
  });
}
