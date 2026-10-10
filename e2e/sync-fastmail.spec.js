// Fastmail (#184): its files over WebDAV, at
// https://myfiles.fastmail.com/quire/quire-sync.json, with the Fastmail
// address and an app password, in the app only. Fastmail's WebDAV sends
// no CORS headers, so a browser page can't reach it: a browser lists no
// Fastmail and sends it nothing. The app's requests are native, which no
// CORS check stands in the way of. The server is a mock routed at
// myfiles.fastmail.com (no real network): as Fastmail is today to a
// page (no CORS), or as the app's native requests meet it (played by a
// mock that lets the page's origin in).

import { test, expect, onAndroid } from './fixtures.js';
import { start, dialog, librarySearch, librarySettings, settingsButton, settingsScreen, libraryShown } from './helpers.js';

const SERVER = 'https://myfiles.fastmail.com';
const FILE = '/quire/quire-sync.json';
const ADDRESS = 'reader@fastmail.com';
const APP_PASSWORD = 'fm-app-9k2x7q4w';

/** The mock Fastmail: its files, with a folder quire made by MKCOL; with
    cors, it lets the page's origin in (as the app's native requests
    get through), else it refuses a page, as Fastmail does today. What
    was asked of it */
function fastmail({ cors = true } = {}) {
  const server = { requests: [], folder: false, body: null, version: 0, puts: 0 };
  const allowed = origin => cors ? {
    'Access-Control-Allow-Origin': origin || '*',
    'Access-Control-Allow-Methods': 'GET, PUT, MKCOL, PROPFIND, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type, If-Match',
    'Access-Control-Expose-Headers': 'ETag',
  } : {};
  server.handle = async route => {
    const request = route.request();
    const headers = allowed(request.headers().origin);
    const path = new URL(request.url()).pathname;
    server.requests.push(`${request.method()} ${path}`);
    // a page's request refused by the browser, for want of CORS headers
    // (a routed answer is not checked for them)
    if (!cors) return route.abort('failed');
    if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers, body: '' });
    const basic = 'Basic ' + Buffer.from(`${ADDRESS}:${APP_PASSWORD}`).toString('base64');
    if (request.headers().authorization !== basic) return route.fulfill({ status: 401, headers, body: '' });
    if (request.method() === 'MKCOL' && path === '/quire/') {
      if (server.folder) return route.fulfill({ status: 405, headers, body: '' });
      server.folder = true;
      return route.fulfill({ status: 201, headers, body: '' });
    }
    if (path === FILE && request.method() === 'GET') {
      if (server.body === null) return route.fulfill({ status: 404, headers, body: '' });
      return route.fulfill({ status: 200, headers: { ...headers, ETag: `"v${server.version}"` }, body: server.body });
    }
    if (path === FILE && request.method() === 'PUT') {
      server.puts++;
      // WebDAV: no parent collection, no file
      if (!server.folder) return route.fulfill({ status: 409, headers, body: '' });
      const match = request.headers()['if-match'];
      if (match !== undefined && match !== `"v${server.version}"`) return route.fulfill({ status: 412, headers, body: '' });
      server.body = request.postData();
      server.version++;
      return route.fulfill({ status: 201, headers, body: '' });
    }
    return route.fulfill({ status: 404, headers, body: '' });
  };
  return server;
}

const panel = page => dialog(page, 'Sync');
const status = page => panel(page).getByRole('status');
const fastmailButton = page => panel(page).getByRole('button', { name: 'Sign in to Fastmail' });
const syncRow = page => settingsScreen(page).getByRole('group', { name: 'Sync' });

/** The Android app (its platform played): Fastmail routed in its own
    context. Its page, and the page's errors */
async function app(browser, server) {
  const context = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  await context.addInitScript(() => { window.Capacitor = { isNativePlatform: () => true, Plugins: {} }; });
  await context.route(`${SERVER}/**`, server.handle);
  const page = await context.newPage();
  const errors = await start(page);
  return { context, page, errors };
}

async function openSync(page) {
  await librarySettings(page);
  await settingsButton(page, 'Sync').click();
  await expect(panel(page)).toBeVisible();
}

/** The browser's own logs of the answers a test expects: a file not
    there yet (404), credentials refused (401) */
const unexpected = errors => errors.filter(e => !/status of (401|404)/.test(e));

test('in a browser, Fastmail is not listed, and nothing is sent to it', async ({ page }, testInfo) => {
  test.skip(onAndroid(testInfo), "a browser, where Fastmail's server refuses the page (no CORS): the Android app lists it (the app's tests below)");
  const errors = await start(page);
  const sent = [];
  page.on('request', request => { if (request.url().startsWith(SERVER)) sent.push(request.url()); });
  const server = fastmail({ cors: false });
  await page.context().route(`${SERVER}/**`, server.handle);
  await openSync(page);
  await expect(panel(page).getByRole('button', { name: 'WebDAV', exact: true })).toBeVisible();
  await expect(fastmailButton(page)).toBeHidden();
  await expect(panel(page).getByLabel('Fastmail address')).toBeHidden();
  await expect(panel(page).getByRole('link', { name: 'Make an app password' })).toBeHidden();
  // not named anywhere on the screen
  await expect(panel(page)).not.toContainText('Fastmail', { useInnerText: true });
  // opened again, from Settings: still no request
  await panel(page).getByRole('button', { name: 'Done' }).click();
  await settingsButton(page, 'Sync').click();
  await expect(panel(page)).toBeVisible();
  await page.waitForTimeout(500);
  expect(sent).toEqual([]);
  expect(server.requests).toEqual([]);
  expect(errors).toEqual([]);
});

test("in the app, the first sync makes Fastmail's folder, then syncs there; the link makes an app password", async ({ browser }) => {
  const server = fastmail();
  const { context, page, errors } = await app(browser, server);
  await openSync(page);
  await panel(page).getByRole('button', { name: 'Fastmail', exact: true }).click();
  await expect(fastmailButton(page)).toBeVisible();
  await expect(panel(page)).toContainText('Syncs through Fastmail');
  // the app password is made in Fastmail's settings, in a tab of its own
  const link = panel(page).getByRole('link', { name: 'Make an app password' });
  await expect(link).toHaveAttribute('href', 'https://app.fastmail.com/settings/security');
  await expect(link).toHaveAttribute('target', '_blank');
  await expect(panel(page)).toContainText('Files (WebDAV)');
  await panel(page).getByLabel('Fastmail address').fill(ADDRESS);
  await panel(page).getByLabel('Fastmail app password').fill(APP_PASSWORD);
  await fastmailButton(page).click();
  await expect(status(page)).toHaveText(/^Last synced on /);
  // no file yet: the folder made, then the file written into it
  const kept = server.requests.filter(r => !r.startsWith('OPTIONS'));
  expect(kept).toEqual([`GET ${FILE}`, 'MKCOL /quire/', `PUT ${FILE}`]);
  expect(server.puts).toBe(1);
  expect(JSON.parse(server.body).devices.length).toBe(1);
  await expect(panel(page).getByRole('button', { name: 'Turn off' })).toBeVisible();
  // the Settings screen's row names Fastmail
  await panel(page).getByRole('button', { name: 'Done' }).click();
  await expect(syncRow(page)).toContainText('Fastmail · synced');
  // kept across a reload: the next sync reads the file, and makes no folder
  await page.reload();
  await expect(libraryShown(page)).toBeVisible();
  await expect.poll(() => server.requests.filter(r => r === `GET ${FILE}`).length).toBe(2);
  await openSync(page);
  await expect(panel(page).getByLabel('Fastmail address')).toHaveValue(ADDRESS);
  await panel(page).getByRole('button', { name: 'Sync now' }).click();
  await expect(status(page)).toHaveText(/^Last synced on /);
  expect(server.requests.filter(r => r.startsWith('MKCOL')).length).toBe(1);
  // turned off: the address and app password forgotten
  await panel(page).getByRole('button', { name: 'Turn off' }).click();
  await expect(status(page)).toHaveText('Sync is off.');
  await expect(panel(page).getByLabel('Fastmail address')).toHaveValue('');
  expect(unexpected(errors)).toEqual([]);
  await context.close();
});

test('in the app, an address or app password Fastmail refuses is said so, and empty fields are asked for', async ({ browser }) => {
  const server = fastmail();
  const { context, page } = await app(browser, server);
  await openSync(page);
  await panel(page).getByRole('button', { name: 'Fastmail', exact: true }).click();
  await expect(fastmailButton(page)).toBeVisible();
  await fastmailButton(page).click();
  await expect(status(page)).toHaveText('Enter your Fastmail address and an app password.');
  await panel(page).getByLabel('Fastmail address').fill(ADDRESS);
  await panel(page).getByLabel('Fastmail app password').fill('my-login-password');
  await fastmailButton(page).click();
  await expect(status(page)).toHaveText(/^The Fastmail address or app password is wrong\. \(Sync tried on /);
  expect(server.puts).toBe(0);
  await panel(page).getByRole('button', { name: 'Done' }).click();
  await expect(syncRow(page)).toContainText('Wrong Fastmail address or app password');
  await context.close();
});

test('in the app, Fastmail is listed with no question to it first', async ({ browser }) => {
  const server = fastmail({ cors: false });
  const { context, page } = await app(browser, server);
  await openSync(page);
  await panel(page).getByRole('button', { name: 'Fastmail', exact: true }).click();
  await expect(fastmailButton(page)).toBeVisible();
  await expect(panel(page).getByLabel('Fastmail address')).toBeVisible();
  await expect(panel(page)).toContainText('Syncs through Fastmail');
  expect(server.requests).toEqual([]);
  await context.close();
});
