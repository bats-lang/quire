// Devices and stores for the sync specs that look at what a sync leaves
// on the page and in the file (sync-idempotent.spec.js): a device is a
// browser context with its clock fixed, a store is one of the places the
// suite plays (a WebDAV folder, Dropbox, Google Drive's app data folder,
// Fastmail's WebDAV, and the file Android's Auto Backup keeps), each
// with how a device signs in to it and where its file's bytes are.
// sync.spec.js keeps its own copies of the small helpers it has; these
// are the same steps, made to be shared.

import { expect, googleStubbed, clientsServed } from './fixtures.js';
import {
  start, importFiles, openBook, toLibrary, dialog, clickControl, librarySearch, librarySettings,
  settingsButton, settingsScreen, bookPage, selectText, selectionButton, reload, pageShown,
} from './helpers.js';
import {
  webdav, folder, USER, PASSWORD, drive, CLIENT, capacitorPlayed,
} from './sync-stores.js';
import { dropbox, KEY } from './dropbox-server.js';
import { sharedBook } from './sync-books.js';

/** The book every device holds (sync-books.js: four chapters of
    paragraphs "Para 1.0"...) */
export const book = sharedBook;

/** The time every device starts at, to the minute: a highlight is
    named by the minute it was made in (the annotation's id), so a test
    that wants two to be the same annotation, or two, sets it */
export const NOON = new Date('2026-06-01T10:00:00Z');
export const minutesLater = (time, minutes) => new Date(time.getTime() + minutes * 60000);

/** The clock of a device's page, fixed at time: Date.now does not run
    on (a minute boundary crossed while a test runs would change what an
    annotation's id is made of), and the timers still do. A page loaded
    again starts over, so a test that reloads sets it again */
export async function clockFixed(page, time) {
  await page.clock.setFixedTime(time);
}

/** A device's errors, but the answers a test makes the server give (a
    file not there yet, credentials refused, Dropbox's and WebDAV's
    conflicts), which the browser logs */
export const unexpected = d => d.errors.filter(e => !/status of (401|404|409|412)/.test(e));

export const panel = page => dialog(page, 'Sync');
export const status = page => panel(page).getByRole('status');

export async function openSync(page) {
  await librarySettings(page);
  await settingsButton(page, 'Sync').click();
  await expect(panel(page)).toBeVisible();
}

export async function closeSync(page) {
  await panel(page).getByRole('button', { name: 'Done' }).click();
  await expect(panel(page)).toBeHidden();
  await settingsButton(page, 'Done').click();
  await expect(settingsScreen(page)).toBeHidden();
}

/** The page hidden (the app put in the background): a sync */
export async function hide(page) {
  await page.evaluate(() => {
    Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
    document.dispatchEvent(new Event('visibilitychange'));
    Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true });
  });
}

// ---- the stores ----

/** A browser context with the clock fixed and the app started on its
    page; routes (a function of the context) are set before the page */
async function started(browser, time, routes = async () => {}) {
  const context = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  await routes(context);
  const page = await context.newPage();
  await page.clock.install({ time });
  await clockFixed(page, time);
  const errors = await start(page);
  return { context, page, errors, time };
}

/** The Capacitor of an app that has no plugin of its own (Fastmail's
    requests are native: a CORS check does not stand in their way) */
const bareApp = () => { window.Capacitor = { isNativePlatform: () => true, Plugins: {} }; };

const FASTMAIL = 'https://myfiles.fastmail.com';
const FASTMAIL_FILE = '/quire/quire-sync.json';
const FASTMAIL_ADDRESS = 'reader@fastmail.com';
const FASTMAIL_PASSWORD = 'fm-app-9k2x7q4w';

/** The mock Fastmail of sync-fastmail.spec.js, as the app's native
    requests meet it (it lets the page's origin in): the folder made by
    MKCOL, the file read with its ETag and written with If-Match */
function fastmail() {
  const server = { requests: [], folder: false, body: null, version: 0, puts: 0 };
  server.handle = async route => {
    const request = route.request();
    const headers = {
      'Access-Control-Allow-Origin': request.headers().origin || '*',
      'Access-Control-Allow-Methods': 'GET, PUT, MKCOL, PROPFIND, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type, If-Match',
      'Access-Control-Expose-Headers': 'ETag',
    };
    const path = new URL(request.url()).pathname;
    server.requests.push(`${request.method()} ${path}`);
    if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers, body: '' });
    const basic = 'Basic ' + Buffer.from(`${FASTMAIL_ADDRESS}:${FASTMAIL_PASSWORD}`).toString('base64');
    if (request.headers().authorization !== basic) return route.fulfill({ status: 401, headers, body: '' });
    if (request.method() === 'MKCOL' && path === '/quire/') {
      if (server.folder) return route.fulfill({ status: 405, headers, body: '' });
      server.folder = true;
      return route.fulfill({ status: 201, headers, body: '' });
    }
    if (path === FASTMAIL_FILE && request.method() === 'GET') {
      if (server.body === null) return route.fulfill({ status: 404, headers, body: '' });
      return route.fulfill({ status: 200, headers: { ...headers, ETag: `"v${server.version}"` }, body: server.body });
    }
    if (path === FASTMAIL_FILE && request.method() === 'PUT') {
      if (!server.folder) return route.fulfill({ status: 409, headers, body: '' });
      const match = request.headers()['if-match'];
      if (match !== undefined && match !== `"v${server.version}"`) return route.fulfill({ status: 412, headers, body: '' });
      server.puts++;
      server.body = request.postData();
      server.version++;
      return route.fulfill({ status: 201, headers, body: '' });
    }
    return route.fulfill({ status: 404, headers, body: '' });
  };
  return server;
}

/** Each store the suite plays. A store is made once for a test
    (`make`), its devices come from `device(browser, server, time)` and
    sign in with `join(device, server)` (the library shown again after),
    `bytes` are the file's bytes as the store holds them (null: none
    yet), `writes` counts the writes it took and `requests` all it was
    asked, and `sync(device, server)` is one sync the reader starts (the
    Sync screen's Sync now, or, where no store is chosen, the page
    hidden). Two devices share a store, except the Auto Backup file,
    which is each device's own: `shared` says whether they do */
export const stores = {
  webdav: {
    name: 'WebDAV',
    shared: true,
    make: webdav,
    device: (browser, server, time) => started(browser, time, async context => {
      await googleStubbed(context);
      await context.route('**/dav/books/quire-sync.json', server.handle);
    }),
    async join(d) {
      await openSync(d.page);
      await panel(d.page).getByRole('button', { name: 'WebDAV', exact: true }).click();
      await panel(d.page).getByLabel('Folder URL').fill(folder(d.page));
      await panel(d.page).getByLabel('User name').fill(USER);
      await panel(d.page).getByLabel('Password', { exact: true }).fill(PASSWORD);
      await panel(d.page).getByRole('button', { name: 'Sign in to WebDAV' }).click();
      await expect(status(d.page)).toHaveText(/^Last synced on /);
      await closeSync(d.page);
    },
    bytes: server => server.body,
    writes: server => server.puts,
    requests: server => server.gets + server.puts,
  },

  dropbox: {
    name: 'Dropbox',
    shared: true,
    make: dropbox,
    device: (browser, server, time) => started(browser, time, async context => {
      await context.route('https://www.dropbox.com/oauth2/authorize**', server.authorize);
      await context.route('https://api.dropboxapi.com/**', server.api);
      await context.route('https://content.dropboxapi.com/**', server.api);
      await clientsServed(context, { dropboxClient: KEY });
    }),
    async join(d) {
      await openSync(d.page);
      await panel(d.page).getByRole('button', { name: 'Dropbox', exact: true }).click();
      await panel(d.page).getByRole('button', { name: 'Sign in to Dropbox' }).click();
      // the page goes to Dropbox's and comes back with a code
      await d.page.waitForURL(url => url.searchParams.get('oauth') === 'dropbox' && url.searchParams.has('code'));
      await expect(status(d.page)).toHaveText(/^Last synced on /);
      await closeSync(d.page);
      await clockFixed(d.page, d.time);
    },
    bytes: server => server.file,
    writes: server => server.uploads.length,
    requests: server => server.requests.length,
  },

  drive: {
    name: 'Android (Google Drive)',
    shared: true,
    make: drive,
    device: async (browser, server, time) => {
      let played;
      const d = await started(browser, time, async context => {
        played = await capacitorPlayed(context, { mode: 'consent', token: server.token });
        await context.route('https://www.googleapis.com/**', server.handle);
        await context.route('https://oauth2.googleapis.com/revoke', server.revoke);
        await clientsServed(context, { googleWebClient: CLIENT });
      });
      return { ...d, files: played.files, google: played.google };
    },
    async join(d) {
      await openSync(d.page);
      await panel(d.page).getByRole('button', { name: 'Google Drive', exact: true }).click();
      await panel(d.page).getByRole('button', { name: 'Sign in to Google Drive' }).click();
      await expect(status(d.page)).toHaveText(/^Last synced on /);
      await closeSync(d.page);
    },
    bytes: server => (server.file ? server.file.body : null),
    writes: server => (server.file ? server.file.version : 0),
    requests: server => server.requests.length,
  },

  fastmail: {
    name: 'Fastmail',
    shared: true,
    make: fastmail,
    device: (browser, server, time) => started(browser, time, async context => {
      await context.addInitScript(bareApp);
      await context.route(`${FASTMAIL}/**`, server.handle);
    }),
    async join(d) {
      await openSync(d.page);
      await panel(d.page).getByRole('button', { name: 'Fastmail', exact: true }).click();
      await panel(d.page).getByLabel('Fastmail address').fill(FASTMAIL_ADDRESS);
      await panel(d.page).getByLabel('Fastmail app password').fill(FASTMAIL_PASSWORD);
      await panel(d.page).getByRole('button', { name: 'Sign in to Fastmail' }).click();
      await expect(status(d.page)).toHaveText(/^Last synced on /);
      await closeSync(d.page);
    },
    bytes: server => server.body,
    writes: server => server.puts,
    requests: server => server.requests.filter(r => !r.startsWith('OPTIONS')).length,
  },

  // no store chosen: the file Android's Auto Backup keeps, in the app's
  // files, merged and written at each sync point. It is a device's own
  // (a reinstalled device gets back the files of the one before), so the
  // "server" is the device itself
  autobackup: {
    name: 'Auto Backup file',
    shared: false,
    make: () => ({}),
    // files: those the device starts with (what Auto Backup gave back)
    device: async (browser, server, time, files = []) => {
      let played;
      const d = await started(browser, time, async context => {
        played = await capacitorPlayed(context, { mode: 'cancel', files });
        await clientsServed(context, {});
      });
      const kept = played.files;
      d.files = kept;
      d.google = played.google;
      d.written = 0;
      const set = kept.set.bind(kept);
      kept.set = (key, value) => { if (key === 'backup/quire-sync.json') d.written++; return set(key, value); };
      return d;
    },
    async join() {},
    bytes: (server, d) => {
      const data = d.files.get('backup/quire-sync.json');
      return data ? Buffer.from(data, 'base64').toString() : null;
    },
    writes: (server, d) => d.written,
    requests: (server, d) => d.written,
  },
};

/** One sync the reader starts, done: the store has taken a write and
    this device has had time to take the merge (it takes it once the
    file is written) */
export async function sync(store, server, d) {
  const before = store.writes(server, d);
  if (store.shared) {
    if (!(await panel(d.page).isVisible())) await openSync(d.page);
    await panel(d.page).getByRole('button', { name: 'Sync now' }).click();
    await expect.poll(() => store.writes(server, d)).toBeGreaterThan(before);
    await expect(status(d.page)).toHaveText(/^Last synced on /);
    await d.page.waitForTimeout(300);
    await closeSync(d.page);
  } else {
    await hiddenSync(store, server, d);
  }
}

/** The page hidden, and the sync it starts ended */
export async function hiddenSync(store, server, d) {
  const before = store.writes(server, d);
  await hide(d.page);
  await expect.poll(() => store.writes(server, d)).toBeGreaterThan(before);
  await d.page.waitForTimeout(300);
}

// ---- annotations, on the page and in the list ----

export const annotationsDialog = page => dialog(page, 'Annotations');

/** A highlight of characters [from, to) of the first paragraph shown */
export async function highlight(page, from, to) {
  await selectText(page, from, to);
  await selectionButton(page, 'Highlight').click();
}

const LABELS = new Set(['Annotations', 'Export', 'Share', 'All', 'Yellow', 'Orange', 'Underlined',
  'Add note', 'Edit note', 'Delete', 'No highlights yet']);

/** What the open book shows of its annotations: the quotes the list
    gives (and how many Delete buttons it has), and the ranges painted
    over the page, each as its mark's name and text (::highlight
    (bats-mark-n), as annotations.spec.js counts them), sorted */
export async function shown(page) {
  await clickControl(page, 'Annotations');
  const list = annotationsDialog(page);
  await expect(list).toBeVisible();
  const lines = (await list.innerText()).split('\n').map(line => line.trim()).filter(Boolean);
  const quotes = lines.filter(line => /\w/.test(line) && !LABELS.has(line) && !/^CHAPTER /i.test(line) && !/^No /.test(line)).sort();
  const deletes = await list.getByRole('button', { name: 'Delete' }).count();
  await list.getByRole('button', { name: 'Close' }).click();
  await expect(list).toBeHidden();
  return { quotes, deletes, painted: await painted(page) };
}

/** The ranges painted over the page, "bats-mark-n: text", sorted */
export function painted(page) {
  return page.evaluate(() => {
    const found = [];
    for (const [name, ranges] of CSS.highlights) for (const range of ranges) found.push(`${name}: ${range.toString()}`);
    return found.sort();
  });
}

/** The list and the page agree: every quote listed is painted once and
    nothing else is */
export function agree(view) {
  expect(view.deletes).toBe(view.quotes.length);
  expect(view.painted.map(p => p.replace(/^[^:]*: /, '')).sort()).toEqual(view.quotes);
}

/** The book open on the page shown: from the library, opened; in the
    book already (a reload may have restored it), waited for */
export async function inBook(page) {
  if (await librarySearch(page).isVisible()) await openBook(page, 'Shared Book');
  else await pageShown(page);
}

/** The app opened again: the page loaded anew (its clock fixed again) */
export async function reopen(d) {
  await reload(d.page);
  await clockFixed(d.page, d.time);
  await expect(bookPage(d.page).or(librarySearch(d.page))).toBeVisible();
}

export { toLibrary, importFiles, openBook };

// ---- the file ----

/** Every path at which two parsed files differ ("books.0.opened"), a
    list value compared whole at its own path when its length differs */
export function changedPaths(a, b, path = '') {
  if (a === b) return [];
  const object = v => v !== null && typeof v === 'object';
  if (!object(a) || !object(b) || Array.isArray(a) !== Array.isArray(b)) return [path];
  const keys = [...new Set([...Object.keys(a), ...Object.keys(b)])];
  return keys.flatMap(key => changedPaths(a[key], b[key], path ? `${path}.${key}` : key));
}

/** A file without the stamps of the devices that wrote it: the
    devices' own numbers (the `devices` entries, each named by the clock
    of the device that first made it) are replaced by their order, and
    `placeDevice` (the device that read the place) by "a device of the
    file", checked to be one: of a place never dated (placeModified 0)
    it is the device that wrote the file last, whichever it was (the
    book's place was never moved, so a device that moved nothing
    claims it; reported on #429). What the file keeps for the reader
    (books, places, annotations, deletions, collections) is untouched,
    so two files are the same file when they are equal as text after
    this */
export function withoutStamps(text) {
  const file = JSON.parse(text);
  // (the order of the devices is the writer's: the one writing puts its own first)
  file.devices.sort((a, b) => a.device - b.device);
  const numbers = file.devices.map(entry => entry.device);
  file.devices = file.devices.map((entry, n) => ({ ...entry, device: `device${n}` }));
  for (const kept of file.books) {
    if (!('placeDevice' in kept)) continue;
    if (!numbers.includes(kept.placeDevice)) throw new Error(`placeDevice ${kept.placeDevice} is no device of the file: ${numbers}`);
    kept.placeDevice = 'a device of the file';
  }
  return JSON.stringify(file, null, 1);
}
