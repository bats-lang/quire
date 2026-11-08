/**
 * The record of a press (quire#1079, keyword: press record): for a test that failed, what became of each press (Playwright's click or
 * tap, `mouse.down`/`mouse.up`) on its way to the page and who else was talking to the page meanwhile. Written as `press-record.json`
 * by the stall watch (stall-capture.js, `stop`), in the test's output directory, which CI keeps as the artifact `e2e-screenshots-<group>`.
 *
 *  1. the test's Playwright trace is Playwright's own (`trace.zip`, with the action's call log), kept for every failing test: a spec
 *     that turns the trace off loses it (pathological.spec.js did, and its red left none);
 *  2. every pointerdown, mousedown, pointerup, mouseup, click, pointercancel and lostpointercapture the page received, from a page init
 *     script (`pressInit`, no DevTools client): when, on which element, whether it was trusted, whether it was cancelled, and whether
 *     it passed the document's capture listener (one that did not was stopped by a capture listener on window, after the record's own);
 *  3. the browser's side of the same press, from Chrome's trace ring (flight-recorder.js, `inputPathOf`);
 *  4. the DevTools clients of the test's context (every `newCDPSession`: this suite's watch, gen-pwa's page watch, a test's own) with
 *     the commands each sent, so the commands of the 5 s before the press and since are in the record.
 *
 * STOPGAP (CLAUDE.md, "Pipeline and tooling improvements belong in bats or pwa"): a second app would copy this capture, so it moves with
 * pwa#289 (the two stall watches that arm every page), where the preload is decided; the ticket that moves it is quire#1079's own.
 * Nothing here opens a DevTools client of its own: the page reports through a binding of Playwright's own connection (`exposeBinding`).
 */

import { relative } from 'node:path';

export const PRESS_TYPES = ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click', 'pointercancel', 'lostpointercapture'];
/** The commands of a DevTools client are kept from this long before the press. */
export const BEFORE_PRESS_MS = 5000;
const BINDING = 'quirePressEvent';
const EVENTS_MOST = 2000;
const EVENTS_KEPT = 600;
const SESSIONS_MOST = 40;
const COMMANDS_MOST = 400;

/**
 * Runs in every frame of the context's pages before the page's own script (`addInitScript`): the record's listener on window
 * (capture) sees an event before any listener of the page, the one on document (capture) and the one on window (bubble) mark how far
 * it went, and the entry is sent through the binding in a task after the dispatch (a message channel, not a timer: a test's fake clock
 * must not hold it back), when the event's `defaultPrevented` is final. Self-contained: it is serialized.
 */
export function pressInit({ binding, types }) {
  try {
    if (window.__quirePressNoted) return;
    Object.defineProperty(window, '__quirePressNoted', { value: true });
    const seen = new WeakMap();
    const waiting = [];
    const send = (entry) => {
      try {
        const call = window[binding];
        if (typeof call === 'function') Promise.resolve(call(JSON.stringify(entry))).catch(() => {});
      } catch (failure) { /* the page goes on without the record */ }
    };
    const channel = new MessageChannel();
    channel.port1.onmessage = () => { for (const [entry, event] of waiting.splice(0)) { entry.defaultPrevented = event.defaultPrevented; send(entry); } };
    const describe = (node) => {
      try {
        if (node === document) return '#document';
        if (node === window) return '#window';
        if (!node || node.nodeType !== 1) return String(node && node.nodeName);
        let text = node.localName;
        if (node.id) text += `#${node.id}`;
        const role = node.getAttribute('role');
        if (role) text += `[role=${role}]`;
        const label = node.getAttribute('aria-label');
        if (label) text += `[aria-label=${label.slice(0, 40)}]`;
        return text;
      } catch (failure) { return '?'; }
    };
    for (const type of types) {
      window.addEventListener(type, (event) => {
        const entry = {
          type, at: performance.timeOrigin + (event.timeStamp || performance.now()), target: describe(event.target), isTrusted: event.isTrusted,
          defaultPrevented: event.defaultPrevented, atDocumentCapture: false, atWindowBubble: false, inFrame: window !== window.top,
          pointerId: event.pointerId === undefined ? null : event.pointerId, pointerType: event.pointerType || null, button: event.button, x: event.clientX, y: event.clientY,
        };
        seen.set(event, entry);
        waiting.push([entry, event]);
        channel.port2.postMessage(0);
      }, true);
      document.addEventListener(type, (event) => { const entry = seen.get(event); if (entry) entry.atDocumentCapture = true; }, true);
      window.addEventListener(type, (event) => { const entry = seen.get(event); if (entry) entry.atWindowBubble = true; }, false);
    }
  } catch (failure) { /* a page that cannot be watched is not failed by it */ }
}

/** The first frame of a stack that is neither this file nor Playwright nor node, as `path:line:column` from the working directory: who made a DevTools client. */
export function callerOf(stack) {
  for (const line of String(stack || '').split('\n').slice(1)) {
    if (/press-record\.js|node_modules|node:internal|\(<anonymous>\)/.test(line)) continue;
    // a file (or a URL of one), or a script given to node on its command line (`[eval]`, as gen-pwa's page watch is)
    const found = /\(?([^()\s]+):(\d+):(\d+)\)?\s*$/.exec(line);
    if (found) {
      const file = found[1].replace(/^file:\/\//, '');
      return `${file.startsWith('/') ? relative(process.cwd(), file) : file}:${found[2]}:${found[3]}`;
    }
  }
  return 'unknown';
}

/**
 * The presses in a list of recorded events, oldest first: a pointerdown opens one, the events that follow on the same page are its own, and it
 * is released when a pointerup or a mouseup came (a click is the page's own answer to both). A mouse event with no pointerdown before it opens one.
 */
export function pressesOf(events) {
  const presses = [];
  for (const event of events) {
    let press = [...presses].reverse().find((each) => each.page === event.page && each.inFrame === event.inFrame);
    if (event.type === 'pointerdown' || !press || (event.type === 'mousedown' && press.events.includes('mousedown'))) {
      press = { page: event.page, inFrame: event.inFrame, downAt: event.at, target: event.target, pointerId: event.pointerId, events: [], releasedAt: null, clickAt: null, stopped: [] };
      presses.push(press);
    }
    press.events.push(event.type);
    if ((event.type === 'pointerup' || event.type === 'mouseup') && press.releasedAt === null) press.releasedAt = event.at;
    if (event.type === 'click') press.clickAt = event.at;
    if (event.stoppedByWindowCapture) press.stopped.push(`${event.type} stopped by a capture listener on window`);
  }
  return presses.map((press) => ({ ...press, released: press.releasedAt !== null }));
}

/** The record of one test's presses and DevTools clients; `track` and `listen` are called for each context, `snapshot` once the test is over. */
export function pressRecord() {
  const events = [];
  const sessions = [];
  const pageNumbers = new WeakMap();
  let pagesSeen = 0;
  let failedAt = null;
  const pageNumber = (page) => {
    if (!page) return 0;
    if (!pageNumbers.has(page)) { pagesSeen += 1; pageNumbers.set(page, pagesSeen); }
    return pageNumbers.get(page);
  };

  const follow = (session, createdBy) => {
    const entry = { id: sessions.length + 1, createdBy, createdAt: Date.now(), detachedAt: null, commands: [] };
    sessions.push(entry);
    if (sessions.length > SESSIONS_MOST) sessions.shift();
    const send = session.send;
    session.send = function (method, params) {
      const command = { at: Date.now(), method, ...(params && typeof params.type === 'string' ? { detail: params.type } : params && typeof params.expression === 'string' ? { detail: params.expression.slice(0, 80) } : {}) };
      entry.commands.push(command);
      if (entry.commands.length > COMMANDS_MOST) entry.commands.shift();
      // the same promise as the caller would have had: it settles the same way, and a rejection is still the caller's to handle
      return send.apply(this, arguments).then(
        (value) => { command.answeredAfterMs = Date.now() - command.at; return value; },
        (error) => { command.failed = String((error && error.message) || error).slice(0, 120); throw error; },
      );
    };
    const detach = session.detach;
    session.detach = function () { entry.detachedAt = Date.now(); return detach.apply(this, arguments); };
  };

  return {
    /** Notes every DevTools client the context makes from now on (synchronously, before any page is watched), and who made it. */
    track(context) {
      const original = context.newCDPSession;
      if (typeof original !== 'function') return;
      context.newCDPSession = async function (...target) {
        const createdBy = callerOf(new Error('who').stack);
        const session = await original.apply(context, target);
        try { follow(session, createdBy); } catch (failure) { /* a client that cannot be followed is only not listed */ }
        return session;
      };
    },
    /** The page side: the binding the init script reports to, and the init script, before the context makes its first page. */
    async listen(context) {
      await context.exposeBinding(BINDING, (source, text) => {
        try {
          const entry = JSON.parse(text);
          entry.page = pageNumber(source.page);
          // the document's capture listener is the next one after the record's own on the path: an event that did not reach it was stopped by a capture listener on window
          entry.stoppedByWindowCapture = !entry.atDocumentCapture;
          events.push(entry);
          if (events.length > EVENTS_MOST) events.shift();
        } catch (unreadable) { /* an entry that cannot be read is not kept */ }
      });
      await context.addInitScript(pressInit, { binding: BINDING, types: PRESS_TYPES });
    },
    /** The test ended unexpectedly: the clients that are attached now are the ones attached at the failure. */
    markFailed() { if (failedAt === null) failedAt = Date.now(); },
    /** The record, from what was kept; `inputPath` is the browser's side (flight-recorder.js `inputPathOf`) or the reason there is none. */
    snapshot({ test, project, inputPath }) {
      const failed = failedAt === null ? Date.now() : failedAt;
      const presses = pressesOf(events);
      const last = presses[presses.length - 1] || null;
      const lost = [...presses].reverse().find((each) => !each.released) || null;
      const pressAt = (lost || last || { downAt: failed }).downAt;
      const inside = (command, from, to) => command.at >= from && command.at <= to;
      return {
        note: 'quire#1079: the press record of a failed test. `trace.zip` beside this file is Playwright\'s (the action\'s call log and the hit-target check\'s verdict); `events` are what the page received (times are epoch ms, the page\'s clock); `inputPath` is Chrome\'s ring (the browser\'s clock, ordered, not comparable to the page\'s); `devtoolsClients` are the DevTools clients of the test\'s context made through newCDPSession. Playwright\'s own connection is always attached and its commands are in the trace.',
        test, project,
        failedAt: failed,
        pressAt,
        presses,
        lastUnreleasedPress: lost,
        events: events.slice(-EVENTS_KEPT),
        inputPath: inputPath === undefined ? { unavailable: 'no browser trace was kept for this test (the recorder is off, or the trace failed)' } : inputPath,
        devtoolsClients: sessions.map((session) => ({
          id: session.id, createdBy: session.createdBy, createdAt: session.createdAt, attached: session.createdAt <= failed && (session.detachedAt === null || session.detachedAt > failed),
          commandsKept: session.commands.length,
          commandsBeforePress: session.commands.filter((command) => inside(command, pressAt - BEFORE_PRESS_MS, pressAt)),
          commandsSincePress: session.commands.filter((command) => inside(command, pressAt + 1, failed)),
        })),
      };
    },
  };
}
