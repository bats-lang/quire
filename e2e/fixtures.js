/**
 * The e2e suite's `test`: Playwright's, with the stall watch of
 * stall-capture.js on every test (#244). Every spec imports `test` from
 * here (global-setup.js checks it).
 */

import { test as base, expect } from '@playwright/test';
import { stallWatch } from './stall-capture.js';

export const test = base.extend({
  stallWatch: [async ({ browser }, use, testInfo) => {
    const watch = stallWatch(browser, testInfo);
    await use(watch);
    await watch.stop();
  }, { auto: true }],
  // the test's own context is watched before its page is made
  context: async ({ context, stallWatch }, use) => {
    stallWatch.watchContext(context);
    await use(context);
  },
});

export { expect };
