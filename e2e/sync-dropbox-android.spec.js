// Dropbox in the app (#184): the sign-in goes through the system's
// browser, in a tab over the app (Capacitor's Browser plugin), and comes
// back to the app at its own address, quire://oauth/dropbox (the App
// plugin's appUrlOpen), as RFC 8252 has a native app sign in. Each
// browser context is a device running the app: its Capacitor is played
// by an init script (Browser keeps the addresses it opens, App passes
// the addresses the test opens the app at, keeping one that started the
// app until a listener is added, as Capacitor does), and Dropbox is the
// mock the browser's tests use, routed in each (no real network).

import { test, expect, clientsServed } from './fixtures.js';
import { KEY, dropbox } from './dropbox-server.js';
import {
  epubFile, importFiles, openBook, place, toLibrary, chapters, dialog,
  librarySearch, librarySettings, settingsButton, settingsScreen,
} from './helpers.js';

/** The app's Capacitor, played: Browser (when browser is true) and App
    (when app is true).
    window.__openApp(url) opens the app at url; an address kept under
    "launch-link" in sessionStorage started the app, and is passed once a
    listener is added */
function capacitor({ browser, app }) {
  const launch = sessionStorage.getItem('launch-link');
  sessionStorage.removeItem('launch-link');
  const kept = launch ? [{ url: launch }] : [];
  window.__links = { opened: [], listeners: [] };
  window.__openApp = url => window.__links.listeners.forEach(f => f({ url }));
  const plugins = {};
  if (app) plugins.App = {
    addListener: (name, f) => {
      if (name === 'appUrlOpen') {
        window.__links.listeners.push(f);
        setTimeout(() => kept.splice(0).forEach(e => f(e)), 0);
      }
      return Promise.resolve({ remove: () => Promise.resolve() });
    },
  };
  // Browser has no close: the return brings the app's activity forward,
  // which ends the tab (bats-lang/bridge#135)
  if (browser) plugins.Browser = {
    open: o => { window.__links.opened.push(o.url); return Promise.resolve(); },
  };
  window.Capacitor = { isNativePlatform: () => true, Plugins: plugins };
}

/** A device running the app, with Dropbox routed, and the build's key
    (none: key '') */
async function device(browser, server, { key = KEY, tab = true, app = true } = {}) {
  const context = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  await context.addInitScript(capacitor, { browser: tab, app });
  await context.route('https://api.dropboxapi.com/**', server.api);
  await context.route('https://content.dropboxapi.com/**', server.api);
  await clientsServed(context, key ? { dropboxClient: key } : {});
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  await page.goto('/');
  await expect(librarySearch(page)).toBeVisible();
  return { context, page, errors };
}

/** A device's errors, but a Dropbox answer the test made fail, which
    the browser logs */
const unexpected = d => d.errors.filter(e => !/status of (401|409)/.test(e));

const panel = page => dialog(page, 'Sync');
const status = page => panel(page).getByRole('status');
const dropboxButton = page => panel(page).getByRole('button', { name: 'Dropbox' });
const row = page => settingsScreen(page).getByRole('group', { name: 'Sync' }).getByRole('status');
const links = page => page.evaluate(() => ({ opened: window.__links.opened }));

async function openSync(page) {
  await librarySettings(page);
  await settingsButton(page, 'Sync ›').click();
  await expect(panel(page)).toBeVisible();
}

async function closeSync(page) {
  await panel(page).getByRole('button', { name: 'Done' }).click();
  await expect(panel(page)).toBeHidden();
  await settingsButton(page, 'Done').click();
  await expect(settingsScreen(page)).toBeHidden();
}

/** Dropbox pressed: the address of Dropbox's page the app opened in the
    system's browser */
async function signInPage(page) {
  const before = (await links(page)).opened.length;
  await dropboxButton(page).click();
  await expect.poll(async () => (await links(page)).opened.length).toBe(before + 1);
  return (await links(page)).opened[before];
}

/** Dropbox's page answered (server.answer), and the app opened at the
    address it sends the reader back to */
async function comeBack(page, server, authorize) {
  const back = server.back(authorize);
  await page.evaluate(url => window.__openApp(url), back);
  return back;
}

/** Dropbox, from the library: signed in through the system's browser,
    back on the sync screen, synced */
async function joinDropbox(page, server) {
  await openSync(page);
  const authorize = await signInPage(page);
  await comeBack(page, server, authorize);
  await expect(status(page)).toHaveText(/^Last synced on /);
  await closeSync(page);
  return authorize;
}

async function nextChapter(page, chapter) {
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(chapter);
}

const book = { title: 'Shared Book', author: 'Sync Tests', chapters: 4, rawChapters: chapters(4) };

test('in the app, Dropbox signs in through the system browser and comes back at quire://oauth/dropbox', async ({ browser }) => {
  const server = dropbox();
  const file = epubFile(book);
  const a = await device(browser, server);
  await importFiles(a.page, [file], 1);
  await openBook(a.page, 'Shared Book');
  await nextChapter(a.page, 2);
  await toLibrary(a.page);
  await openSync(a.page);
  await expect(panel(a.page)).toContainText('Dropbox\'s page opens in your browser to sign you in, then brings you back here.');
  await closeSync(a.page);
  const address = a.page.url();
  const authorize = await joinDropbox(a.page, server);
  // Dropbox's page, in the browser's tab, with S256 PKCE, coming back to
  // the app's own address; the app's page never left
  const asked = Object.fromEntries(new URL(authorize).searchParams);
  expect(authorize.startsWith('https://www.dropbox.com/oauth2/authorize?')).toBe(true);
  expect(asked).toMatchObject({
    client_id: KEY, response_type: 'code', token_access_type: 'offline', code_challenge_method: 'S256',
    scope: 'files.content.read files.content.write', redirect_uri: 'quire://oauth/dropbox',
  });
  expect(asked.state).toMatch(/^[A-Za-z0-9_-]{22}$/);
  expect(a.page.url()).toBe(address);
  // the code is exchanged once
  expect(server.exchanged).toHaveLength(1);
  expect(server.uploads).toEqual(['add']);
  expect(server.json().books).toHaveLength(1);
  await librarySettings(a.page);
  await expect(row(a.page)).toHaveText(/^Dropbox · synced (just now|1 min ago)$/);
  await settingsButton(a.page, 'Done').click();

  // another device running the app joins, and gets the place
  const b = await device(browser, server);
  await importFiles(b.page, [file], 1);
  await joinDropbox(b.page, server);
  expect(server.uploads[1]).toEqual({ '.tag': 'update', update: 'rev1' });
  await openBook(b.page, 'Shared Book');
  await expect.poll(async () => (await place(b.page)).ch).toBe(2);
  await toLibrary(b.page);

  // Turn off, made final: the grant is given back to Dropbox
  await openSync(b.page);
  await panel(b.page).getByRole('button', { name: 'Turn off' }).click();
  await expect(status(b.page)).toHaveText('Sync is off.');
  await expect.poll(() => server.revoked.length, { timeout: 15000 }).toBe(1);
  expect(unexpected(a)).toEqual([]);
  expect(unexpected(b)).toEqual([]);
  await a.context.close();
  await b.context.close();
});

test('in the app, a canceled sign-in changes nothing, and a code or an address it did not ask for is not taken', async ({ browser }) => {
  const server = dropbox();
  const a = await device(browser, server);
  await openSync(a.page);
  server.answer = 'deny';
  await comeBack(a.page, server, await signInPage(a.page));
  await expect(status(a.page)).toHaveText('Dropbox sign-in was canceled.');
  expect(server.requests).toEqual([]);

  // an address of another app's, or of quire's that is not Dropbox's
  // return, is not sync's: nothing changes
  await a.page.evaluate(() => window.__openApp('quire://oauth/dropboxes?code=x&state=AAAAAAAAAAAAAAAAAAAAAA'));
  await a.page.evaluate(() => window.__openApp('content://downloads/book.epub'));
  await expect(status(a.page)).toHaveText('Dropbox sign-in was canceled.');

  // a code with a state this app did not send is refused
  server.answer = 'allow';
  await signInPage(a.page);
  server.codes.set('stolen', { challenge: 'x', redirect: 'quire://oauth/dropbox', client: KEY });
  await a.page.evaluate(() => window.__openApp('quire://oauth/dropbox?code=stolen&state=AAAAAAAAAAAAAAAAAAAAAA'));
  await expect(status(a.page)).toHaveText('Dropbox didn\'t sign Quire in. Try again.');
  expect(server.requests).toEqual([]);
  await closeSync(a.page);
  await librarySettings(a.page);
  await expect(row(a.page)).toHaveText('Off');
  expect(unexpected(a)).toEqual([]);
  await a.context.close();
});

test('in the app, a return from Dropbox that starts the app again is taken once sync has started', async ({ browser }) => {
  const server = dropbox();
  const a = await device(browser, server);
  await openSync(a.page);
  const authorize = await signInPage(a.page);
  // Android stopped the app while the reader was in the browser: the
  // address it is opened at is what starts it again
  const back = server.back(authorize);
  await a.page.evaluate(url => sessionStorage.setItem('launch-link', url), back);
  await a.page.reload();
  await expect(status(a.page)).toHaveText(/^Last synced on /);
  expect(server.uploads).toEqual(['add']);
  expect(server.exchanged).toHaveLength(1);
  // the same address handed over again (it is taken already) is not a
  // sign-in: no exchange, nothing said
  const said = await status(a.page).textContent();
  await a.page.evaluate(url => window.__openApp(url), back);
  await a.page.waitForTimeout(500);
  expect(server.exchanged).toHaveLength(1);
  await expect(status(a.page)).toHaveText(said);
  expect(unexpected(a)).toEqual([]);
  await a.context.close();
});

test('in the app, Dropbox is not listed without the system browser\'s tab or the app\'s links, and says when the build has no key', async ({ browser }) => {
  const server = dropbox();
  // each plugin without the other: no round trip, so no Dropbox
  for (const plugins of [{ tab: false }, { app: false }]) {
    const a = await device(browser, server, plugins);
    await openSync(a.page);
    await expect(dropboxButton(a.page)).toBeHidden();
    await expect(panel(a.page).getByText('Dropbox sync isn\'t set up')).toBeHidden();
    await a.context.close();
  }

  const b = await device(browser, server, { key: '' });
  await openSync(b.page);
  await expect(panel(b.page)).toContainText('Dropbox sync isn\'t set up in this build of Quire.');
  await expect(dropboxButton(b.page)).toBeHidden();
  expect(unexpected(b)).toEqual([]);
  await b.context.close();
});
