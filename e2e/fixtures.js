/**
 * The e2e suite's `test`: Playwright's, with the stall watch of
 * stall-capture.js on every test (#244). Every spec imports `test` from
 * here (global-setup.js checks it).
 */

import { test as base, expect } from '@playwright/test';
import { stallWatch } from './stall-capture.js';

/** Google's sign-in script, stubbed with one that defines nothing: the
    build has a Google client (scripts/sync-clients.env), so the Sync
    screen loads the script, and the suite never reaches Google. A spec
    that plays Google (sync-android.spec.js) routes its own over this */
export async function googleStubbed(context) {
  await context.route('https://accounts.google.com/**', route => route.fulfill({
    status: 200, headers: { 'content-type': 'text/javascript' }, body: '',
  }));
}

export const test = base.extend({
  stallWatch: [async ({ browser }, use, testInfo) => {
    const watch = stallWatch(browser, testInfo);
    await use(watch);
    await watch.stop();
  }, { auto: true }],
  // the test's own context is watched before its page is made
  context: async ({ context, stallWatch }, use) => {
    stallWatch.watchContext(context);
    await googleStubbed(context);
    await use(context);
  },
});

export { expect };
