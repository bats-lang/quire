// Nextcloud: signing in with its Login Flow v2, then syncing through
// the user's files folder over WebDAV. The server is a mock routed at
// https://cloud.example.com (no real network), answering CORS as a
// server that lets the app's origin in would.

import { test, expect } from './fixtures.js';
import { start, dialog, librarySettings, settingsButton } from './helpers.js';

const SERVER = 'https://cloud.example.com';
const TOKEN = '6ad14f1e0c2b9ad4c1f3e1b2a7d8c9e0';
const LOGIN = 'alice@example.com';
const USER_ID = 'alice';
const APP_PASSWORD = 'nc-app-Pass-7731';

/** The mock Nextcloud: the flow's start and poll, the user endpoint and
    the files folder; what was asked of it */
function nextcloud({ pollsBeforeGrant = 1, startStatus = 200 } = {}) {
  const server = { starts: 0, polls: 0, pollBodies: [], pollTypes: [], userAsks: [], puts: 0, body: null, version: 0 };
  const cors = origin => ({
    'Access-Control-Allow-Origin': origin || '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type, If-Match, OCS-APIRequest',
    'Access-Control-Expose-Headers': 'ETag',
  });
  server.handle = async route => {
    const request = route.request();
    const headers = cors(request.headers().origin);
    const url = new URL(request.url());
    if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers, body: '' });
    const json = (status, value) => route.fulfill({ status, headers: { ...headers, 'Content-Type': 'application/json' }, body: JSON.stringify(value) });
    if (url.pathname === '/index.php/login/v2' && request.method() === 'POST') {
      if (startStatus !== 200) return route.fulfill({ status: startStatus, headers, body: 'Not found' });
      server.starts++;
      return json(200, { poll: { token: `${TOKEN}${server.starts}`, endpoint: `${SERVER}/login/v2/poll` }, login: `${SERVER}/login/v2/flow/zQ81kLmn` });
    }
    if (url.pathname === '/login/v2/poll' && request.method() === 'POST') {
      server.polls++;
      server.pollBodies.push(request.postData());
      server.pollTypes.push(request.headers()['content-type']);
      if (!/^token=[0-9a-f]+$/.test(request.postData() || '')) return route.fulfill({ status: 404, headers, body: '' });
      if (server.polls <= pollsBeforeGrant) return route.fulfill({ status: 404, headers, body: '[]' });
      return json(200, { server: SERVER, loginName: LOGIN, appPassword: APP_PASSWORD });
    }
    const basic = 'Basic ' + Buffer.from(`${LOGIN}:${APP_PASSWORD}`).toString('base64');
    if (url.pathname === '/ocs/v2.php/cloud/user') {
      server.userAsks.push({ ocs: request.headers()['ocs-apirequest'], authorization: request.headers().authorization, format: url.searchParams.get('format') });
      if (request.headers().authorization !== basic) return route.fulfill({ status: 401, headers, body: '' });
      return json(200, { ocs: { meta: { status: 'ok', statuscode: 200 }, data: { enabled: true, id: USER_ID, 'display-name': 'Alice' } } });
    }
    if (url.pathname === `/remote.php/dav/files/${USER_ID}/quire-sync.json`) {
      if (request.headers().authorization !== basic) return route.fulfill({ status: 401, headers, body: '' });
      if (request.method() === 'GET') {
        if (server.body === null) return route.fulfill({ status: 404, headers, body: '' });
        return route.fulfill({ status: 200, headers: { ...headers, ETag: `"v${server.version}"` }, body: server.body });
      }
      if (request.method() === 'PUT') {
        server.puts++;
        server.body = request.postData();
        server.version++;
        return route.fulfill({ status: 201, headers, body: '' });
      }
    }
    return route.fulfill({ status: 404, headers, body: '' });
  };
  return server;
}

const panel = page => dialog(page, 'Sync');
const status = page => panel(page).getByRole('status');

/** The Sync screen, and on it the Nextcloud row's own step (#331) */
async function openSync(page, server) {
  await page.context().route(`${SERVER}/**`, server.handle);
  await librarySettings(page);
  await settingsButton(page, 'Sync ›').click();
  await expect(panel(page)).toBeVisible();
  await panel(page).getByRole('button', { name: 'Nextcloud ›' }).click();
  await expect(panel(page).getByLabel('Nextcloud server')).toBeVisible();
}

/** The browser's own logs of the 404s the flow and a first sync expect */
const unexpected = errors => errors.filter(e => !/status of 404/.test(e));

test('signing in with Nextcloud polls its flow, finds the files folder and syncs there', async ({ page }) => {
  const errors = await start(page);
  const server = nextcloud({ pollsBeforeGrant: 1 });
  await openSync(page, server);
  await panel(page).getByLabel('Nextcloud server').fill(`${SERVER}/`);
  await panel(page).getByRole('button', { name: 'Sign in with Nextcloud' }).click();
  // the sign-in page is a link the reader opens, in a tab of its own
  const link = panel(page).getByRole('link', { name: "Open Nextcloud's sign-in page" });
  await expect(link).toBeVisible();
  await expect(link).toHaveAttribute('href', `${SERVER}/login/v2/flow/zQ81kLmn`);
  await expect(link).toHaveAttribute('target', '_blank');
  await expect(status(page)).toHaveText(/sign in and grant access/);
  // granted on the second poll: the user's id found, the folder kept,
  // a sync made with the app password
  await expect(status(page)).toHaveText(/^Last synced on /, { timeout: 30000 });
  expect(server.polls).toBe(2);
  expect(server.pollBodies.every(body => body === `token=${TOKEN}1`)).toBe(true);
  expect(server.pollTypes.every(type => /^application\/x-www-form-urlencoded/.test(type))).toBe(true);
  expect(server.userAsks).toEqual([{ ocs: 'true', authorization: 'Basic ' + Buffer.from(`${LOGIN}:${APP_PASSWORD}`).toString('base64'), format: 'json' }]);
  expect(server.puts).toBe(1);
  expect(JSON.parse(server.body).devices.length).toBe(1);
  await expect(link).toBeHidden();
  // what it signed in with is the WebDAV store's
  await expect(panel(page).getByLabel('Folder URL')).toHaveValue(`${SERVER}/remote.php/dav/files/${USER_ID}`);
  await expect(panel(page).getByLabel('User name')).toHaveValue(LOGIN);
  await expect(panel(page).getByRole('button', { name: 'Turn off' })).toBeVisible();
  expect(unexpected(errors)).toEqual([]);
});

test('a server address that is not https, or not a Nextcloud, is said so', async ({ page }) => {
  await start(page);
  const server = nextcloud({ startStatus: 404 });
  await openSync(page, server);
  await panel(page).getByLabel('Nextcloud server').fill('http://cloud.example.com');
  await panel(page).getByRole('button', { name: 'Sign in with Nextcloud' }).click();
  await expect(status(page)).toHaveText("Enter your Nextcloud's address, starting with https://.");
  await panel(page).getByLabel('Nextcloud server').fill(SERVER);
  await panel(page).getByRole('button', { name: 'Sign in with Nextcloud' }).click();
  await expect(status(page)).toHaveText("That address isn't a Nextcloud server, or it didn't answer as one.");
  await expect(panel(page).getByRole('link', { name: "Open Nextcloud's sign-in page" })).toBeHidden();
  expect(server.polls).toBe(0);
});

test('a sign-in started again stops the first one polling', async ({ page }) => {
  await start(page);
  const server = nextcloud({ pollsBeforeGrant: 1000 });
  await openSync(page, server);
  await panel(page).getByLabel('Nextcloud server').fill(SERVER);
  const signIn = panel(page).getByRole('button', { name: 'Sign in with Nextcloud' });
  const pollsWith = start => server.pollBodies.filter(body => body === `token=${TOKEN}${start}`).length;
  await signIn.click();
  await expect.poll(() => pollsWith(1), { timeout: 15000 }).toBeGreaterThanOrEqual(1);
  await signIn.click();
  await expect.poll(() => pollsWith(2), { timeout: 15000 }).toBeGreaterThanOrEqual(1);
  // the first sign-in's token is not polled again
  const first = pollsWith(1);
  await page.waitForTimeout(7000);
  expect(pollsWith(1)).toBe(first);
  expect(pollsWith(2)).toBeGreaterThanOrEqual(2);
  expect(server.puts).toBe(0);
});
