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

/** Fastmail's files, as a browser page meets them: refused, for want of
    CORS headers. The Sync screen asks each time it opens whether a page
    may reach them, and the suite never reaches Fastmail. A routed answer
    is not checked for CORS, so the refusal is played as the failed
    request a page sees. A spec that plays a Fastmail that lets pages in
    (sync-fastmail.spec.js) routes its own over this */
export async function fastmailStubbed(context) {
  await context.route('https://myfiles.fastmail.com/**', route => route.abort('failed'));
}

/** Whether a console message is the browser's log of that refusal */
export const fastmailRefused = message => message.location().url.startsWith('https://myfiles.fastmail.com/');

/** The build's OAuth clients, as sync-clients.json serves them, in place
    of the ones committed in scripts/sync-clients.env: a spec that plays
    a provider serves its own test client, and one that tests a build
    with no client serves none ({}) */
export async function clientsServed(context, clients) {
  await context.route('**/sync-clients.json', route => route.fulfill({
    status: 200, headers: { 'content-type': 'application/json' }, body: JSON.stringify(clients),
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
    await fastmailStubbed(context);
    await use(context);
  },
});

export { expect };
