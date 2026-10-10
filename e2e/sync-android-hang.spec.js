// A call to Google's authorization that never answers (#340): the plugin's
// promise ends the call only when it settles, so a plugin that never
// settles it must not leave Use Android or Sync now with nothing shown
// and nothing that ends. The consent screen is the reader's to take as
// long as they like: while it is awaited the status card says so, and
// Stop waiting ends it. A call that shows nothing is ended by a timer
// (30 s) and said. Each call the plugin's stand-in leaves pending
// (`hold`, in e2e/sync-stores.js) is one the test settles late, which the
// app drops.

import { test, expect, clientsServed } from './fixtures.js';
import { epubFile, importFiles, chapters, dialog, librarySearch, librarySettings, settingsButton, settingsScreen, libraryShown } from './helpers.js';
import { drive, CLIENT, SCOPE, capacitorPlayed } from './sync-stores.js';

async function device(browser, server) {
  const context = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  const { google } = await capacitorPlayed(context, { mode: 'consent', token: server.token });
  await context.route('https://www.googleapis.com/**', server.handle);
  await context.route('https://oauth2.googleapis.com/revoke', server.revoke);
  await clientsServed(context, { googleWebClient: CLIENT });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  // the timers (30 s) are run by the test
  await page.clock.install();
  await page.goto('/');
  await expect(libraryShown(page)).toBeVisible();
  return { context, page, google, errors };
}

const panel = page => dialog(page, 'Sync');
const status = page => panel(page).getByRole('status');
const banner = page => page.getByRole('alert');
const stop = page => panel(page).getByRole('button', { name: 'Stop waiting' });
const syncNow = page => panel(page).getByRole('button', { name: 'Sync now' });
const row = page => settingsScreen(page).getByRole('group', { name: 'Sync' }).getByRole('status');
async function chooseAndroid(page) {
  await panel(page).getByRole('button', { name: 'Google Drive', exact: true }).click();
  await panel(page).getByRole('button', { name: 'Sign in to Google Drive' }).click();
}

async function openSync(page) {
  await librarySettings(page);
  await settingsButton(page, 'Sync').click();
  await expect(panel(page)).toBeVisible();
}

/** Whether a token is kept on the device ("sync-google-token"), once
    every write the app has started has reached IndexedDB */
async function tokenKept(page) {
  return page.evaluate(async () => {
    if (!(await indexedDB.databases()).some(d => d.name === 'bats')) return false;
    return new Promise((resolve, reject) => {
      const opened = indexedDB.open('bats');
      opened.onerror = () => reject(opened.error);
      opened.onsuccess = () => {
        const db = opened.result;
        if (!db.objectStoreNames.contains('kv')) { db.close(); resolve(false); return; }
        // a read-write transaction completes after every earlier one
        const flush = db.transaction('kv', 'readwrite');
        flush.oncomplete = () => {
          const read = db.transaction('kv').objectStore('kv').get('sync-google-token');
          read.onsuccess = () => { db.close(); resolve(read.result !== undefined); };
          read.onerror = () => { db.close(); reject(read.error); };
        };
        flush.onerror = () => { db.close(); reject(flush.error); };
      };
    });
  });
}

const book = { title: 'Hanging', author: 'Sync Tests', chapters: 2, rawChapters: chapters(2) };
const WAITING = "Waiting for Google's consent screen. Finish it there, or stop waiting.";
const NO_ANSWER = "Google didn't answer. Check the connection, then try again.";
const GRANTED = { authorization: { accessToken: 'token-1', grantedScopes: [SCOPE], account: 'reader@example.com' } };

/** Use Android, joined, with the app opened again and its book imported */
async function joined(browser, server) {
  const a = await device(browser, server);
  await importFiles(a.page, [epubFile(book)], 1);
  await openSync(a.page);
  await chooseAndroid(a.page);
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  return a;
}

test('a consent screen that never answers is said, and Stop waiting ends it; an answer after it is dropped', async ({ browser }) => {
  const server = drive();
  const a = await device(browser, server);
  await importFiles(a.page, [epubFile(book)], 1);
  await openSync(a.page);

  a.google.outcomes.authorizeScopes = [{ hold: true }];
  await chooseAndroid(a.page);
  // said where the reader is, with the way out; no timer ends it
  await expect(status(a.page)).toHaveText(WAITING);
  await expect(stop(a.page)).toBeVisible();
  await expect(syncNow(a.page)).toBeHidden();
  await a.page.clock.fastForward('10:00');
  await expect(status(a.page)).toHaveText(WAITING);
  await expect(stop(a.page)).toBeVisible();
  await expect(banner(a.page)).toBeHidden();

  // the screen closed and opened again meanwhile: still awaited, still
  // with its way out
  await panel(a.page).getByRole('button', { name: 'Done' }).click();
  await settingsButton(a.page, 'Done').click();
  await openSync(a.page);
  await expect(status(a.page)).toHaveText(WAITING);
  await expect(stop(a.page)).toBeVisible();
  await expect(syncNow(a.page)).toBeHidden();

  // another ask while it is awaited is the screen already open, said
  await chooseAndroid(a.page);
  await expect(banner(a.page)).toHaveText(/^Google's consent screen is already open: finish it, then try again\./);
  await banner(a.page).getByRole('button', { name: 'Dismiss' }).click();
  expect(a.google.asked('authorizeScopes')).toHaveLength(1);
  await expect(stop(a.page)).toBeVisible();

  // Stop waiting: a cancel, said quietly as the reader's own
  await stop(a.page).click();
  await expect(status(a.page)).toHaveText('Google sign-in was canceled.');
  await expect(stop(a.page)).toBeHidden();
  await expect(banner(a.page)).toBeHidden();

  // the plugin answers after all: dropped, nothing chosen or synced
  expect(a.google.held).toHaveLength(1);
  a.google.held.shift()(GRANTED);
  await a.page.clock.fastForward('00:05');
  await expect(status(a.page)).toHaveText('Google sign-in was canceled.');
  await expect(banner(a.page)).toBeHidden();
  expect(server.requests).toEqual([]);
  // nothing kept from it: no token, so what the reader was told stays true
  expect(await tokenKept(a.page)).toBe(false);
  await a.page.keyboard.press('Escape');
  await expect(row(a.page)).toHaveText('Off');
  await settingsButton(a.page, 'Sync').click();

  // and a new ask goes through
  await chooseAndroid(a.page);
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  await expect(stop(a.page)).toBeHidden();
  await expect(syncNow(a.page)).toBeVisible();
  expect(a.errors).toEqual([]);
  await a.context.close();
});

test('a consent screen answered while it is awaited ends the wait', async ({ browser }) => {
  const server = drive();
  const a = await device(browser, server);
  await importFiles(a.page, [epubFile(book)], 1);
  await openSync(a.page);
  a.google.outcomes.authorizeScopes = [{ hold: true }];
  await chooseAndroid(a.page);
  await expect(status(a.page)).toHaveText(WAITING);
  a.google.held.shift()(GRANTED);
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  await expect(stop(a.page)).toBeHidden();
  await expect(syncNow(a.page)).toBeVisible();
  // answered in time, its token is kept
  expect(await tokenKept(a.page)).toBe(true);
  expect(a.errors).toEqual([]);
  await a.context.close();
});

test('a call that shows nothing and never answers is ended after 30 s and said', async ({ browser }) => {
  const server = drive();
  const a = await joined(browser, server);
  await panel(a.page).getByRole('button', { name: 'Done' }).click();
  await settingsButton(a.page, 'Done').click();

  // the token's hour is up and Google's silent answer never comes: Drive
  // refuses the token, which is cleared, and another is asked for
  server.token = a.google.token = 'token-2';
  a.google.outcomes.authorizationForScopes = [{ hold: true }];
  await a.page.reload();
  await expect(librarySearch(a.page)).toBeVisible();
  await expect.poll(() => a.google.asked('authorizationForScopes')).toHaveLength(1);
  await a.page.clock.fastForward('00:29');
  await openSync(a.page);
  await expect(status(a.page)).not.toContainText(NO_ANSWER);
  await a.page.clock.fastForward('00:02');
  await expect(status(a.page)).toContainText(NO_ANSWER);
  // not a sync the reader started: the status line says it, no banner
  await expect(banner(a.page)).toBeHidden();

  // its answer, late, is dropped, and no token is kept from it
  expect(await tokenKept(a.page)).toBe(false);
  a.google.held.shift()({ authorization: { ...GRANTED.authorization, accessToken: 'token-2' } });
  await a.page.clock.fastForward('00:05');
  await expect(status(a.page)).toContainText(NO_ANSWER);
  expect(await tokenKept(a.page)).toBe(false);

  // Sync now asks again, and a sync the reader started says it in the banner
  a.google.outcomes.authorizeScopes = [{ hold: true }];
  await syncNow(a.page).click();
  await expect(status(a.page)).toHaveText(WAITING);
  await stop(a.page).click();
  await expect(status(a.page)).toContainText('Google sign-in was canceled.');
  expect(a.errors).toEqual([]);
  await a.context.close();
});

test('a token clear that never answers is ended after 30 s, and the answer after it asks nothing more', async ({ browser }) => {
  const server = drive();
  const a = await joined(browser, server);
  await panel(a.page).getByRole('button', { name: 'Done' }).click();
  await settingsButton(a.page, 'Done').click();

  server.token = a.google.token = 'token-2';
  a.google.outcomes.clearAuthorizationToken = [{ hold: true }];
  await a.page.reload();
  await expect(librarySearch(a.page)).toBeVisible();
  await expect.poll(() => a.google.asked('clearAuthorizationToken')).toHaveLength(1);
  await a.page.clock.fastForward('00:31');
  await openSync(a.page);
  await expect(status(a.page)).toContainText(NO_ANSWER);
  expect(a.google.asked('authorizationForScopes')).toEqual([]);

  // the clear's answer, late: it asks Google nothing more
  a.google.held.shift()(undefined);
  await a.page.clock.fastForward('00:05');
  await expect(status(a.page)).toContainText(NO_ANSWER);
  expect(a.google.asked('authorizationForScopes')).toEqual([]);
  expect(a.errors).toEqual([]);
  await a.context.close();
});

test('taking the grant back that Google never answers is said after 30 s', async ({ browser }) => {
  const server = drive();
  const a = await joined(browser, server);
  a.google.outcomes.revokeAccess = [{ hold: true }];
  // Turn off, made final once its offer is dismissed
  await panel(a.page).getByRole('button', { name: 'Turn off' }).click();
  await expect(status(a.page)).toHaveText('Sync is off.');
  // the offer stays until it is dismissed (quire#364); made final, it takes the grant back
  await a.page.getByRole('status').filter({ hasText: 'Sync turned off' }).getByRole('button', { name: 'Dismiss' }).click();
  await a.page.clock.fastForward('00:15');
  await expect.poll(() => a.google.asked('revokeAccess')).toHaveLength(1);
  await expect(banner(a.page)).toBeHidden();
  await a.page.clock.fastForward('00:31');
  await expect(banner(a.page)).toHaveText(/^Google didn't answer when Quire took back its access to Drive: remove it in your Google account, under Security, Your connections to third-party apps\./);
  expect(a.errors).toEqual([]);
  await a.context.close();
});
