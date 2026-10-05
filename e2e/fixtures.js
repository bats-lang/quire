/**
 * The e2e suite's `test`: Playwright's, with the stall watch of
 * stall-capture.js on every test (#244). Every spec imports `test` from
 * here (global-setup.js checks it).
 */

import { test as base, expect } from '@playwright/test';
import { stallWatch } from './stall-capture.js';
import { MARGIN_PROJECTS, checkPageMargins } from './page-margins.js';

/** Google's sign-in script, stubbed with one that defines nothing: the
    build has a Google client (scripts/sync-clients.env), so the Sync
    screen loads the script, and the suite never reaches Google. A spec
    that plays Google (sync-android.spec.js) routes its own over this */
export async function googleStubbed(context) {
  await context.route('https://accounts.google.com/**', route => route.fulfill({
    status: 200, headers: { 'content-type': 'text/javascript' }, body: '',
  }));
}

/** The build's OAuth clients, as sync-clients.json serves them, in place
    of the ones committed in scripts/sync-clients.env: a spec that plays
    a provider serves its own test client, and one that tests a build
    with no client serves none ({}) */
export async function clientsServed(context, clients) {
  await context.route('**/sync-clients.json', route => route.fulfill({
    status: 200, headers: { 'content-type': 'application/json' }, body: JSON.stringify(clients),
  }));
}

/** Android's insets on a Pixel-class phone, in CSS px: its status bar
    above (with the camera's cutout) and its gesture navigation's handle
    below, which an app drawn edge to edge (Android 15's rule) gets as
    the safe area's insets */
export const ANDROID_INSETS = { top: 45, left: 0, right: 0, bottom: 24 };

/** Whether the test runs in the android project (playwright.config.js) */
export const onAndroid = testInfo => testInfo.project.name === 'android';

/** Gives page Android's insets, as the WebView gives an app drawn edge
    to edge (Chromium's DevTools set them) */
export async function androidInsets(page) {
  const devtools = await page.context().newCDPSession(page);
  await devtools.send('Emulation.setSafeAreaInsetsOverride', { insets: ANDROID_INSETS });
  await devtools.detach();
}

/** The app's Capacitor as the Android app has it (pwa's project: the
    plugins bridge calls), played in the page: the app runs natively, so
    bridge takes its Android branch (the system bars for full screen,
    ScreenOrientation, ScreenBrightness, Share, the files Auto Backup
    keeps, the Browser tab and app links, the device's Google account).
    What each plugin was asked is kept in window.__android, and which
    system bars are hidden (`hidden`: SystemBars with no bar named hides
    or shows both, as Capacitor's SystemBars.java does; a new process
    starts with them shown). The device has no Google account (a spec that plays one makes its own device,
    as sync-android.spec.js does) */
export function androidApp() {
  const asked = window.__android = { calls: [], files: new Map(), brightness: -1, hidden: { status: false, navigation: false } };
  const bars = o => (o && o.bar === 'StatusBar') ? ['status'] : (o && o.bar === 'NavigationBar') ? ['navigation'] : ['status', 'navigation'];
  const call = (plugin, method, answer = () => ({})) => (options = {}) => {
    asked.calls.push({ plugin, method, options });
    try { return Promise.resolve(answer(options)); } catch (e) { return Promise.reject(e); }
  };
  const missing = what => { throw new Error(`${what} does not exist`); };
  window.Capacitor = {
    isNativePlatform: () => true,
    getPlatform: () => 'android',
    Plugins: {
      SystemBars: {
        hide: call('SystemBars', 'hide', o => { for (const bar of bars(o)) asked.hidden[bar] = true; return {}; }),
        show: call('SystemBars', 'show', o => { for (const bar of bars(o)) asked.hidden[bar] = false; return {}; }),
      },
      ScreenOrientation: { lock: call('ScreenOrientation', 'lock'), unlock: call('ScreenOrientation', 'unlock') },
      ScreenBrightness: {
        getBrightness: call('ScreenBrightness', 'getBrightness', () => ({ brightness: asked.brightness })),
        setBrightness: call('ScreenBrightness', 'setBrightness', o => { asked.brightness = o.brightness; return {}; }),
      },
      Share: { share: call('Share', 'share') },
      Filesystem: {
        writeFile: call('Filesystem', 'writeFile', o => { asked.files.set(o.path, o.data); return { uri: 'file:///' + o.path }; }),
        readdir: call('Filesystem', 'readdir', o => {
          const prefix = o.path ? o.path + '/' : '';
          const names = [...new Set([...asked.files.keys()].filter(k => k.startsWith(prefix))
            .map(k => k.slice(prefix.length).split('/')[0]))];
          if (o.path && !names.length) missing('Folder');
          return { files: names.map(name => ({ name, type: 'file' })) };
        }),
        stat: call('Filesystem', 'stat', o => asked.files.has(o.path) ? { type: 'file' } : missing('File')),
        readFile: call('Filesystem', 'readFile', o => asked.files.has(o.path) ? { data: asked.files.get(o.path) } : missing('File')),
      },
      Browser: { open: call('Browser', 'open'), close: call('Browser', 'close') },
      App: { addListener: call('App', 'addListener', () => ({ remove: () => Promise.resolve() })) },
      GoogleSignIn: {
        initialize: call('GoogleSignIn', 'initialize'),
        signIn: call('GoogleSignIn', 'signIn', () => { throw Object.assign(new Error('NO_CREDENTIAL_AVAILABLE'), { code: 'NO_CREDENTIAL_AVAILABLE' }); }),
        signOut: call('GoogleSignIn', 'signOut'),
      },
    },
  };
}

export const test = base.extend({
  stallWatch: [async ({ browser }, use, testInfo) => {
    const watch = stallWatch(browser, testInfo);
    await use(watch);
    await watch.stop();
  }, { auto: true }],
  // the test's own context is watched before its page is made
  context: async ({ context, stallWatch }, use, testInfo) => {
    stallWatch.watchContext(context);
    await googleStubbed(context);
    if (onAndroid(testInfo)) await context.addInitScript(androidApp);
    await use(context);
  },
  // in the android project, every page of the test's context has
  // Android's insets before it loads anything; and a test that passed
  // and leaves the reader showing a reflowed page, paged or scrolled,
  // with the bars down has that page's head and foot measured (#296),
  // in the phone-sized projects: no spec has to remember to
  page: async ({ page }, use, testInfo) => {
    if (onAndroid(testInfo)) await androidInsets(page);
    await use(page);
    if (!MARGIN_PROJECTS.includes(testInfo.project.name)) return;
    if (testInfo.status !== 'passed' || page.isClosed()) return;
    await checkPageMargins(page, 'as the test ended');
  },
});

export { expect };
