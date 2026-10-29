/**
 * Waiting for the page to be still without waiting a time (quire#985, keyword:
 * quiet). A step that "lets the app settle" waits for an event: the app's own
 * short timers (a debounce, the recount of a chapter's pages every 250 ms) have
 * all fired and none is set, the requests the page made have ended. Both are
 * kept from the first moment a page of the context exists, so nothing a step
 * began is missed, and what is asked is a state that holds, not a duration.
 *
 * Under a fake clock (`page.clock.install()`) the page's timers are the clock's:
 * the test runs them (`page.clock.runFor`, `settled` and `rested` of
 * e2e/relaunch.js), and `timersDrained` is then true at once.
 */

/** Wraps setTimeout and clearTimeout in every page of the context, before its scripts run, and keeps the delay of
    each timer set and not yet fired or cleared (window.__timersLive(limit) counts those under limit ms). The callback
    is called as it was: the timer leaves the set as it fires, before the callback runs, so a callback that sets the
    next timer (a chain) leaves the set empty only when the chain ends. */
export async function trackTimers(context) {
  await context.addInitScript(() => {
    const live = new Map();
    const set = window.setTimeout;
    const clear = window.clearTimeout;
    window.setTimeout = function (callback, delay, ...rest) {
      const wrapped = typeof callback === 'function'
        ? function (...given) { live.delete(id); return callback.apply(this, given); }
        : callback;
      const id = set.call(window, wrapped, delay, ...rest);
      live.set(id, Number(delay) || 0);
      return id;
    };
    window.clearTimeout = function (id) { live.delete(id); return clear.call(window, id); };
    Object.defineProperty(window, '__timerDelays', { value: () => [...live.values()] });
    Object.defineProperty(window, '__timersLive', {
      value: limit => [...live.values()].filter(delay => delay < limit).length,
    });
  });
}

/** The longest chain of the app's short timers (`_settle`: 12 x 250 ms) with room for the debounces it is followed by */
const SHORT_TIMERS_MS = 3500;

/** The timers of the app that are due in under `limit` ms are none: a debounce has fired, a chain of re-counts
    has ended. The timers of a moment of the app's own (a toast's 2 s, the back button's 10 s) are not looked at. */
export async function timersDrained(page, { limit = 1000, timeout = 30000 } = {}) {
  // under a fake clock the app's timers are the clock's, not the real ones this file wraps (the only real timers
  // are the clock's own): they fire when the test runs the clock, which is run over the span every short timer
  // of the app is due in, the recount's chain (12 x 250 ms, `_settle` of src/reader.bats) the longest, and the
  // network and IndexedDB, which are not the clock's, are left alone
  if (await page.evaluate(() => globalThis.__pwClock !== undefined)) {
    await page.clock.runFor(SHORT_TIMERS_MS);
    return;
  }
  await page.waitForFunction(bound => {
    if (typeof window.__timersLive !== 'function') throw new Error('the page\'s timers are not tracked (trackTimers of e2e/quiet.js)');
    return window.__timersLive(bound) === 0;
  }, limit, { timeout, polling: 'raf' });
}

/** Both of the above for a context a spec makes itself (the test's own context has them from the fixture) */
export async function observe(context) {
  await trackTimers(context);
  trackRequests(context);
}

const inFlight = new WeakMap();

/** Keeps the requests of every page of the context that are begun and not ended (a response, a failure). */
export function trackRequests(context) {
  const watch = page => {
    if (inFlight.has(page)) return;
    const open = new Set();
    inFlight.set(page, open);
    page.on('request', request => open.add(request));
    page.on('requestfinished', request => open.delete(request));
    page.on('requestfailed', request => open.delete(request));
  };
  context.on('page', watch);
  for (const page of context.pages()) watch(page);
}

/** Resolves when the page has no request begun and not ended: each one is waited for to be answered and its body
    read (a request that fails ends too). A request that is never answered is the test's limit. */
export async function requestsDone(page, { timeout = 30000 } = {}) {
  const open = inFlight.get(page);
  if (!open) throw new Error('requestsDone: the page\'s context is not tracked (trackRequests of e2e/quiet.js)');
  const deadline = Date.now() + timeout;
  while (open.size > 0) {
    const remaining = deadline - Date.now();
    // the limit is the test's budget (it is no part of what is waited for)
    let limit;
    const over = new Promise(done => { limit = setTimeout(() => { done('over'); }, Math.max(remaining, 0)); });
    const ended = await Promise.race([over, ...[...open].map(async request => {
      const response = await request.response().catch(() => null);
      if (response) await response.finished().catch(() => null);
    })]);
    clearTimeout(limit);
    if (ended === 'over') throw new Error(`requests still open after ${timeout} ms: ${[...open].map(request => request.url()).join(', ')}`);
    // the events that take a request out of the set are delivered on the event loop's next turns
    await new Promise(next => setImmediate(next));
  }
}
