// A browser whose trace ring is taken before the stall watch asks for it: a second Tracing.start on the browser is refused, so the
// ring the evidence needs cannot start, and the test fails by name before its body runs (the preflight of the browser's trace ring)
import { test as base } from '../fixtures.js';

const test = base.extend({
  browser: [async ({ playwright, launchOptions }, use) => {
    const browser = await playwright.chromium.launch(launchOptions);
    const taken = await browser.newBrowserCDPSession();
    await taken.send('Tracing.start', { traceConfig: { recordMode: 'recordContinuously', includedCategories: ['toplevel'] } });
    await use(browser);
    await browser.close();
  }, { scope: 'worker' }],
});

test('trace ring taken', async ({ page }) => {
  await page.setContent('<p>never reached</p>');
});
