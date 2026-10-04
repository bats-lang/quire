/**
 * Evidence for a page that stops answering (#244): where its main thread
 * is when it hangs, taken while it hangs.
 *
 * A page's renderer answers a DevTools command on its main thread, so a
 * page that is already stuck in a loop cannot be attached to, and cannot
 * have its debugger enabled, any more: both wait for the main thread.
 * Only a few commands interrupt running script (Debugger.pause,
 * Debugger.setBreakpointsActive, Runtime.terminateExecution). So each page
 * is armed when it is first seen: a DevTools session of its own with the
 * debugger enabled and every breakpoint (and `debugger;` statement) made
 * inactive, which costs nothing until a pause is asked for, except that V8
 * keeps a page's wasm on its baseline compiler (Liftoff) while a debugger
 * is enabled.
 *
 * Then a watch (`stallWatch`) asks each page to evaluate `1` every 2 s.
 * A page that does not answer within 5 s, and every page of a test that
 * is about to time out, is captured (`capture`):
 *   - which DevTools commands its renderer still answers: an
 *     interrupting one (V8 alive) and a task (its main thread free);
 *   - Debugger.pause: the call frames it pauses in (script URL, function,
 *     line and column; for wasm, `wasm://` and the byte offset);
 *   - when it does not pause, a 2 s CPU profile (Profiler), if it can be
 *     taken;
 *   - each renderer process's CPU time over 1 s, which tells a busy main
 *     thread (a loop: about 1 s) from a blocked one (about 0).
 * The capture is written to the test's output directory
 * (stall-capture-<n>.json, uploaded by CI), attached to the test, and
 * summed up on stderr.
 */

import { writeFileSync } from 'node:fs';

const ANSWER_MS = 5000;     // a page that takes longer to evaluate is captured
const PROBE_EVERY_MS = 2000;
const SCAN_EVERY_MS = 1000; // new contexts and pages are armed this often
const COMMAND_MS = 2000;    // how long a DevTools command is waited for
const PAUSE_MS = 3000;
const PROFILE_MS = 2000;
const TIMEOUT_MARGIN_MS = 15000;

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** How a promise ended within `ms`: { answered, ms, value } or { error } or { answered: false }. */
async function within(promise, ms) {
  const started = Date.now();
  let timer;
  const silent = new Promise((resolve) => { timer = setTimeout(() => resolve({ answered: false, ms }), ms); });
  const outcome = Promise.resolve(promise).then(
    (value) => ({ answered: true, ms: Date.now() - started, value }),
    (error) => ({ answered: true, ms: Date.now() - started, error: String(error && error.message || error).slice(0, 300) }));
  try { return await Promise.race([outcome, silent]); } finally { clearTimeout(timer); }
}

/**
 * A page's DevTools session, made while the page still answers, with
 * the debugger enabled; `scripts` maps a script id to its URL.
 */
export async function arm(page) {
  const armed = { session: null, scripts: new Map(), error: null, pausing: false };
  try {
    const session = await page.context().newCDPSession(page);
    armed.session = session;
    session.on('Debugger.scriptParsed', (event) => {
      if (event.url) armed.scripts.set(event.scriptId, event.url);
    });
    // a pause no capture waits for (one asked for that came too late) is
    // ended at once, so the page never stays paused
    session.on('Debugger.paused', () => {
      if (!armed.pausing) session.send('Debugger.resume').catch(() => {});
    });
    await session.send('Debugger.enable');
    await session.send('Debugger.setBreakpointsActive', { active: false });
  } catch (error) {
    armed.error = String(error && error.message || error);
  }
  return armed;
}

function frameOf(frame, scripts) {
  const url = frame.url || scripts.get(frame.location.scriptId) || '';
  const column = frame.location.columnNumber || 0;
  return {
    functionName: frame.functionName || '(anonymous)',
    url,
    line: frame.location.lineNumber + 1,
    column: column + 1,
    // in a wasm frame, the column is the code's offset in the module
    ...(url.startsWith('wasm://') ? { byteOffset: column } : {}),
  };
}

/** The functions a CPU profile spent its samples in, most first, each with its stack. */
function profileSummary(profile) {
  const nodes = new Map(profile.nodes.map((node) => [node.id, node]));
  const parent = new Map();
  for (const node of profile.nodes) for (const child of node.children || []) parent.set(child, node.id);
  const hits = new Map();
  for (const sample of profile.samples || []) hits.set(sample, (hits.get(sample) || 0) + 1);
  const top = [...hits.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8);
  return {
    samples: (profile.samples || []).length,
    top: top.map(([id, count]) => {
      const stack = [];
      for (let at = id; at !== undefined; at = parent.get(at)) {
        const frame = nodes.get(at).callFrame;
        stack.push({ functionName: frame.functionName || '(anonymous)', url: frame.url, line: frame.lineNumber + 1, column: frame.columnNumber + 1 });
      }
      return { samples: count, stack };
    }),
  };
}

/** Each renderer process's CPU time (s) over `ms`, from the browser's own session. */
async function rendererCpu(browser, ms) {
  let session;
  try {
    session = (await within(browser.newBrowserCDPSession(), COMMAND_MS)).value;
    if (!session) return { error: 'no browser session' };
    const read = async () => {
      const result = await within(session.send('SystemInfo.getProcessInfo'), COMMAND_MS);
      return result.value ? result.value.processInfo.filter((process) => process.type === 'renderer') : null;
    };
    const before = await read();
    await delay(ms);
    const after = await read();
    if (!before || !after) return { error: 'SystemInfo.getProcessInfo did not answer' };
    return after.map((process) => {
      const earlier = before.find((other) => other.id === process.id);
      return { pid: process.id, cpuSeconds: earlier ? +(process.cpuTime - earlier.cpuTime).toFixed(3) : null, overSeconds: ms / 1000 };
    });
  } catch (error) {
    return { error: String(error && error.message || error) };
  } finally {
    if (session) session.detach().catch(() => {});
  }
}

/** Where a page's main thread is: see the top of this file. */
export async function capture(page, armed, reason, browser) {
  armed.capturing = true;
  try { return await captureArmed(page, armed, reason, browser); } finally { armed.capturing = false; }
}

async function captureArmed(page, armed, reason, browser) {
  const result = { reason, at: new Date().toISOString(), url: page.url(), armed: !armed.error, armError: armed.error };
  const session = armed.session;
  const cpu = browser ? rendererCpu(browser, 1000) : Promise.resolve(null);
  if (session && !armed.error) {
    // An interrupting command (answered while script runs) and a task
    const interrupt = await within(session.send('Debugger.setBreakpointsActive', { active: false }), COMMAND_MS);
    const task = await within(session.send('Runtime.evaluate', { expression: '1' }), COMMAND_MS);
    result.answers = {
      interrupt: { answered: interrupt.answered, ms: interrupt.ms, error: interrupt.error },
      task: { answered: task.answered, ms: task.ms, error: task.error },
    };
    armed.pausing = true;
    const paused = new Promise((resolve) => session.once('Debugger.paused', resolve));
    const pause = await within(session.send('Debugger.pause'), COMMAND_MS);
    const stop = await within(paused, PAUSE_MS);
    armed.pausing = false;
    if (stop.value) {
      result.paused = { reason: stop.value.reason, frames: stop.value.callFrames.map((frame) => frameOf(frame, armed.scripts)) };
      await within(session.send('Debugger.resume'), COMMAND_MS);
    } else {
      // the pause asked for is still pending: disabling the debugger
      // drops it, so the page's next script does not stop in it
      await within(session.send('Debugger.disable'), COMMAND_MS);
      await within(session.send('Debugger.enable'), COMMAND_MS);
      await within(session.send('Debugger.setBreakpointsActive', { active: false }), COMMAND_MS);
      result.pauseError = pause.error || (pause.answered ? `did not pause within ${PAUSE_MS} ms` : 'Debugger.pause was not answered');
      const enabled = await within(session.send('Profiler.enable'), COMMAND_MS);
      const started = enabled.answered && !enabled.error && await within(session.send('Profiler.start'), COMMAND_MS);
      if (started && started.answered && !started.error) {
        await delay(PROFILE_MS);
        const stopped = await within(session.send('Profiler.stop'), COMMAND_MS);
        result.profile = stopped.value ? profileSummary(stopped.value.profile) : { error: stopped.error || 'Profiler.stop was not answered' };
      } else {
        result.profile = { error: (started && started.error) || enabled.error || 'Profiler.enable or Profiler.start was not answered' };
      }
    }
  }
  result.rendererCpu = await cpu;
  result.verdict = verdict(result);
  return result;
}

function verdict(result) {
  if (!result.armed) return 'the page was not armed, so it could not be paused';
  const top = result.paused && result.paused.frames[0];
  const at = top ? `${top.functionName} (${top.url}:${top.line}:${top.column})` : '';
  if (result.answers && result.answers.task.answered) {
    return `the main thread is free: it answers a task${top ? `, and paused next in ${at}` : ''}`;
  }
  if (top) return `the main thread is running script, in ${at}`;
  if (result.answers && !result.answers.interrupt.answered) {
    return 'the renderer answers no DevTools command: its main thread is blocked outside script, or the renderer is frozen';
  }
  return 'no script on the stack, and the main thread runs no task';
}

export function summary(result) {
  const lines = [`[stall-capture] ${result.reason}: ${result.url}`, `  ${result.verdict}`];
  if (result.answers) lines.push(`  answers: interrupt ${result.answers.interrupt.answered}, task ${result.answers.task.answered}`);
  if (result.paused) for (const frame of result.paused.frames.slice(0, 12)) {
    lines.push(`    at ${frame.functionName} (${frame.url}:${frame.line}:${frame.column})`);
  }
  if (result.profile && result.profile.top) for (const entry of result.profile.top.slice(0, 3)) {
    lines.push(`    ${entry.samples} samples: ${entry.stack.map((frame) => frame.functionName).join(' < ')}`);
  }
  if (Array.isArray(result.rendererCpu)) {
    lines.push(`  renderer CPU over 1 s: ${result.rendererCpu.map((process) => `${process.pid} ${process.cpuSeconds}s`).join(', ')}`);
  }
  return lines.join('\n');
}

/**
 * The watch over one test's pages: arms each page as it is made (a
 * context's 'page' event; a context made with browser.newContext, or
 * given to watchContext, is watched at once, any other within 1 s), probes
 * each, captures a page that stops answering (once) and every page when
 * the test is about to time out. `captures` holds what it took;
 * `next(page, ms)` waits for a capture of that page.
 */
export function stallWatch(browser, testInfo) {
  const armed = new Map();     // page -> its armed session (a promise)
  const ready = new Map();     // page -> its armed session, once armed
  const watchedContexts = new Set();
  const running = new Set();   // captures in progress
  const captures = [];
  const waiters = [];
  let stopped = false;
  let count = 0;

  const watchPage = (page) => {
    if (stopped || armed.has(page) || page.isClosed()) return;
    const pending = arm(page);
    armed.set(page, pending);
    pending.then((done) => ready.set(page, done));
    probe(page);
  };
  const watchContext = (context) => {
    if (watchedContexts.has(context)) return;
    watchedContexts.add(context);
    context.on('page', watchPage);
    for (const page of context.pages()) watchPage(page);
  };
  const scan = () => { for (const context of browser.contexts()) watchContext(context); };

  const record = async (page, reason) => {
    const arming = await within(armed.get(page), COMMAND_MS);
    const armedPage = arming.value || { session: null, scripts: new Map(),
      error: 'the page was still being armed: it stopped answering before its debugger was enabled' };
    const result = await capture(page, armedPage, reason, browser);
    count += 1;
    const path = testInfo.outputPath(`stall-capture-${count}.json`);
    writeFileSync(path, JSON.stringify(result, null, 2));
    await testInfo.attach(`stall-capture-${count}`, { path, contentType: 'application/json' }).catch(() => {});
    console.error(summary(result));
    captures.push({ page, result });
    for (const waiter of waiters.splice(0)) waiter();
    return result;
  };
  const start = (page, reason) => {
    const job = record(page, reason).catch((error) => console.error(`[stall-capture] failed: ${error && error.stack || error}`));
    running.add(job);
    job.finally(() => running.delete(job));
  };

  async function probe(page) {
    while (!stopped && !page.isClosed()) {
      // not while the page is captured: its pause would stop in the probe
      if (ready.has(page) && ready.get(page).capturing) { await delay(PROBE_EVERY_MS); continue; }
      const answer = await within(page.evaluate(() => 1), ANSWER_MS);
      if (stopped || page.isClosed()) return;
      if (!answer.answered) {
        start(page, `page did not answer an evaluate within ${ANSWER_MS / 1000} s`);
        return;
      }
      await delay(PROBE_EVERY_MS);
    }
  }

  // checked at each scan, so a timeout the test changes is followed
  const started = Date.now();
  let timeoutCaptured = false;
  const nearTimeout = () => {
    if (timeoutCaptured || !testInfo.timeout) return;
    const margin = Math.min(TIMEOUT_MARGIN_MS, testInfo.timeout / 3);
    if (Date.now() < started + testInfo.timeout - margin) return;
    timeoutCaptured = true;
    for (const page of armed.keys()) if (!page.isClosed()) start(page, 'test about to time out');
  };

  // a context the test makes is watched as soon as it is made; the scan
  // is for any other way a context comes to be
  const newContext = browser.newContext;
  browser.newContext = async (...options) => {
    const context = await newContext.apply(browser, options);
    watchContext(context);
    return context;
  };

  scan();
  const scanTimer = setInterval(() => { scan(); nearTimeout(); }, SCAN_EVERY_MS);

  return {
    captures,
    watchContext,
    async next(page, ms) {
      const deadline = Date.now() + ms;
      for (;;) {
        const found = captures.find((entry) => entry.page === page);
        if (found) return found.result;
        if (Date.now() >= deadline) throw new Error(`no stall capture of the page within ${ms} ms`);
        await new Promise((resolve) => { waiters.push(resolve); setTimeout(resolve, 250); });
      }
    },
    /** The page's armed session (null when arming failed): its commands still reach a page that hangs. */
    async session(page) {
      const pending = armed.get(page);
      return pending ? (await pending).session : null;
    },
    async stop() {
      stopped = true;
      browser.newContext = newContext;
      clearInterval(scanTimer);
      for (const context of watchedContexts) context.off('page', watchPage);
      await Promise.all([...running]);
      for (const pending of armed.values()) {
        const arming = await within(pending, COMMAND_MS);
        if (arming.value && arming.value.session) arming.value.session.detach().catch(() => {});
      }
    },
  };
}
