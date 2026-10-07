// The stores sync keeps its file in, played for the e2e tests: a WebDAV
// folder, Google Drive's app data folder, and the Android app's
// Capacitor (Google's authorization, and the files Auto Backup keeps). No real
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
    // the account's address about.get gives (none when null), and the
    // tokens Google's revocation endpoint was given
    address: 'reader@example.com', revoked: [],
    // the token of each request Drive took
    accepted: [],
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
    d.accepted.push(d.token);
    const id = d.file && d.file.id;
    if (request.method() === 'GET' && url.pathname === '/drive/v3/about') {
      if (url.searchParams.get('fields') !== 'user/emailAddress') return json(route, { error: 'unexpected fields' }, 400);
      return json(route, { user: d.address ? { emailAddress: d.address } : {} });
    }
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
  // Google's OAuth revocation endpoint: route it at
  // 'https://oauth2.googleapis.com/revoke'
  d.revoke = async route => {
    const request = route.request();
    const token = new URLSearchParams(request.postData() || '').get('token');
    const form = (request.headers()['content-type'] || '').startsWith('application/x-www-form-urlencoded');
    if (request.method() !== 'POST' || !form || !token) return json(route, { error: 'invalid_request' }, 400);
    d.revoked.push(token);
    return json(route, {});
  };
  d.json = () => JSON.parse(d.file.body);
  return d;
}

/** The scope the Google store asks for */
export const SCOPE = 'https://www.googleapis.com/auth/drive.appdata';

/** The app's Capacitor, played in a page: Google's authorization
    (GoogleAuthorize, bats-lang/capacitor-plugins' google-authorize) and
    the Filesystem. Both keep their state in the test (window.__google*
    and window.__file* bindings, kept by capacitorPlayed), so it outlasts
    the page as the account's grant and an app's files outlast its
    process */
function capacitor() {
  const google = method => async (options = {}) => {
    const answer = await window.__google(method, options);
    if (answer && 'reject' in answer) throw answer.reject;
    if (answer && 'resolveMade' in answer) return made[answer.resolveMade]();
    if (answer && 'rejectMade' in answer) throw made[answer.rejectMade]();
    if (answer && 'error' in answer) {
      const failure = new Error(answer.message ?? (answer.error || 'failed'));
      Object.defineProperty(failure, 'stack', { value: 'the plugin', writable: true, configurable: true });
      if (answer.error != null) failure.code = answer.error;
      throw failure;
    }
    return answer;
  };
  const made = {
    cycle: () => { const o = { name: 'cycle' }; o.self = o; return o; },
    unwritable: () => ({
      toJSON() { throw new Error('toJSON threw'); },
      toString() { throw new Error('toString threw'); },
    }),
    huge: () => ({ pad: 'x'.repeat(1048577) }),
    deep: () => { let v = []; for (let i = 1; i < 513; i++) v = [v]; return v; },
    undefined: () => undefined,
    null: () => null,
    true: () => true,
    number: () => 42,
    text: () => 'text',
    array: () => [],
    error: () => {
      const thrown = new Error('it threw');
      Object.defineProperty(thrown, 'stack', { value: 'the plugin', writable: true, configurable: true });
      return thrown;
    },
  };
  const within = name => new Error().stack.includes(name);
  const throwing = (at, name) => {
    const arms = window.__googleThrows || [];
    const armed = arms.find(arm => arm.at === at);
    if (!armed || !within(name)) return;
    if (!armed.count || --armed.count === 0) window.__googleThrows = arms.filter(arm => arm !== armed);
    throw made[armed.value]();
  };
  const decode = TextDecoder.prototype.decode;
  TextDecoder.prototype.decode = function (...a) {
    throwing('arguments', 'googleCall');
    return decode.apply(this, a);
  };
  const encode = TextEncoder.prototype.encode;
  TextEncoder.prototype.encode = function (...a) {
    throwing('keep', 'googleKeep');
    return encode.apply(this, a);
  };
  const method = name => {
    const call = google(name);
    return options => {
      throwing('method', '');
      const arms = window.__googleThrows || [];
      const returned = arms.find(arm => arm.at === 'returns');
      if (returned) {
        window.__googleThrows = arms.filter(arm => arm !== returned);
        return made[returned.value]();
      }
      return call(options);
    };
  };
  const googleAuthorize = {
    authorizationForScopes: method('authorizationForScopes'),
    authorizeScopes: method('authorizeScopes'),
    clearAuthorizationToken: method('clearAuthorizationToken'),
    revokeAccess: method('revokeAccess'),
  };
  window.Capacitor = {
    isNativePlatform: () => true,
    Plugins: {
      get GoogleAuthorize() {
        throwing('lookup', 'googleCall');
        throwing('presence', 'batsJsGoogleAuthorizeAvailable');
        return googleAuthorize;
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

/** The device's Google account, as Play services' AuthorizationClient
    answers for it: whether the reader granted the scopes (granted),
    the token it gives (token: the one Google issues now) and caches
    until it is cleared (cached), the account it names (null for none),
    and every call (calls). mode: 'consent' grants at authorizeScopes,
    'cancel' is the reader backing out of the consent screen, 'fail'
    rejects it with failure (a CommonStatusCodes name) */
function googleAccount({ token, mode }) {
  const google = { token, mode, failure: 'DEVELOPER_ERROR', granted: false, cached: null, account: 'reader@example.com', calls: [], outcomes: {} };
  const authorization = scopes => {
    if (!google.cached) google.cached = google.token;
    return { accessToken: google.cached, grantedScopes: scopes, account: google.account };
  };
  google.answer = (method, options) => {
    google.calls.push({ method, options });
    const queued = google.outcomes[method];
    if (queued && queued.length) return queued.shift();
    if (method === 'authorizationForScopes') return { authorization: google.granted ? authorization(options.scopes) : null };
    if (method === 'authorizeScopes') {
      if (google.mode === 'cancel') return { error: 'CANCELED' };
      if (google.mode === 'fail') return { error: google.failure };
      google.granted = true;
      return { authorization: authorization(options.scopes) };
    }
    if (method === 'clearAuthorizationToken') {
      if (options.accessToken === google.cached) google.cached = null;
      return undefined;
    }
    if (method === 'revokeAccess') {
      google.granted = false;
      google.cached = null;
      return undefined;
    }
    return { error: 'UNIMPLEMENTED' };
  };
  /** The calls of one method, their options */
  google.asked = method => google.calls.filter(c => c.method === method).map(c => c.options);
  return google;
}

/** The context runs the app: its Capacitor played, its Google account
    (googleAccount's: mode, and the token Google gives) and its files
    (files, [path, base64] pairs, are those it starts with: what Auto
    Backup gave back), both returned */
export async function capacitorPlayed(context, { mode = 'consent', token = 'token-1', files = [] } = {}) {
  const kept = new Map(files);
  const google = googleAccount({ token, mode });
  await context.exposeBinding('__google', (_, method, options) => google.answer(method, options));
  await context.exposeBinding('__fileWrite', (_, path, data) => { kept.set(path, data); });
  await context.exposeBinding('__fileRead', (_, path) => kept.get(path));
  await context.exposeBinding('__fileNames', () => [...kept.keys()]);
  await context.addInitScript(capacitor);
  return { files: kept, google };
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
