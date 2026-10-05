// The stores sync keeps its file in, played for the e2e tests: a WebDAV
// folder, Google Drive's app data folder, and the Android app's
// Capacitor (Google's sign-in, and the files Auto Backup keeps). No real
// network. Each is shared by the devices (browser contexts) of a test;
// Dropbox is played by dropbox-server.js.

/** The WebDAV folder's user name and app password */
export const USER = 'reader';
export const PASSWORD = 'app-pass-4417';

/** The WebDAV folder: on the page's own origin, whatever port the
    suite is served on (a request to another origin would be
    cross-origin, and read as one the server does not let in) */
export const folder = page => new URL('/dav/books/', page.url()).href;

/** A WebDAV folder holding quire-sync.json, shared by the devices.
    Route its handle at '**' + '/dav/books/quire-sync.json' */
export function webdav() {
  const server = {
    body: null, version: 0, gets: 0, puts: 0,
    // a test's interference: the status every request gets, a network
    // failure, a missing folder, a write of another device's before
    // the next PUT
    status: null, offline: false, noFolder: false, putStatus: null, beforePut: null,
  };
  server.handle = async route => {
    const request = route.request();
    if (server.offline) return route.abort('internetdisconnected');
    if (server.status) return route.fulfill({ status: server.status, body: '' });
    const expected = 'Basic ' + Buffer.from(`${USER}:${PASSWORD}`).toString('base64');
    if (request.headers().authorization !== expected) return route.fulfill({ status: 401, body: '' });
    if (request.method() === 'GET') {
      server.gets++;
      if (server.body === null) return route.fulfill({ status: 404, body: '' });
      return route.fulfill({ status: 200, body: server.body, headers: { ETag: `"v${server.version}"` } });
    }
    if (request.method() === 'PUT') {
      server.puts++;
      if (server.noFolder) return route.fulfill({ status: 409, body: '' });
      if (server.putStatus) return route.fulfill({ status: server.putStatus, body: '' });
      if (server.beforePut) { const write = server.beforePut; server.beforePut = null; write(); }
      const match = request.headers()['if-match'];
      if (match !== undefined && match !== `"v${server.version}"`) return route.fulfill({ status: 412, body: '' });
      server.body = request.postData();
      server.version++;
      return route.fulfill({ status: 201, body: '' });
    }
    return route.fulfill({ status: 405, body: '' });
  };
  server.json = () => JSON.parse(server.body);
  return server;
}

/** The Google client the tests' builds have */
export const CLIENT = '1234567890-quiretest.apps.googleusercontent.com';

/** Google Drive's API for the app data folder, shared by the devices:
    the file's id, version and bytes, and every request made. Route its
    handle at 'https://www.googleapis.com/**' */
export function drive() {
  const d = {
    file: null, requests: [], token: 'token-1',
    // a test's interference: another device's write, made as the app
    // checks the version it read
    beforeCheck: null,
  };
  const cors = {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'authorization, content-type',
    'access-control-allow-methods': 'GET, POST, PATCH',
  };
  const json = (route, body, status = 200) =>
    route.fulfill({ status, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) });
  d.handle = async route => {
    const request = route.request();
    if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors });
    const url = new URL(request.url());
    d.requests.push(`${request.method()} ${url.pathname}${url.search}`);
    if (request.headers().authorization !== `Bearer ${d.token}`) return json(route, { error: 'invalid token' }, 401);
    const id = d.file && d.file.id;
    if (request.method() === 'GET' && url.pathname === '/drive/v3/files') {
      if (url.searchParams.get('spaces') !== 'appDataFolder') return json(route, { error: 'not the app data folder' }, 400);
      return json(route, { files: d.file ? [{ id, version: String(d.file.version) }] : [] });
    }
    if (request.method() === 'GET' && id && url.pathname === `/drive/v3/files/${id}`) {
      if (url.searchParams.get('alt') === 'media')
        return route.fulfill({ status: 200, headers: { ...cors, 'content-type': 'application/json' }, body: d.file.body });
      if (d.beforeCheck) { const other = d.beforeCheck; d.beforeCheck = null; other(); }
      return json(route, { version: String(d.file.version) });
    }
    if (request.method() === 'POST' && url.pathname === '/upload/drive/v3/files') {
      const type = request.headers()['content-type'] || '';
      const boundary = (type.match(/boundary=(.+)$/) || [])[1];
      const parts = request.postData().split(`--${boundary}`).slice(1, -1)
        .map(part => part.slice(part.indexOf('\r\n\r\n') + 4).replace(/\r\n$/, ''));
      const metadata = JSON.parse(parts[0]);
      d.file = { id: 'file-1', version: 1, body: parts[1], metadata };
      return json(route, { id: d.file.id, version: '1' });
    }
    if (request.method() === 'PATCH' && id && url.pathname === `/upload/drive/v3/files/${id}`) {
      d.file.body = request.postData();
      d.file.version++;
      return json(route, { id, version: String(d.file.version) });
    }
    return json(route, { error: 'not found' }, 404);
  };
  d.json = () => JSON.parse(d.file.body);
  return d;
}

/** The app's Capacitor, played in a page: Google's sign-in (mode:
    'token' gives a token for the device's account, 'none' finds no
    account, 'cancel' is the reader saying no) and the Filesystem, whose
    files are the context's (window.__file* bindings, kept by
    capacitorPlayed), so they outlast the page as an app's files outlast
    its process */
function capacitor({ mode, token }) {
  window.__google = { mode, token, signIns: 0, signOuts: 0, initialized: [] };
  window.Capacitor = {
    isNativePlatform: () => true,
    Plugins: {
      GoogleSignIn: {
        initialize: o => { window.__google.initialized.push(o); return Promise.resolve(); },
        signIn: () => {
          const g = window.__google;
          g.signIns++;
          if (g.mode === 'token') return Promise.resolve({ accessToken: g.token, email: 'reader@example.com' });
          const code = g.mode === 'none' ? 'NO_CREDENTIAL_AVAILABLE' : 'SIGN_IN_CANCELED';
          return Promise.reject(Object.assign(new Error(code), { code }));
        },
        signOut: () => { window.__google.signOuts++; return Promise.resolve(); },
      },
      Filesystem: {
        writeFile: async o => { await window.__fileWrite(o.path, o.data); return { uri: 'file:///' + o.path }; },
        // as Capacitor's: a directory's listing, and a call for a file not
        // there rejects (the app's console logs it, so the app makes none)
        readdir: async o => {
          const prefix = o.path ? o.path + '/' : '';
          const names = [...new Set((await window.__fileNames()).filter(k => k.startsWith(prefix))
            .map(k => k.slice(prefix.length).split('/')[0]))];
          if (o.path && !names.length) throw new Error('Folder does not exist');
          return { files: names.map(name => ({ name, type: 'file' })) };
        },
        stat: async o => {
          if ((await window.__fileNames()).includes(o.path)) return { type: 'file' };
          throw new Error('File does not exist');
        },
        readFile: async o => ({ data: await window.__fileRead(o.path) }),
      },
    },
  };
}

/** The context runs the app: its Capacitor played (mode as capacitor's,
    token the one Google gives), its files kept in the Map returned
    (files, [path, base64] pairs, are those it starts with: what Auto
    Backup gave back) */
export async function capacitorPlayed(context, { mode = 'token', token = 'token-1', files = [] } = {}) {
  const kept = new Map(files);
  await context.exposeBinding('__fileWrite', (_, path, data) => { kept.set(path, data); });
  await context.exposeBinding('__fileRead', (_, path) => kept.get(path));
  await context.exposeBinding('__fileNames', () => [...kept.keys()]);
  await context.addInitScript(capacitor, { mode, token });
  return kept;
}

/** Google Identity Services, played in a browser page: each request
    gives window.__gis.token (or, with window.__gis.closed, the reader
    closes the window); revokes are counted. window.__gis is made as the
    page starts (identityServicesPlayed), not by this script: the app
    loads the script only once the Sync screen looks for a token, so a
    test, which sets window.__gis.closed as that screen opens, could
    otherwise run before the script has */
const IDENTITY_SERVICES = `
  window.google = { accounts: { oauth2: {
    initTokenClient: o => {
      window.__gis.clients.push({ client_id: o.client_id, scope: o.scope });
      return { requestAccessToken: () => {
        window.__gis.requests++;
        setTimeout(() => window.__gis.closed ? o.error_callback({ type: 'popup_closed' }) : o.callback({ access_token: window.__gis.token }), 10);
      } };
    },
    revoke: (token, done) => { window.__gis.revoked.push(token); done && done(); },
  } } };
`;

/** The context's Google script is the one played above */
export async function identityServicesPlayed(context) {
  await context.route('https://accounts.google.com/gsi/client', route => route.fulfill({
    status: 200, headers: { 'content-type': 'text/javascript' }, body: IDENTITY_SERVICES,
  }));
  await context.addInitScript(() => {
    window.__gis = { token: 'token-1', closed: false, requests: 0, revoked: [], clients: [] };
  });
}
