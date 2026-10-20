/** A page's recent console, errors and requests, kept in node: a frozen page's script cannot record them. */

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
    list() { return entries.map((entry) => ({ ...entry })); },
  };
}

// a copy, not a slice: V8 keeps a slice's whole parent alive
const cut = (text) => JSON.parse(JSON.stringify(String(text === undefined || text === null ? '' : text).slice(0, TEXT_MOST)));

/** Listens for the rest of the page's life; `snapshot()` says what was kept. A failing listener is silent. */
export function keepHistory(page) {
  const kept = {
    console: ring(HISTORY_EACH),
    pageerror: ring(HISTORY_EACH),
    request: ring(HISTORY_EACH),
    requestfinished: ring(HISTORY_EACH),
    requestfailed: ring(HISTORY_EACH),
  };
  const inFlight = new Map();
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
    request.response().then((response) => { if (response) entry.status = response.status(); }).catch(() => {});
  });
  listen('requestfailed', (request) => {
    const began = inFlight.get(request);
    inFlight.delete(request);
    const failure = request.failure();
    kept.requestfailed.push({ at: Date.now(), method: request.method(), url: cut(request.url()), ms: began ? Date.now() - began.at : null, failure: cut(failure && failure.errorText) });
  });
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
