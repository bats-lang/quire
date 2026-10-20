/**
 * What a page did just before it stopped answering (#575): its recent console
 * messages, uncaught errors and network requests, each with its time, kept in
 * node. A frozen page's script cannot record anything, but Playwright's events
 * still arrive here, so the capture can say which requests were in flight when
 * the page froze (a request begun and not yet finished or failed).
 *
 * Cheap by design: no body is read, no request is awaited, and each text is cut.
 * Each kind keeps its last HISTORY_EACH entries (a ring), and the requests in
 * flight are at most IN_FLIGHT_MOST (the oldest is dropped past that).
 */

/** The last this many entries of each kind (console, pageerror, request, requestfinished, requestfailed). */
export const HISTORY_EACH = 100;
/** The requests begun and not yet finished or failed, at most. */
export const IN_FLIGHT_MOST = 100;
/** A message, URL or failure text is kept to this many characters. */
const TEXT_MOST = 300;

/** A ring of the last `most` entries, oldest dropped first. */
function ring(most) {
  const entries = [];
  return {
    push(entry) {
      entries.push(entry);
      if (entries.length > most) entries.shift();
    },
    list() { return entries.slice(); },
  };
}

// A kept text is a copy of at most TEXT_MOST characters, not a slice. In V8 a slice of 13 characters or
// more is a sliced string that still refers to the whole parent, so a kept slice keeps its message alive.
// Measured on node 22.22 (--expose-gc): 100 slices of 10 MB messages, the messages dropped, held 1000 MB;
// 100 copies made by JSON.parse(JSON.stringify(...)) held 0 MB. JSON keeps lone surrogates as they were.
const cut = (text) => JSON.parse(JSON.stringify(String(text === undefined || text === null ? '' : text).slice(0, TEXT_MOST)));

/**
 * Listens to the page's events for the rest of its life and returns
 * `{ snapshot() }`, which says what was kept so far (a copy, safe to write).
 * It never throws into Playwright's event dispatch: a listener that fails is
 * silent, since the history is evidence and must not fail a test.
 */
export function keepHistory(page) {
  const kept = {
    console: ring(HISTORY_EACH),
    pageerror: ring(HISTORY_EACH),
    request: ring(HISTORY_EACH),
    requestfinished: ring(HISTORY_EACH),
    requestfailed: ring(HISTORY_EACH),
  };
  // request object -> its entry in `request`, until it finishes or fails
  const inFlight = new Map();
  // each listener as it was attached, so the page's close can take it off again
  const attached = [];
  const listen = (event, listener) => {
    try {
      const wrapped = (...args) => { try { listener(...args); } catch (failure) { /* evidence only: never fail the page's events */ } };
      page.on(event, wrapped);
      attached.push([event, wrapped]);
    } catch (failure) { /* a page that cannot be listened to keeps no history */ }
  };
  listen('console', (message) => {
    kept.console.push({ at: Date.now(), type: message.type(), text: cut(message.text()) });
  });
  listen('pageerror', (error) => {
    kept.pageerror.push({ at: Date.now(), name: cut(error && error.name), message: cut(error && error.message) });
  });
  listen('request', (request) => {
    const entry = { at: Date.now(), method: request.method(), type: request.resourceType(), url: cut(request.url()) };
    kept.request.push(entry);
    inFlight.set(request, entry);
    if (inFlight.size > IN_FLIGHT_MOST) inFlight.delete(inFlight.keys().next().value);
  });
  listen('requestfinished', (request) => {
    const began = inFlight.get(request);
    inFlight.delete(request);
    const entry = { at: Date.now(), method: request.method(), url: cut(request.url()), ms: began ? Date.now() - began.at : null, status: null };
    kept.requestfinished.push(entry);
    // the status is a value the response holds: nothing is awaited for it, and a status that is not known when the entry is read stays null
    request.response().then((response) => { if (response) entry.status = response.status(); }).catch(() => {});
  });
  listen('requestfailed', (request) => {
    const began = inFlight.get(request);
    inFlight.delete(request);
    const failure = request.failure();
    kept.requestfailed.push({ at: Date.now(), method: request.method(), url: cut(request.url()), ms: began ? Date.now() - began.at : null, failure: cut(failure && failure.errorText) });
  });
  // The page's close takes the listeners off (the rings and the snapshot stay readable).
  try {
    page.once('close', () => {
      for (const [event, wrapped] of attached) page.off(event, wrapped);
      attached.length = 0;
    });
  } catch (failure) { /* a page that cannot say it closed keeps its listeners, as the page does */ }
  return {
    snapshot() {
      const now = Date.now();
      return {
        note: `the last ${HISTORY_EACH} of each kind, oldest first; \`at\` is epoch ms, the same clock as the capture; inFlight holds the requests begun and not yet finished or failed (ageMs at the capture)`,
        console: kept.console.list(),
        pageerror: kept.pageerror.list(),
        request: kept.request.list(),
        requestfinished: kept.requestfinished.list(),
        requestfailed: kept.requestfailed.list(),
        inFlight: [...inFlight.values()].map((entry) => ({ ...entry, ageMs: now - entry.at })),
      };
    },
  };
}
