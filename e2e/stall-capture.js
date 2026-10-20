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
 *     thread (a loop: about 1 s) from a blocked one (about 0);
 *   - when the page is frozen (it answers nothing and its renderer used
 *     almost no CPU, #575 and #591; a page that is only busy is left alone,
 *     since gdb stops the process), the renderer's native stacks: gdb's
 *     backtrace of every thread, the kernel's stack, wait channel and system
 *     call of every thread, and what resolves the raw offsets offline (the
 *     binary's path and build id, the load address of every module, the
 *     executable anonymous regions where JIT code lives);
 *   - when gdb gives no stacks (not installed, or the kernel will not let it
 *     attach) the user-space stacks are asked of `eu-stack` and then `pstack`,
 *     and what none could give is said as `not available: <why>`
 *     (`userSpaceStacks`, `fallbackStacks`), never a failure of the test;
 *   - the kernel's view of the other browser processes too (the browser
 *     process, the GPU process: `native.browserProcesses`), with their
 *     user-space stacks from the fallback tools when a renderer is frozen;
 *   - the kernel's record (`kernel`): each renderer's cgroup and the OOM and
 *     hung-task lines of dmesg, read before the native stacks;
 *   - what the page did before it stopped (`history`, e2e/page-history.js);
 *   - the browser's Mojo messages of the 10 s before the renderer's last one
 *     (`mojoMessages`, a Chromium trace of the test, #737).
 */

import { execFile } from 'node:child_process';
import { accessSync, closeSync, constants, existsSync, openSync, readdirSync, readFileSync, readlinkSync, readSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { delimiter, isAbsolute, join } from 'node:path';
import { bindAttempts } from './attempt-log.js';
import { keepHistory } from './page-history.js';
import { runnerLoad, sampleRunner } from './runner-load.js';

const ANSWER_MS = 5000;     // a page that takes longer to evaluate is captured
const PROBE_EVERY_MS = 2000;
const SCAN_EVERY_MS = 1000; // new contexts and pages are armed this often
const COMMAND_MS = 2000;    // how long a DevTools command is waited for
const PAUSE_MS = 3000;
const PROFILE_MS = 2000;
const METRICS_MS = 1000;    // Performance.getMetrics, around an attempt (#600): a busy page is noted, not waited for
const HARVEST_MS = 1000;
// After a read the page did not answer, none is made for this long (#715), unless the
// probe hears from the page sooner (it asks every PROBE_EVERY_MS and resets it). 5 s,
// by what comparable breakers do: Hystrix's circuit stays open for sleepWindowInMilliseconds
// 5000 after calls that time out at 1000 ms, the same ratio as METRICS_MS here (the
// Hystrix wiki, Configuration); resilience4j's waitDurationInOpenState (60 s) and Envoy's
// outlier base_ejection_time (30 s) protect a service from load and guard a remote
// dependency, where this guards only a diagnostic read, whose cost is a lost sample, so it
// is the short end. It is also ANSWER_MS: a page silent that long is captured by the probe.
const DEAF_MS = 5000;
const LONG_TASKS_MOST = 300;
const ATTEMPTS_MOST = 300;
const LOAD_WINDOW_MS = 60000; // the runner's load, as far back as a capture reports it (#600)
// a test's pages are captured this long before its timeout (a third of a shorter one)
const TIMEOUT_MARGIN_MS = 15000;

// The native stacks (#575, #591) of a page judged frozen. Every external
// command has a hard limit, so a capture never hangs the run
const CPU_WINDOW_MS = 1000;             // the renderers' CPU time is read over this long
// A renderer is frozen, not busy, when it used less CPU than this over
// CPU_WINDOW_MS. Measured here (a 2 s window, Chrome headless shell): a
// renderer in a synchronous loop used 0.98 s of CPU per second, an idle
// one and a SIGSTOPped one 0 s, and the frozen renderers of #575 and #591
// 0 s and 0.02 s. A page that is only slow (heavy layout: pathological.spec.js,
// #522's 15 s layout, a loaded runner) spends about a second a second, so it
// is far above this and is not attached to.
export const FROZEN_CPU_SECONDS = 0.1;
const GDB_SECONDS = 15;                 // the backtraces: `timeout` ends gdb after this plus CORE_SECONDS (and kills it 1 s later)
// A core file of each frozen renderer is written by the same gdb, after the
// backtraces (stack first, then core), so the renderer is stopped once. The
// whole of gdb's time, the backtraces and the core, is bounded by `timeout`
const CORE_SECONDS = 15;
// Limits on what is kept: the core as gdb writes it, and gzipped (what is uploaded)
export const CORE_MAX_BYTES = 1024 * 1024 * 1024;
export const CORE_GZ_MAX_BYTES = 200 * 1024 * 1024;
const GZIP_MS = 60000;
const CORE_QUIET_MIN_BYTES = 16 * 1024 * 1024; // an empty mapping at least this large is left out of the core
const CORE_QUIET_MOST = 200;
const GDB_MS = (GDB_SECONDS + CORE_SECONDS) * 1000 + 2000; // node's own limit on the same command: after `timeout -s KILL`, so a backstop
const HELPER_MS = 5000;                 // readelf, sudo tail, the gdb version check
const NATIVE_MOST = 6;                  // renderers whose stacks are taken, at once
const CORE_MOST = 2;                    // and whose core is written too (a core is up to CORE_MAX_BYTES of disk until it is gzipped)
const STACK_FRAMES = 40;
const FALLBACK_MS = 10000;              // eu-stack, pstack: each, when gdb gave no stacks
const TRACE_CATEGORIES = ['disabled-by-default-mojom'];
const TRACE_BUFFER_KB = 16384;
const TRACE_WINDOW_US = 10000000;
export const TRACE_PROCESS_MOST = 10000; // events of one process (about 2 MB)
const TRACE_ARGS_CHARS = 160;
const TRACE_TEXT_CHARS = 120;
const TRACE_END_MS = 8000; // a frozen renderer's flush takes about 5 s (measured, #737)
// the trace's start awaited, Tracing.end, and the flush: the longest the watch's end waits for it
const MOJO_END_MOST_MS = 2 * COMMAND_MS + TRACE_END_MS;
// stop() waits this long for captures still running (the native step can
// outlast the test); what they found by then is already written (`save`)
export const TEARDOWN_MS = 10000;
// and stop() then ends their commands (at most HELPER_MS), waits 1.5 s more, and waits for the Mojo trace to end
export const TEARDOWN_MOST_MS = TEARDOWN_MS + HELPER_MS + 1500 + MOJO_END_MOST_MS;

/**
 * The longest a capture of a page that answers can take, every wait in
 * `record` and `captureArmed` run out one after another: the arming
 * waited for (1 command); the interrupting command, the task and
 * Debugger.pause (3); the pause itself (PAUSE_MS); the debugger
 * disabled, enabled and its breakpoints made inactive again (3);
 * Profiler.enable and Profiler.start (2); the profile (PROFILE_MS);
 * Profiler.stop (1); the kernel's log (dmesg, HELPER_MS). The renderers' CPU
 * time (a session, two reads and 1 s between them) is taken alongside, and is
 * shorter.
 * 10 x 2 s + 3 s + 2 s + 5 s + 8 s = 38 s.
 */
// Its Mojo trace ends alongside the steps and is awaited last (up to MOJO_END_MOST_MS; its TRACE_END_MS is the 8 s above).
export const CAPTURE_MOST_MS = 10 * COMMAND_MS + PAUSE_MS + PROFILE_MS + HELPER_MS + TRACE_END_MS;

/**
 * What the native stacks of a frozen page add, every wait run out: an
 * evaluate of an unarmed page (1 command); the renderers' CPU time awaited
 * (the browser session, two reads and CPU_WINDOW_MS: 3 commands and the
 * window, all of it counted, though it began alongside the probes above);
 * gdb's version; per renderer (side by side) readelf (the binary's
 * notes, sections and version, the system libraries' notes, dpkg), `sudo tail` for the kernel stacks, gdb (backtraces and core), the two fallback stack tools when gdb gave none, the two fallback tools again for the browser and GPU processes (after the renderers'), and gzip. A capture of a frozen page takes at most
 * CAPTURE_MOST_MS and this.
 */
export const NATIVE_MOST_MS = COMMAND_MS + (3 * COMMAND_MS + CPU_WINDOW_MS) + HELPER_MS + 8 * HELPER_MS + GDB_MS + GZIP_MS + 2 * FALLBACK_MS
  + 2 * FALLBACK_MS; // the browser's and the GPU's fallback tools

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

// QUIRE_NO_STALL_ARM=1 (anything but empty or 0) skips arming: the debugger is
// never enabled, so a run can be compared with and without it (#575, #591: the
// frozen renderers all had it armed, which is a suspect, not evidence). The
// watch still probes and still takes the native stacks; it loses what needs
// the debugger (the pause, the profile, the answers). Read at each arming.
// Nothing sets it: it is for a run someone chooses to make.
const NO_ARM = 'QUIRE_NO_STALL_ARM';
const armingOff = () => !['', '0'].includes(process.env[NO_ARM] || '');

// One Mojo trace per browser and test (#737): Chromium gives its events only at the end, so it is ended once.
const mojoTraces = new WeakMap(); // browser -> { session, received, ready, error, taken }

// the trace's clock: CLOCK_MONOTONIC in microseconds on Linux, as process.hrtime
const traceNow = () => Number(process.hrtime.bigint() / 1000n);

/** One event as a capture keeps it, its args and names cut. */
const keepTraceEvent = (event) => ({
  ts: event.ts,
  ph: event.ph,
  pid: event.pid,
  tid: event.tid,
  cat: event.cat,
  name: String(event.name).slice(0, TRACE_TEXT_CHARS),
  ...(event.dur === undefined ? {} : { dur: event.dur }),
  ...(event.ph === 'M' && event.name === 'process_name' ? { processName: String(event.args && event.args.name || '').slice(0, TRACE_TEXT_CHARS) } : {}),
  ...(event.ph !== 'M' && event.args ? { args: JSON.stringify(event.args).slice(0, TRACE_ARGS_CHARS) } : {}),
});

/** Opt-in (QUIRE_MOJO_TRACE=1, #737): a test's watch traces its browser unless it is @serial. */
export const traceWantedFor = (testInfo) => process.env.QUIRE_MOJO_TRACE === '1' && !testInfo.tags.includes('@serial');

/** Starts the browser's Mojo trace; none with QUIRE_NO_STALL_ARM. */
export function startMojoTrace(browser) {
  if (armingOff() || mojoTraces.has(browser)) return;
  const trace = { session: null, received: [], ready: null, error: null, taken: null, startedUs: null };
  mojoTraces.set(browser, trace);
  trace.ready = (async () => {
    trace.session = await browser.newBrowserCDPSession();
    trace.session.on('Tracing.dataCollected', (event) => { for (const each of event.value) trace.received.push(keepTraceEvent(each)); });
    trace.startedUs = traceNow();
    await trace.session.send('Tracing.start', { transferMode: 'ReportEvents', traceConfig: {
      recordMode: 'recordContinuously',
      traceBufferSizeInKb: TRACE_BUFFER_KB,
      includedCategories: TRACE_CATEGORIES,
      excludedCategories: ['*'],
    } });
  })().catch((error) => { trace.error = String(error && error.message || error).slice(0, 300); });
}

/** The trace of a browser, if its watch started one (for the tests of this file). */
export function mojoTraceOf(browser) {
  return mojoTraces.get(browser);
}

/** Each renderer's 10 s before its own last message, the other processes' from the earliest of those to the capture; at most `most` newest of each. */
export function mojoWindow(received, startedUs, capturedUs, windowUs = TRACE_WINDOW_US, most = TRACE_PROCESS_MOST) {
  const processes = {};
  for (const each of received) if (each.processName !== undefined) processes[each.pid] = each.processName;
  const timed = received.filter((each) => each.ph !== 'M' && each.cat !== '__metadata');
  if (!timed.length) return { processes, received: received.length, note: 'no Mojo message was traced' };
  const lastOf = new Map();
  for (const each of timed) lastOf.set(each.pid, Math.max(lastOf.get(each.pid) || 0, each.ts));
  const rendererPids = [...lastOf.keys()].filter((pid) => processes[pid] === 'Renderer');
  const newestUs = [...lastOf.values()].reduce((latest, ts) => Math.max(latest, ts), 0);
  const othersFromUs = (rendererPids.length ? rendererPids.map((pid) => lastOf.get(pid)).reduce((least, ts) => Math.min(least, ts), Infinity) : newestUs) - windowUs;
  const oldestUs = timed.reduce((least, each) => Math.min(least, each.ts), Infinity);
  const perProcess = [];
  const events = [];
  for (const [pid, lastUs] of lastOf) {
    const fromUs = rendererPids.includes(pid) ? lastUs - windowUs : othersFromUs;
    const inWindow = timed.filter((each) => each.pid === pid && each.ts >= fromUs).sort((a, b) => a.ts - b.ts);
    const kept = inWindow.slice(-most);
    events.push(...kept);
    perProcess.push({
      pid,
      name: processes[pid] || null,
      lastUs,
      silentMs: Math.round((capturedUs - lastUs) / 1000),
      inWindow: inWindow.length,
      kept: kept.length,
      retainedMs: kept.length ? Math.round((kept[kept.length - 1].ts - kept[0].ts) / 1000) : 0,
    });
  }
  const reachedUs = Math.min(othersFromUs, ...rendererPids.map((pid) => lastOf.get(pid) - windowUs));
  return {
    categories: TRACE_CATEGORIES,
    note: `Mojo messages of the browser: each renderer's ${windowUs / 1000000} s before its own last message, the other processes' from the earliest of those to the capture, at most ${most} newest of each (retainedMs is the time kept); ts is the monotonic clock in microseconds, as process.hrtime`,
    processes,
    perProcess,
    ringDropped: startedUs < reachedUs && oldestUs > reachedUs, // the ring dropped messages the windows reach
    received: received.length,
    inWindow: perProcess.reduce((sum, each) => sum + each.inWindow, 0),
    dropped: perProcess.reduce((sum, each) => sum + each.inWindow - each.kept, 0),
    events: events.sort((a, b) => a.ts - b.ts).map(({ processName, ...rest }) => rest),
  };
}

/** Ends the trace and reads its window; what it cannot give is said as `not available`. */
async function endMojoTrace(trace, capturedUs) {
  try {
    await within(trace.ready, COMMAND_MS);
    if (!trace.session || trace.error) return `not available: Tracing did not start: ${trace.error || 'no answer'}`;
    const ended = new Promise((resolve) => trace.session.once('Tracing.tracingComplete', resolve));
    const ending = await within(trace.session.send('Tracing.end'), COMMAND_MS);
    if (!ending.answered) return 'not available: Tracing.end was not answered';
    if (!(await within(ended, TRACE_END_MS)).answered) return `not available: the trace did not end within ${TRACE_END_MS} ms (a stopped renderer does not flush)`;
    return mojoWindow(trace.received, trace.startedUs, capturedUs);
  } catch (error) {
    return `not available: ${String(error && error.message || error).slice(0, 300)}`;
  }
}

/** The browser's Mojo window for a capture: the first capture of a test ends the trace, and later ones read the same window. */
function takeMojoTrace(browser, capturedUs) {
  const trace = browser && mojoTraces.get(browser);
  if (!trace) return Promise.resolve(armingOff() ? `not available: not armed: ${NO_ARM}=${process.env[NO_ARM]} starts no Mojo trace` : 'not available: no Mojo trace was started on this browser (QUIRE_MOJO_TRACE is not 1, or a @serial test, which asserts timings, is not traced)');
  if (!trace.taken) trace.taken = endMojoTrace(trace, capturedUs);
  return trace.taken;
}

/** The watch's end: a trace no capture took is ended and dropped, and the session is let go. */
async function releaseMojoTrace(browser) {
  const trace = mojoTraces.get(browser);
  if (!trace) return;
  mojoTraces.delete(browser);
  if (!trace.taken) trace.taken = endMojoTrace(trace, traceNow());
  await within(trace.taken, MOJO_END_MOST_MS);
  if (trace.session) trace.session.detach().catch(() => {});
}

/**
 * A page's DevTools session, made while the page still answers, with
 * the debugger enabled; `scripts` maps a script id to its URL.
 */
export async function arm(page) {
  const armed = { session: null, scripts: new Map(), error: null, pausing: false, history: armingOff() ? null : keepHistory(page) };
  if (armingOff()) {
    // the capture then says the page was not armed (`armed: false`, this reason)
    armed.error = `not armed: ${NO_ARM}=${process.env[NO_ARM]} (the debugger is never enabled)`;
    await watchTiming(page, armed);
    return armed;
  }
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
  await watchTiming(page, armed);
  return armed;
}

/**
 * What decides a failure on a page that was slow to answer, not frozen (#600),
 * kept while the page is alive, since its pages are closed before a failed
 * test's fixtures end: DevTools' Performance metrics (read around each attempt
 * of a helper, attempt-log.js), the long tasks and long animation frames the
 * page's own PerformanceObserver saw (the page's script keeps them in
 * `__quireStall`, a property nothing enumerates; the probe takes them every
 * 2 s), and the attempts themselves. Nothing here fails: a read that cannot
 * be made is written as "not available: why".
 */
const OBSERVE_LONG_TASKS = `(() => { try {
  if (globalThis.__quireStall) return;
  const kept = [];
  Object.defineProperty(globalThis, '__quireStall', { value: kept });
  const note = (entry) => { if (kept.length >= 200) return;
    const scripts = (entry.scripts || []).slice(0, 3).map((script) => ({ source: String(script.sourceURL || '').slice(-80), invoker: String(script.invoker || '').slice(0, 80), ms: Math.round(script.duration) }));
    kept.push({ type: entry.entryType, at: Math.round(performance.timeOrigin + entry.startTime), ms: Math.round(entry.duration),
      ...(entry.blockingDuration !== undefined ? { blockingMs: Math.round(entry.blockingDuration) } : {}),
      ...(entry.styleAndLayoutStart ? { styleAndLayoutStartMs: Math.round(entry.styleAndLayoutStart - entry.startTime) } : {}),
      ...(scripts.length ? { scripts } : {}) }); };
  for (const type of ['longtask', 'long-animation-frame']) {
    try { new PerformanceObserver((list) => list.getEntries().forEach(note)).observe({ type, buffered: true }); } catch (unsupported) { /* this browser lacks the type */ }
  }
} catch (failure) { /* the page goes on without it */ } })()`;

async function watchTiming(page, armed) {
  const timing = { entries: [], longTasks: [], notes: [], unavailable: null };
  armed.timing = timing;
  const session = armed.session;
  timing.push = (entry) => { timing.entries.push(entry); if (timing.entries.length > ATTEMPTS_MOST) timing.entries.shift(); };
  // A page that did not answer a read just now will not answer the next one
  // (#715): waiting METRICS_MS before and after every attempt, and HARVEST_MS
  // after a failed one, came out of toLibrary's tries and clickControl's 20 s
  // for a frozen page. The first read that times out pays METRICS_MS; the reads
  // in the DEAF_MS after it are not made and say so. Any read that is answered
  // ends it.
  let deafSince = 0;
  const deaf = () => deafSince !== 0 && Date.now() - deafSince < DEAF_MS;
  // the same for the harvest (an evaluate in the page), which a page can refuse while it answers getMetrics
  let harvestDeafSince = 0;
  const harvestDeaf = () => harvestDeafSince !== 0 && Date.now() - harvestDeafSince < DEAF_MS;
  // the probe had an answer from the page: it is not deaf to either read
  timing.heardFrom = () => { deafSince = 0; harvestDeafSince = 0; };
  timing.metrics = async () => {
    if (!session || armed.error) return { unavailable: armed.error || 'the page was not armed' };
    if (deaf()) return { unavailable: `Performance.getMetrics not asked: the page did not answer one less than ${DEAF_MS} ms ago` };
    const read = await within(session.send('Performance.getMetrics'), METRICS_MS);
    deafSince = read.answered ? 0 : Date.now();
    if (!read.answered) return { unavailable: `Performance.getMetrics was not answered within ${METRICS_MS} ms: the page's main thread was busy` };
    if (read.error || !read.value) return { unavailable: read.error || 'no metrics' };
    return Object.fromEntries(read.value.metrics.map((metric) => [metric.name, metric.value]));
  };
  // the long tasks seen since the last harvest: the page keeps them, this takes them
  // `answering`: the probe has just had an answer from the page, whatever the last read did
  timing.harvest = async (answering = false) => {
    if (page.isClosed() || (!answering && harvestDeaf())) return;
    const read = await within(page.evaluate(() => { const kept = globalThis.__quireStall; return kept ? kept.splice(0) : []; }), HARVEST_MS);
    harvestDeafSince = read.answered ? 0 : Date.now();
    if (Array.isArray(read.value)) {
      timing.longTasks.push(...read.value);
      if (timing.longTasks.length > LONG_TASKS_MOST) timing.longTasks.splice(0, timing.longTasks.length - LONG_TASKS_MOST);
    }
  };
  timing.snapshot = () => ({
    note: 'long tasks are the page\'s PerformanceObserver entries (longtask: a task over 50 ms; long-animation-frame: a frame over 50 ms, with its blocking time and where style and layout began), `at` in epoch ms, the same clock as an attempt\'s startedAt; devtools is Performance.getMetrics between the attempt\'s start and end',
    notAvailable: timing.unavailable,
    attempts: timing.entries,
    longTasks: timing.longTasks,
  });
  bindAttempts(page, timing);
  if (!session || armed.error) { timing.unavailable = `not available: ${armed.error || 'the page was not armed'}`; return; }
  try {
    const enabled = await within(session.send('Performance.enable'), COMMAND_MS);
    if (!enabled.answered || enabled.error) timing.unavailable = `not available: Performance.enable ${enabled.error || 'was not answered'}`;
    // for the pages made later by a navigation, and the one already there
    await within(session.send('Page.addScriptToEvaluateOnNewDocument', { source: OBSERVE_LONG_TASKS }), COMMAND_MS);
    await within(session.send('Runtime.evaluate', { expression: OBSERVE_LONG_TASKS }), COMMAND_MS);
  } catch (error) {
    timing.unavailable = `not available: ${String(error && error.message || error)}`;
  }
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

/**
 * What each thread of a process is doing, from /proc (Linux): its name,
 * state (R running, S sleeping, D waiting on the disk) and the kernel
 * function it waits in, counted. A renderer that answers nothing and uses
 * no CPU is waiting for something outside script (#575): this says what.
 */
function threadStates(pid) {
  try {
    const counts = new Map();
    for (const thread of readdirSync(`/proc/${pid}/task`)) {
      const read = (file) => { try { return readFileSync(`/proc/${pid}/task/${thread}/${file}`, 'utf8').trim(); } catch (error) { return '?'; } };
      const stat = read('stat');
      const state = stat.slice(stat.lastIndexOf(')') + 2, stat.lastIndexOf(')') + 3);
      const key = `${read('comm')} ${state} ${read('wchan')}`;
      counts.set(key, (counts.get(key) || 0) + 1);
    }
    return [...counts].map(([thread, count]) => `${count} x ${thread}`);
  } catch (error) {
    return [String(error && error.message || error)];
  }
}

/**
 * What a process's main thread is blocked in (#591): the system call it
 * sleeps in and its arguments (`syscall`: for a futex, the address it
 * waits on, so two processes' threads waiting on one another can be told
 * from a thread waiting for nothing) and, where the kernel lets this user
 * read it, its kernel stack. Every thread of the process whose state is
 * not S or R, or every one that waits in a futex or a poll, is not listed:
 * only the main thread, which is the one a page's script runs on.
 */
function mainThreadWait(pid) {
  const read = (file) => { try { return readFileSync(`/proc/${pid}/${file}`, 'utf8').trim(); } catch (error) { return `(${error.code || error.message})`; } };
  return { syscall: read('syscall'), kernelStack: read('stack') };
}

/**
 * The open files of a process that are sockets or pipes, counted by kind
 * (a renderer that waits on a browser process waits on one of its mojo
 * pipes, a unix socket): with the threads' states, whether the process
 * waits on another one.
 */
function openChannels(pid) {
  try {
    const counts = new Map();
    for (const fd of readdirSync(`/proc/${pid}/fd`)) {
      let target = '?';
      try { target = readlinkSync(`/proc/${pid}/fd/${fd}`); } catch (error) { target = '?'; }
      const kind = target.startsWith('socket:') ? 'socket' : target.startsWith('pipe:') ? 'pipe' : target.startsWith('/') ? 'file' : target.replace(/[:\[].*/, '') || 'other';
      counts.set(kind, (counts.get(kind) || 0) + 1);
    }
    return [...counts].map(([kind, count]) => `${count} x ${kind}`);
  } catch (error) {
    return [String(error && error.message || error)];
  }
}

/** The machine's load, pressure and free memory when a page stalls: a starved machine is not the page's fault. */
function machineState() {
  const text = (file) => { try { return readFileSync(file, 'utf8'); } catch (error) { return ''; } };
  const free = /MemAvailable:\s+(\d+) kB/.exec(text('/proc/meminfo'));
  // pressure stall information (cpu, io, memory): the share of the last 10 s that tasks waited for the resource
  const pressure = {};
  for (const resource of ['cpu', 'io', 'memory']) pressure[resource] = text(`/proc/pressure/${resource}`).trim().split('\n');
  return { loadAverage: text('/proc/loadavg').trim(), memoryAvailableMiB: free ? Math.round(+free[1] / 1024) : null, pressure };
}

// Kernel evidence: read-only, bounded, and a failure is written as `unavailable: <why>`.
export const CGROUP_FILES = ['memory.events', 'memory.current', 'memory.max', 'cpu.stat', 'cgroup.freeze'];
export const KERNEL_LOG_PATTERN = /oom|killed process|out of memory|hung task|blocked for more than/i;
export const KERNEL_LOG_LINES = 200;
export const READ_MOST = 16384;

/** A file's text, at most READ_MOST bytes of it, trimmed. Throws as a read does. */
function readBounded(file) {
  const descriptor = openSync(file, 'r');
  try {
    const buffer = Buffer.alloc(READ_MOST);
    const bytes = readSync(descriptor, buffer, 0, READ_MOST, 0);
    return buffer.subarray(0, bytes).toString('utf8').trim();
  } finally {
    closeSync(descriptor);
  }
}

/**
 * One process's cgroup (v2), as /proc/<pid>/cgroup names it, and the files
 * CGROUP_FILES names in that cgroup's directory. `roots` replaces /proc and
 * /sys/fs/cgroup (the tests' stand-in trees).
 */
export function cgroupEvidence(pid, roots = {}) {
  const procRoot = roots.proc || '/proc';
  const cgroupRoot = roots.cgroup || '/sys/fs/cgroup';
  let text;
  try {
    text = readBounded(join(procRoot, String(pid), 'cgroup'));
  } catch (error) {
    return { pid, unavailable: `unavailable: /proc/${pid}/cgroup: ${error.code || error.message}` };
  }
  const v2 = text.split('\n').find((line) => line.startsWith('0::'));
  if (!v2) return { pid, unavailable: 'unavailable: no cgroup v2 line in /proc/<pid>/cgroup (cgroup v1 only, or none)' };
  const path = v2.slice(3);
  const directory = join(cgroupRoot, path);
  const files = {};
  for (const name of CGROUP_FILES) {
    try {
      files[name] = readBounded(join(directory, name));
    } catch (error) {
      files[name] = `unavailable: ${error.code || error.message}`;
    }
  }
  return { pid, path, directory, files };
}

/**
 * The last KERNEL_LOG_LINES lines of the kernel's log that match
 * KERNEL_LOG_PATTERN (`dmesg`, as root or through sudo, as the gdb path
 * runs its commands): { lines, matched } or { unavailable }.
 */
export async function kernelLog(scope) {
  const path = whichExecutable('dmesg');
  if (!path) return { unavailable: 'unavailable: dmesg is not installed' };
  const out = await runPrivileged([path], HELPER_MS, undefined, scope);
  if (!out.ok) return { unavailable: `unavailable: ${(cap((out.stderr || '').trim(), 200) || out.error || 'dmesg gave no output').replace(/\s+/g, ' ')}` };
  const matched = out.stdout.split('\n').filter((line) => KERNEL_LOG_PATTERN.test(line));
  return { lines: matched.slice(-KERNEL_LOG_LINES), matched: matched.length };
}

/** The cgroups of these processes and the kernel's log, never throws. */
export async function kernelEvidence(pids, scope = nativeScope(), roots = {}) {
  return { cgroups: pids.map((pid) => cgroupEvidence(pid, roots)), kernelLog: await kernelLog(scope) };
}

/** Each renderer process's CPU time (s) over `ms`, from the browser's own session. */
async function rendererCpu(browser, ms) {
  let session;
  try {
    session = (await within(browser.newBrowserCDPSession(), COMMAND_MS)).value;
    if (!session) return { error: 'no browser session' };
    const read = async () => {
      const result = await within(session.send('SystemInfo.getProcessInfo'), COMMAND_MS);
      // every process of the browser, not only the renderers (#591): a
      // renderer that waits on the browser process or the GPU process is
      // told from one that waits for nothing by what those are doing
      return result.value ? result.value.processInfo : null;
    };
    const before = await read();
    await delay(ms);
    const after = await read();
    if (!before || !after) return { error: 'SystemInfo.getProcessInfo did not answer' };
    return after.map((process) => {
      const earlier = before.find((other) => other.id === process.id);
      return { pid: process.id, type: process.type, cpuSeconds: earlier ? +(process.cpuTime - earlier.cpuTime).toFixed(3) : null, overSeconds: ms / 1000 };
    });
  } catch (error) {
    return { error: String(error && error.message || error) };
  } finally {
    if (session) session.detach().catch(() => {});
  }
}

/**
 * An external command, run to its end or to `ms`, whichever is first, and
 * never rejected: { ok, code, stdout, stderr, ms, timedOut, error }. It runs
 * in a process group of its own, which is killed (SIGKILL) at `ms`, so no
 * capture waits on one for ever. A command that needs root and so runs
 * through sudo is also wrapped, inside sudo, in `timeout -s KILL` (see
 * `privileged`), because a SIGKILL of sudo reaches no process of root's:
 * `timeout` is the one that ends the command, `ms` being the later backstop.
 */
function run(command, args, ms, env, scope) {
  return new Promise((resolve) => {
    const started = Date.now();
    const done = (outcome) => resolve({ stdout: '', stderr: '', timedOut: false, ...outcome, ms: Date.now() - started });
    let child;
    if (scope && scope.aborted) return done({ ok: false, code: 'aborted', error: 'not started: the watch was stopped' });
    try {
      child = execFile(command, args, { timeout: ms, killSignal: 'SIGKILL', maxBuffer: 16 * 1024 * 1024, env: { ...process.env, ...env }, encoding: 'utf8', detached: true },
        (error, stdout, stderr) => {
          // whatever is left in the group (a grandchild that kept running) goes too
          if (scope && child) scope.children.delete(child);
          try { if (child && child.pid) process.kill(-child.pid, 'SIGKILL'); } catch (gone) { /* no such group: nothing left */ }
          done({
            ok: !error,
            code: error ? (typeof error.code === 'number' ? error.code : String(error.code || error.signal || 'error')) : 0,
            stdout: stdout || '',
            stderr: stderr || '',
            timedOut: !!(error && error.killed),
            error: error ? String(error.message || error).slice(0, 300) : undefined,
          });
        });
      if (scope) scope.children.add(child);
    } catch (error) {
      done({ ok: false, code: 'error', error: String(error && error.message || error).slice(0, 300) });
    }
  });
}

const isRoot = typeof process.getuid === 'function' && process.getuid() === 0;
/**
 * A command that needs root, ended by `timeout -s KILL <seconds>` as root (so
 * the real command is killed even if sudo is not), through sudo without a
 * password prompt where this user is not root (the runners allow it).
 */
function privileged(args, ms) {
  // KILL, not TERM then KILL: a gdb that is ended with TERM or INT leaves the process it is attached to
  // stopped for good (measured by the review), and a killed gdb is detached from it by the kernel
  const limited = ['timeout', '-s', 'KILL', String(Math.max(1, Math.floor(ms / 1000) - 2)), ...args];
  return isRoot ? limited : ['sudo', '-n', ...limited];
}
const runPrivileged = (args, ms, env, scope) => { const full = privileged(args, ms); return run(full[0], full.slice(1), ms, env, scope); };

/**
 * What a watch has running outside node: its commands' children, and whether
 * it was stopped (then none starts). `abort` ends them, SIGTERM to each
 * process group (sudo relays it to `timeout`, which ends gdb; as root the group
 * is killed outright) and SIGKILL a second later, so a gdb that is attached to a
 * renderer lets go and the renderer runs again.
 */
export function nativeScope() {
  const token = `QUIRE_STALL_${Math.random().toString(36).slice(2, 10)}`;
  return {
    aborted: false,
    token,
    children: new Set(),
    attached: new Set(),   // the pids gdb is attached to now
    /**
     * Ends what this watch runs: SIGKILL to each child's process group (all a root user can
     * reach; sudo's group is root's, out of reach of one that is not) and `pkill -KILL -f` of the
     * token that gdb's command line carries, as root through sudo, so `timeout` and gdb are
     * killed whoever started them (KILL: gdb ended by TERM or INT leaves its process stopped),
     * and then SIGCONT to every pid gdb was attached to, which a gdb ended in the middle of a call
     * into the process can still leave stopped. Without any of it gdb still ends by `timeout -s
     * KILL`, about 30 s after it started. A gdb ended during a call into the renderer can leave
     * it broken, not only stopped: that is a renderer that was frozen.
     */
    async abort() {
      this.aborted = true;
      const groups = [...this.children].map((child) => child.pid).filter(Boolean);
      for (const group of groups) { try { process.kill(-group, 'SIGKILL'); } catch (gone) { /* it ended, or it is root's */ } }
      // the pattern matches the token in gdb's command line and not pkill's own
      const pattern = `[${token[0]}]${token.slice(1)}`;
      await runPrivileged(['pkill', '-KILL', '-f', pattern], HELPER_MS);
      await Promise.all([...this.attached].map((pid) => resume(pid)));
      return groups.length;
    },
  };
}

/** SIGCONT, as root through sudo where this user cannot: a renderer a gdb let go of stopped runs again. */
async function resume(pid) {
  try { process.kill(pid, 'SIGCONT'); return true; } catch (error) { /* not ours to signal: root's? try sudo */ }
  const out = await runPrivileged(['kill', '-CONT', String(pid)], HELPER_MS);
  return out.ok;
}

const cap = (text, most) => (text.length > most ? `${text.slice(0, most)}\n... (${text.length - most} more characters cut)` : text);

// A path to gdb, instead of the one PATH finds (the specs' stand-in). An
// absolute path, not a PATH entry: the privileged command runs under sudo,
// whose own PATH (secure_path) is not this process's
const GDB_PATH_VARIABLE = 'QUIRE_STALL_GDB';

/** The absolute path of an executable on this process's PATH, or null. */
export function whichExecutable(name) {
  if (isAbsolute(name)) { try { accessSync(name, constants.X_OK); return name; } catch (missing) { return null; } }
  for (const directory of (process.env.PATH || '').split(delimiter)) {
    if (!directory) continue;
    try { accessSync(join(directory, name), constants.X_OK); return join(directory, name); } catch (missing) { /* not in this directory */ }
  }
  return null;
}

/**
 * gdb, if the machine has it, as an absolute path (the same one the
 * privileged command then runs). Nothing is installed here (a capture that
 * installs packages in the middle of a test run is a supply chain
 * decision): the e2e jobs install it in a visible step of check.yml
 * (a stopgap, bats-lang/pwa#109). Looked for when a page is frozen, so a
 * healthy job runs nothing.
 */
async function findGdb(scope) {
  const path = whichExecutable(process.env[GDB_PATH_VARIABLE] || 'gdb');
  if (!path) return { available: false, version: null, path: null, error: 'gdb is not installed' };
  const version = await run(path, ['--version'], HELPER_MS, undefined, scope);
  return { available: version.ok, version: version.ok ? version.stdout.split('\n')[0] : null, path, error: version.ok ? undefined : (version.error || 'gdb does not answer --version') };
}

// What a machine that cannot take the stacks says: gdb's own words when the kernel refuses to
// let it attach (Yama's ptrace_scope or a missing privilege), or sudo's when it wants a password
// or a terminal. The capture then says `unavailable` and goes on without them
export const CANNOT_ATTACH = /ptrace: (Operation not permitted|Permission denied)|Could not attach to process|yama\/ptrace_scope|sudo: (a password is required|a terminal is required|sorry, you are not allowed)|spawn sudo ENOENT|sudo: (command )?not found/;

// The tools that give a process's user-space stacks when gdb does not (not installed, or not
// allowed to attach), tried in this order and the first that answers is kept. eu-stack is
// elfutils' (Ubuntu's `elfutils`; `-m` names the module of each frame), pstack is the old
// script (`pstack` of Red Hat's, absent on Ubuntu)
// eu-stack prints "#0  0x...", pstack "0x...: ????"
const FRAME_LINE = /^(#0\s|0x[0-9a-f]+: )/m;
const FALLBACK_TOOLS = [
  { tool: 'eu-stack', args: (pid) => ['-p', String(pid), '-m', '-n', String(STACK_FRAMES)] },
  { tool: 'pstack', args: (pid) => [String(pid)] },
];

/**
 * The stacks of one process by the fallback tools: { ok, tried }, `tried` the
 * tools in order, each { tool, available, ... } and, for one that gave none,
 * `note: 'not available: <why>'`. Never throws.
 */
async function fallbackStacks(pid, scope) {
  const tried = [];
  for (const { tool, args } of FALLBACK_TOOLS) {
    const path = whichExecutable(tool);
    if (!path) { tried.push({ tool, available: false, note: `not available: ${tool} is not installed` }); continue; }
    const out = await runPrivileged([path, ...args(pid)], FALLBACK_MS, undefined, scope);
    // the frames decide, whatever the exit code (eu-stack exits 1 after printing some)
    const ok = FRAME_LINE.test(out.stdout);
    const why = (cap(out.stderr.trim(), 200) || out.error || 'it printed no frames').replace(/\s+/g, ' ');
    tried.push({ tool, available: true, path, ok, exitCode: out.code, ms: out.ms, stderr: cap(out.stderr, 2000), text: cap(out.stdout, 100000), note: ok ? undefined : `not available: ${tool} gave no stacks: ${why}` });
    if (ok) break;
  }
  return { ok: tried.some((each) => each.ok), tried };
}

const ANONYMOUS_CODE = '(anonymous executable memory)';

/** What the maps of a process say about where its code is: see `identity`. */
function parseMaps(text, exe) {
  const modules = new Map();     // path -> the lowest address of its first mapping
  const regions = [];            // every mapping, to say which one an address is in
  const exeMaps = [];
  const anonymousCode = [];      // executable memory with no file: JIT code (V8's), the vdso
  for (const line of text.split('\n')) {
    const found = /^([0-9a-f]+)-([0-9a-f]+) (\S+) ([0-9a-f]+) \S+ \d+\s*(.*)$/.exec(line);
    if (!found) continue;
    const [, start, end, perms, offset, name] = found;
    const path = name.replace(/ \(deleted\)$/, '');
    regions.push({ start: BigInt(`0x${start}`), end: BigInt(`0x${end}`), perms, path: path.startsWith('/') ? path : (perms.includes('x') ? ANONYMOUS_CODE : null) });
    if (path === exe) exeMaps.push(line.replace(/\s+/g, ' '));
    if (path.startsWith('/')) {
      if (!modules.has(path) || (BigInt(`0x${offset}`) === 0n && BigInt(`0x${start}`) < BigInt(`0x${modules.get(path)}`))) modules.set(path, start);
    } else if (perms.includes('x')) {
      anonymousCode.push(`${start}-${end} ${perms} ${name}`.trim());
    }
  }
  const info = { exeBase: modules.get(exe) || null, exeMaps, modules: [...modules].map(([path, base]) => ({ path, base })), anonymousCode: anonymousCode.slice(0, 64) };
  return { info, regions, bases: modules };
}

/**
 * What resolves a raw address of the process's stacks offline: the
 * binary's path, its GNU build id (readelf -n; the same download then
 * gives the symbols), the address it is loaded at and every other
 * module's, so address - exeBase is the offset in the binary. Kept apart
 * from gdb's text because the maps change when the process runs again.
 */
async function identity(pid, scope) {
  const result = { pid };
  let exe = null;
  try { exe = readlinkSync(`/proc/${pid}/exe`).replace(/ \(deleted\)$/, ''); } catch (error) { result.exeError = String(error.code || error.message); }
  result.exe = exe;
  let maps = null;
  try {
    maps = parseMaps(readFileSync(`/proc/${pid}/maps`, 'utf8'), exe);
    Object.assign(result, maps.info);
  } catch (error) { result.mapsError = String(error.code || error.message); }
  if (exe) {
    const notes = await run('readelf', ['-n', exe], HELPER_MS, undefined, scope);
    const id = /Build ID:\s*([0-9a-f]+)/.exec(notes.stdout);
    result.buildId = id ? id[1] : null;
    if (!id) result.buildIdError = notes.error || cap(notes.stderr || notes.stdout, 300) || 'no build id note';
    // what the browser binary is, so a core or an address can be matched to symbols later
    const sections = await run('readelf', ['-S', '-W', exe], HELPER_MS, undefined, scope);
    const version = await run(exe, ['--version'], HELPER_MS, undefined, scope);
    let size = null;
    try { size = statSync(exe).size; } catch (gone) { /* the binary was replaced */ }
    result.binary = {
      version: version.ok ? version.stdout.split('\n')[0].trim() : null,
      bytes: size,
      hasSymtab: /\s\.symtab\s/.test(sections.stdout),     // function names, if not stripped
      hasDebugLink: /\s\.gnu_debuglink\s/.test(sections.stdout), // names a separate debug file, which no public source of this browser holds
      hasDebugInfo: /\s\.debug_info\s/.test(sections.stdout),
    };
  }
  if (maps) {
    // the system libraries a stack runs through (libc, the loader, libstdc++): their build ids and
    // the libc package, which name the separate debug files that symbolise them (Debian and
    // Ubuntu's debuginfod, libc6-dbg) later, when this machine is gone
    const wanted = maps.info.modules.filter((module) => /\/(libc|ld-linux[^/]*|libpthread|libstdc\+\+|libm)\.so/.test(module.path)).slice(0, 6);
    result.libraries = await Promise.all(wanted.map(async (module) => {
      const notes = await run('readelf', ['-n', module.path], HELPER_MS, undefined, scope);
      const id = /Build ID:\s*([0-9a-f]+)/.exec(notes.stdout);
      return { path: module.path, base: module.base, buildId: id ? id[1] : null };
    }));
    const release = (() => { try { return /^PRETTY_NAME="?([^"\n]*)/m.exec(readFileSync('/etc/os-release', 'utf8'))[1]; } catch (error) { return null; } })();
    const libc = await run('dpkg-query', ['-W', '-f', '${Version}', 'libc6'], HELPER_MS, undefined, scope);
    const libcDebug = await run('dpkg-query', ['-W', '-f', '${Version}', 'libc6-dbg'], HELPER_MS, undefined, scope);
    result.system = { os: release, libc6: libc.ok ? libc.stdout : null, libc6Dbg: libcDebug.ok ? libcDebug.stdout : null };
  }
  return { result, maps };
}

/**
 * The kernel's view of every thread: its name, state, wait channel,
 * system call (a futex's address and operation) and stack. The stack is
 * readable by root only, so it is read through sudo when this user cannot.
 */
async function kernelTasks(pid, scope) {
  let tids = [];
  try { tids = readdirSync(`/proc/${pid}/task`); } catch (error) { return { error: String(error.code || error.message) }; }
  const read = (tid, file) => { try { return readFileSync(`/proc/${pid}/task/${tid}/${file}`, 'utf8').trim(); } catch (error) { return `(${error.code || error.message})`; } };
  const tasks = tids.map((tid) => {
    const stat = read(tid, 'stat');
    return { tid: +tid, comm: read(tid, 'comm'), state: stat.slice(stat.lastIndexOf(')') + 2, stat.lastIndexOf(')') + 3), wchan: read(tid, 'wchan'), syscall: read(tid, 'syscall'), kernelStack: read(tid, 'stack') };
  });
  const denied = tasks.filter((task) => /^\((EACCES|EPERM)\b/.test(task.kernelStack));
  if (denied.length) {
    // one sudo for all of them: `tail -v` heads each file with its name
    const files = denied.map((task) => `/proc/${pid}/task/${task.tid}/stack`);
    const out = await runPrivileged(['tail', '-v', '-n', '+1', ...files], HELPER_MS, undefined, scope);
    for (const block of out.stdout.split(/^==> /m).slice(1)) {
      const head = /^\/proc\/\d+\/task\/(\d+)\/stack <==\n([\s\S]*)$/.exec(block);
      const task = head && denied.find((each) => each.tid === +head[1]);
      if (task) task.kernelStack = head[2].trim();
    }
    for (const task of denied) if (/^\(E/.test(task.kernelStack)) task.kernelStackError = out.error || cap(out.stderr, 200) || 'not read';
  }
  return { tasks };
}

/**
 * gdb's text, taken apart: `Thread 3 (Thread 0x7f.. (LWP 123) "name"):`
 * heads the frames below it. The thread whose LWP is the process id is
 * the main thread, the one a page's script runs on.
 */
function parseGdb(text, pid, maps) {
  const threads = [];
  let current = null;
  for (const line of text.split('\n')) {
    const head = /^Thread (\d+) \((.*)\):\s*$/.exec(line);
    if (head) {
      const lwp = /LWP (\d+)/.exec(head[2]);
      const name = /"([^"]*)"/.exec(head[2]);
      current = { number: +head[1], lwp: lwp ? +lwp[1] : null, name: name ? name[1] : null, frames: [] };
      threads.push(current);
    } else if (current && /^#\d+ /.test(line)) {
      current.frames.push(frameLocated(line.trim(), maps));
    }
  }
  const main = threads.find((thread) => thread.lwp === pid) || null;
  return { threads, mainThread: main };
}

/**
 * A frame of gdb's text with where its address is: the module whose
 * mapping holds it (a path, or the anonymous executable memory JIT code
 * lives in) and, for a module, the offset in it from its first mapping,
 * which is what an offline symbol lookup (addr2line, a symbol server)
 * takes for a stripped binary.
 */
function frameLocated(text, maps) {
  const found = /^#\d+\s+(0x[0-9a-f]+)/.exec(text);
  const frame = { text };
  if (!found) return frame;
  frame.pc = found[1];
  if (!maps) return frame;
  const pc = BigInt(found[1]);
  const region = maps.regions.find((each) => pc >= each.start && pc < each.end);
  frame.module = region ? region.path : null;
  if (region && region.path && region.path !== ANONYMOUS_CODE && maps.bases.has(region.path)) {
    frame.offset = `0x${(pc - BigInt(`0x${maps.bases.get(region.path)}`)).toString(16)}`;
  }
  return frame;
}

/**
 * The mappings that hold nothing (no resident page) and are large, from the
 * process's smaps: a Chromium renderer reserves over a terabyte of address space
 * (PROT_NONE cages of V8 and PartitionAlloc, 1.4 TB here, 64 MB resident), and
 * gdb's core writer reads every page of what it is not told to leave out: 52 s of
 * system time and no core in 60 s, measured. Marked MADV_DONTDUMP in the stopped
 * process (`madvise(..., 16)` called by gdb, after the backtraces), they are left out,
 * and the core takes 2 s and is the resident memory.
 */
function quietRanges(pid) {
  const ranges = [];
  let current = null;
  let text = '';
  try { text = readFileSync(`/proc/${pid}/smaps`, 'utf8'); } catch (error) { return ranges; }
  for (const line of text.split('\n')) {
    const header = /^([0-9a-f]+)-([0-9a-f]+) \S+ /.exec(line);
    if (header) {
      current = { start: BigInt(`0x${header[1]}`), end: BigInt(`0x${header[2]}`) };
    } else if (current && line.startsWith('Rss:')) {
      if (/^Rss:\s+0 kB/.test(line) && current.end - current.start >= BigInt(CORE_QUIET_MIN_BYTES)) ranges.push(current);
      current = null;
    }
  }
  return ranges.slice(0, CORE_QUIET_MOST);
}

/** gdb attached to one process, to its end or GDB_MS, then let go. */
async function backtrace(pid, maps, scope, gdbPath, corePath) {
  // The core is asked only where `prlimit` can bound the file gdb writes (CORE_MAX_BYTES):
  // when the empty reservations cannot be left out (a call in the process fails: a process
  // that is in a group stop, SIGSTOPped, cannot run one) the dump is the whole address space,
  // 5 GB measured, and the limit ends gdb at the cap
  const prlimit = corePath ? whichExecutable('prlimit') : null;
  const core = prlimit ? corePath : null;
  const args = [gdbPath, '-batch', '-nx', '-q',
    '-iex', 'set auto-load off', '-iex', 'set debuginfod enabled off', '-iex', 'set pagination off', '-iex', 'set confirm off',
    // an address on every frame: gdb leaves it out of a frame whose pc is the start of a source line, and the
    // frame's module and offset (and the core's comparison with it) come from the address
    '-iex', 'set print frame-info location-and-address',
    // the watch's token on the command line, so teardown can find this command by it (`abort`)
    ...(scope ? ['-iex', `echo ${scope.token}\\n`] : []),
    '-ex', 'info threads', '-ex', `thread apply all bt ${STACK_FRAMES}`,
    // after the backtraces, in the same attach (what is stopped is stopped once): the empty
    // reservations are left out of the dump, then the core is written
    // only this thread runs during a call, so the other threads' state is the stack's (the core is still
    // written after the stacks, not at the same instant)
    ...(core ? ['-ex', 'set scheduler-locking on'] : []),
    ...(core ? quietRanges(pid).flatMap((range) => ['-ex', `call (int)madvise(${range.start}UL, ${range.end - range.start}UL, 16)`]) : []),
    ...(core ? ['-ex', `generate-core-file ${core}`] : []),
    '-p', String(pid)];
  if (scope) scope.attached.add(pid);
  const out = await runPrivileged(core ? [prlimit, `--fsize=${CORE_MAX_BYTES}`, '--', ...args] : args, GDB_MS, { DEBUGINFOD_URLS: '' }, scope);
  if (scope) scope.attached.delete(pid);
  // a gdb that did not finish (the limit, the size cap, an abort) can leave the renderer stopped: let it run
  if (!out.ok) await resume(pid);
  const parsed = parseGdb(out.stdout, pid, maps);
  const timedOut = out.timedOut || out.code === 124 || out.code === 137;
  // the backtraces come first: a gdb that ended while it wrote the core (the time limit, the size
  // limit) still gave the stacks, and the core's failure is the core's (`keepCore` says it), never the stacks'
  const stacksBeforeEnd = !!(core && !out.ok && parsed.mainThread && parsed.mainThread.frames.length > 0);
  return {
    ok: out.ok || stacksBeforeEnd,
    coreEndedEarly: stacksBeforeEnd,
    coreSaved: !!core && out.stdout.includes('Saved corefile'),
    // a call into the process that could not run (a process in a group stop cannot run one): the reservations stay in the dump
    coreCallsFailed: (out.stderr.match(/Evaluation of the expression containing the function/g) || []).length,
    coreAsked: !!core,
    exitCode: out.code,
    timedOut,
    ms: out.ms,
    error: out.error,
    stderr: cap(out.stderr, 4000),
    // the whole text too, in case the parts miss a form of gdb's output
    text: cap(out.stdout, 200000),
    threadCount: parsed.threads.length,
    mainThread: parsed.mainThread,
    threads: parsed.threads,
  };
}

/**
 * The core gdb wrote (or not): gzipped to `<core>.gz` and the raw file removed,
 * or removed when it is over CORE_MAX_BYTES or its gzip over CORE_GZ_MAX_BYTES.
 * Never throws and never fails a test: the answer says what became of it.
 */
async function keepCore(corePath, scope, saved, callsFailed) {
  const gz = `${corePath}.gz`;
  const remove = (path) => { try { unlinkSync(path); } catch (gone) { /* not there */ } };
  try {
    if (!existsSync(corePath)) return { written: false, reason: 'gdb wrote no core (it failed, or was ended first)' };
    if (!saved) { const partial = statSync(corePath).size; remove(corePath); return { written: false, kept: false, bytes: partial, reason: 'gdb did not finish the core (ended by the size or time limit, or failed): a partial core is useless and was removed' }; }
    if (callsFailed) { const partial = statSync(corePath).size; remove(corePath); return { written: true, kept: false, bytes: partial, reason: `${callsFailed} call(s) into the process failed (it is in a group stop, SIGSTOPped, and cannot run one), so the empty reservations could not be left out and the dump is not a core of its memory` }; }
    const bytes = statSync(corePath).size;
    if (bytes > CORE_MAX_BYTES) { remove(corePath); return { written: true, kept: false, bytes, reason: `over the cap of ${CORE_MAX_BYTES} bytes` }; }
    const packed = await run('gzip', ['-1', '-f', corePath], GZIP_MS, undefined, scope);
    remove(corePath);
    if (!packed.ok || !existsSync(gz)) { remove(gz); return { written: true, kept: false, bytes, reason: `gzip failed: ${packed.error || packed.stderr}` }; }
    const gzBytes = statSync(gz).size;
    if (gzBytes > CORE_GZ_MAX_BYTES) { remove(gz); return { written: true, kept: false, bytes, gzBytes, reason: `compressed over the cap of ${CORE_GZ_MAX_BYTES} bytes` }; }
    return { written: true, kept: true, file: gz, bytes, gzBytes, gzipMs: packed.ms };
  } catch (error) {
    remove(corePath);
    return { written: false, kept: false, reason: String(error && error.message || error).slice(0, 300) };
  }
}

/**
 * The native stacks of these renderers (a page judged stalled: see the top
 * of this file). Nothing here throws, and every command is limited.
 */
export async function nativeStacks(renderers, scope, corePathFor, others = []) {
  const result = { ptraceScope: '(absent)' };
  try { result.ptraceScope = readFileSync('/proc/sys/kernel/yama/ptrace_scope', 'utf8').trim(); } catch (error) { /* no Yama: ptrace is the kernel's usual rule */ }
  result.root = isRoot;
  const gdb = await findGdb(scope);
  result.gdb = gdb;
  const taken = renderers.slice(0, NATIVE_MOST);
  const aside = Promise.all(others.slice(0, NATIVE_MOST).map(async (other) => ({ pid: other.pid, type: other.type, cpuSeconds: other.cpuSeconds, kernel: await kernelTasks(other.pid, scope) })));
  result.renderers = await Promise.all(taken.map(async (renderer, index) => {
    // the kernel's view and the addresses first: gdb stops the process
    const { result: entry, maps } = await identity(renderer.pid, scope);
    entry.kernel = await kernelTasks(renderer.pid, scope);
    // A process in a group stop (SIGSTOP, state T) cannot run the calls that leave the empty
    // reservations out of the core, and a call abandoned there leaves it broken: no core of it
    const main = entry.kernel.tasks && entry.kernel.tasks.find((task) => task.tid === renderer.pid);
    const stopped = !!main && main.state === 'T';
    const corePath = corePathFor && index < CORE_MOST && !stopped ? corePathFor(renderer.pid) : null;
    entry.gdbStacks = gdb.available ? await backtrace(renderer.pid, maps, scope, gdb.path, corePath) : { ok: false, error: gdb.error };
    if (corePath && entry.gdbStacks.coreAsked) entry.core = await keepCore(corePath, scope, entry.gdbStacks.coreSaved, entry.gdbStacks.coreCallsFailed);
    else if (corePath) entry.core = { written: false, kept: false, reason: gdb.available ? 'no prlimit to bound the file' : gdb.error };
    else if (stopped && corePathFor) entry.core = { written: false, kept: false, reason: 'the process is in a group stop (SIGSTOP): no call can run in it to leave the empty reservations out, and a core of all of its address space is not possible' };
    // gdb gave no stacks: the next tools may, or the entry says why none could (never a failure)
    if (entry.gdbStacks.ok) {
      entry.userSpaceStacks = 'gdb';
    } else {
      entry.fallbackStacks = await fallbackStacks(renderer.pid, scope);
      const used = entry.fallbackStacks.tried.find((each) => each.ok);
      entry.userSpaceStacks = used ? used.tool : `not available: gdb (${entry.gdbStacks.error || cap((entry.gdbStacks.stderr || '').trim(), 200) || 'no stacks'}); ${entry.fallbackStacks.tried.map((each) => each.note).join('; ')}`;
    }
    return entry;
  }));
  result.browserProcesses = await aside;
  // the browser's and the GPU's stacks, by the fallback tools only (never gdb)
  await Promise.all(result.browserProcesses.filter((other) => /^(browser|gpu)$/i.test(other.type)).map(async (other) => {
    other.fallbackStacks = await fallbackStacks(other.pid, scope);
    const used = other.fallbackStacks.tried.find((each) => each.ok);
    other.userSpaceStacks = used ? used.tool : other.fallbackStacks.tried.map((each) => each.note).join('; ');
  }));
  // no gdb, or none that may attach: the capture carries on without the stacks, and says so
  if (!gdb.available) result.unavailable = `native capture unavailable: ${gdb.error}`;
  else if (result.renderers.length && result.renderers.every((renderer) => !renderer.gdbStacks.ok && CANNOT_ATTACH.test(`${renderer.gdbStacks.stderr}\n${renderer.gdbStacks.text}\n${renderer.gdbStacks.error}`))) {
    result.unavailable = `native capture unavailable: gdb cannot attach (ptrace_scope ${result.ptraceScope}, root ${isRoot}): ${result.renderers[0].gdbStacks.stderr.trim().slice(0, 200)}`;
  }
  return result;
}

/** Where a page's main thread is: see the top of this file. */
export async function capture(page, armed, reason, browser, save = () => {}, scope = nativeScope(), corePathFor = null) {
  armed.capturing = true;
  try { return await captureArmed(page, armed, reason, browser, save, scope, corePathFor); } finally { armed.capturing = false; }
}

async function captureArmed(page, armed, reason, browser, save, scope, corePathFor) {
  const result = { reason, at: new Date().toISOString(), url: page.url(), armed: !armed.error, armError: armed.error };
  result.history = armed.history ? armed.history.snapshot() : 'not available: the page was not watched';
  const capturedUs = traceNow();
  const mojo = takeMojoTrace(browser, capturedUs); // ends alongside the capture, awaited below (#737)
  const session = armed.session;
  const cpu = browser ? rendererCpu(browser, CPU_WINDOW_MS) : Promise.resolve(null);
  // Does the page's main thread run a task? Asked of the armed session; a page
  // that is not armed (no debugger, or it stopped answering before it was
  // armed) is asked with an evaluate of its own, so armed and unarmed pages
  // are judged alike, whatever the reason of the capture
  let answers = false;
  if (session && !armed.error) {
    // An interrupting command (answered while script runs) and a task
    const interrupt = await within(session.send('Debugger.setBreakpointsActive', { active: false }), COMMAND_MS);
    const task = await within(session.send('Runtime.evaluate', { expression: '1' }), COMMAND_MS);
    result.answers = {
      interrupt: { answered: interrupt.answered, ms: interrupt.ms, error: interrupt.error },
      task: { answered: task.answered, ms: task.ms, error: task.error },
    };
    answers = task.answered;
  } else {
    const evaluated = await within(page.evaluate(() => 1), COMMAND_MS);
    result.evaluate = { answered: evaluated.answered, ms: evaluated.ms, error: evaluated.error };
    answers = evaluated.answered;
  }
  let processes = null;
  const kernelOf = (list) => kernelEvidence(Array.isArray(list) ? list.filter((process) => process.type === 'renderer').map((process) => process.pid) : [], scope).catch((error) => ({ error: String(error && error.stack || error) }));
  if (!answers) {
    // No answer, and only then: the renderers that also used (almost) no CPU
    // are frozen, as #575 and #591 were. One that used a second a second is
    // busy (a loop, a heavy layout), still running, and is left alone: gdb
    // stops the process it is attached to. So the native stacks come first,
    // before the pause and the profile below change what a frozen renderer does
    processes = await cpu;
    if (Array.isArray(processes)) {
      // Which renderer is the page's own is not known (no pid for a target in
      // the DevTools protocol or the process info), so the rule is about all of
      // them: if any renderer used CPU, the page that answers nothing is
      // presumed to be that busy one, and nothing is attached; only when every
      // renderer is idle is the page presumed frozen, and the renderers
      // attached to are the idle ones (the other pages' too: collateral, next
      // to a page that is frozen, which is a failing test anyway)
      const renderers = processes.filter((process) => process.type === 'renderer' && process.cpuSeconds !== null);
      const busy = renderers.filter((process) => process.cpuSeconds >= FROZEN_CPU_SECONDS);
      result.frozenBelowCpuSeconds = FROZEN_CPU_SECONDS;
      if (busy.length) {
        result.presumedBusy = `renderer ${busy.map((process) => `${process.pid} used ${process.cpuSeconds} s of CPU`).join(', ')} over ${CPU_WINDOW_MS / 1000} s, so the page is presumed busy, not frozen, and nothing is attached`;
      } else if (renderers.length) {
        // before the stacks, which a teardown can cut off
        result.kernel = await kernelOf(processes);
        save(result);
        result.native = await nativeStacks(renderers, scope, corePathFor, processes.filter((process) => process.type !== 'renderer' && process.cpuSeconds !== null)).catch((error) => ({ error: String(error && error.stack || error) }));
        save(result);
      }
    }
  }
  if (session && !armed.error) {
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
  processes = processes || await cpu;
  if (Array.isArray(processes)) {
    for (const process of processes) {
      process.threads = threadStates(process.pid);
      process.mainThread = mainThreadWait(process.pid);
      process.channels = openChannels(process.pid);
    }
    result.rendererCpu = processes.filter((process) => process.type === 'renderer');
    result.otherProcesses = processes.filter((process) => process.type !== 'renderer');
  } else {
    result.rendererCpu = processes;
  }
  if (!result.kernel) result.kernel = await kernelOf(processes);
  result.machine = machineState();
  // the runner's load over the last minute, and the page's attempts and long
  // tasks (#600): a slow page is told from a slow runner by these
  try { result.runnerLoad = runnerLoad(LOAD_WINDOW_MS); } catch (error) { result.runnerLoad = `not available: ${String(error && error.message || error)}`; }
  if (armed.timing) {
    try { await armed.timing.harvest(); result.pageTiming = armed.timing.snapshot(); } catch (error) { result.pageTiming = `not available: ${String(error && error.message || error)}`; }
  }
  result.mojoMessages = await mojo;
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
    for (const process of result.rendererCpu) {
      if (process.threads) lines.push(`  renderer ${process.pid} threads: ${process.threads.join('; ')}`);
      if (process.mainThread) lines.push(`  renderer ${process.pid} main thread: syscall ${process.mainThread.syscall}; kernel stack ${process.mainThread.kernelStack.replace(/\s+/g, ' ').slice(0, 300)}`);
      if (process.channels) lines.push(`  renderer ${process.pid} open: ${process.channels.join(', ')}`);
    }
  }
  if (result.native) {
    if (result.native.error) lines.push(`  native stacks: ${result.native.error}`);
    else {
      if (result.native.unavailable) lines.push(`  ${result.native.unavailable}`);
      lines.push(`  native stacks: gdb ${result.native.gdb.available ? result.native.gdb.version : 'not available'}, ptrace_scope ${result.native.ptraceScope}`);
      for (const renderer of result.native.renderers) {
        const stacks = renderer.gdbStacks;
        lines.push(`  renderer ${renderer.pid}: ${renderer.exe}, build id ${renderer.buildId}, loaded at ${renderer.exeBase}; gdb ${stacks.ok ? 'ok' : `failed (${stacks.error})`}, ${stacks.threadCount || 0} threads`);
        if (renderer.binary) lines.push(`    binary: ${renderer.binary.version}, ${renderer.binary.bytes} bytes, symbols ${renderer.binary.hasSymtab ? 'in .symtab' : 'none (stripped)'}${renderer.binary.hasDebugLink ? ', .gnu_debuglink' : ''}`);
        if (renderer.core) lines.push(`    core: ${renderer.core.kept ? `kept ${renderer.core.file} (${renderer.core.bytes} bytes, ${renderer.core.gzBytes} gzipped)` : `not kept: ${renderer.core.reason}`}`);
        lines.push(`    user-space stacks: ${renderer.userSpaceStacks}`);
        if (renderer.fallbackStacks) for (const each of renderer.fallbackStacks.tried) if (each.ok) lines.push(...each.text.split('\n').slice(0, 14).map((line) => `    ${each.tool}: ${line}`));
        if (stacks.mainThread) for (const frame of stacks.mainThread.frames.slice(0, 12)) lines.push(`    main thread ${frame.text}${frame.module ? ` [${frame.module}${frame.offset ? ` +${frame.offset}` : ''}]` : ''}`);
      }
    }
  }
  if (result.native && Array.isArray(result.native.browserProcesses)) for (const other of result.native.browserProcesses) {
    const tasks = other.kernel.tasks || [];
    lines.push(`  ${other.type} ${other.pid}: ${tasks.length} threads by the kernel${other.kernel.error ? ` (${other.kernel.error})` : ''}, main thread syscall ${(tasks.find((task) => task.tid === other.pid) || {}).syscall}`);
    if (other.userSpaceStacks) {
      lines.push(`    ${other.type} ${other.pid} user-space stacks: ${other.userSpaceStacks}`);
      if (other.fallbackStacks) for (const each of other.fallbackStacks.tried) if (each.ok) lines.push(...each.text.split('\n').slice(0, 14).map((line) => `    ${each.tool}: ${line}`));
    }
  }
  if (Array.isArray(result.otherProcesses)) for (const process of result.otherProcesses) {
    lines.push(`  ${process.type} ${process.pid}: CPU ${process.cpuSeconds}s over 1 s; threads: ${process.threads.join('; ')}`);
  }
  if (result.kernel && result.kernel.cgroups) {
    for (const each of result.kernel.cgroups) {
      if (each.unavailable) lines.push(`  renderer ${each.pid} cgroup: ${each.unavailable}`);
      else lines.push(`  renderer ${each.pid} cgroup ${each.path}: ${Object.entries(each.files).map(([name, value]) => `${name} ${value.replace(/\s+/g, ' ')}`).join(' | ').slice(0, 400)}`);
    }
  }
  if (result.kernel && result.kernel.kernelLog) {
    const log = result.kernel.kernelLog;
    if (log.unavailable) lines.push(`  kernel log: ${log.unavailable}`);
    else lines.push(`  kernel log: ${log.matched} matching lines${log.lines.length ? `, the last: ${log.lines[log.lines.length - 1].slice(0, 200)}` : ''}`);
  }
  if (result.machine) {
    lines.push(`  machine: load ${result.machine.loadAverage}, ${result.machine.memoryAvailableMiB} MiB available`);
    for (const [resource, rows] of Object.entries(result.machine.pressure)) if (rows[0]) lines.push(`  pressure ${resource}: ${rows.join(' | ')}`);
  }
  if (result.runnerLoad && result.runnerLoad.summary) lines.push(`  runner: ${result.runnerLoad.summary.reading}`);
  const mojo = result.mojoMessages;
  if (mojo) lines.push(`  Mojo messages: ${mojo.events ? `${mojo.events.length} kept of ${mojo.inWindow} in the windows; ${mojo.perProcess.filter((each) => each.name === 'Renderer').map((each) => `renderer ${each.pid} silent ${each.silentMs} ms, ${each.retainedMs} ms kept`).join('; ')}` : mojo}`);
  if (result.history && result.history.inFlight) {
    const history = result.history;
    const flying = history.inFlight.slice(0, 3).map((each) => `${each.method} ${each.url} for ${each.ageMs} ms`).join('; ');
    lines.push(`  page history: ${history.console.length} console, ${history.pageerror.length} errors, ${history.requestfailed.length} failed requests; ${history.inFlight.length} requests in flight${flying ? `: ${flying}` : ''}`);
  }
  if (result.pageTiming && result.pageTiming.attempts) {
    const late = result.pageTiming.attempts.filter((entry) => entry.outcome === 'failed').slice(-3);
    for (const entry of late) lines.push(`  attempt ${entry.step} #${entry.attempt} failed after ${entry.ms} ms: ${entry.why}${entry.devtools && entry.devtools.reading ? ` (${entry.devtools.reading})` : ''}`);
    lines.push(`  ${result.pageTiming.attempts.length} attempts and ${result.pageTiming.longTasks.length} long tasks noted`);
  }
  return lines.join('\n');
}

/**
 * The watch over one test's pages: arms each page as it is made (a
 * context's 'page' event; a context made with browser.newContext, or
 * given to watchContext, is watched at once, any other within 1 s), probes
 * each, captures a page that stops answering (once) and every page when
 * the test is about to time out. `captures` holds what it took;
 * `next(page, ms)` waits for a capture of that page, and
 * `started(page, ms)` for one to begin.
 */
export function stallWatch(browser, testInfo) {
  const armed = new Map();     // page -> its armed session (a promise)
  const ready = new Map();     // page -> its armed session, once armed
  const watchedContexts = new Set();
  const running = new Set();   // captures in progress
  const scope = nativeScope(); // what they run outside node
  const captures = [];
  const starts = [];           // the pages whose capture has begun
  const waiters = [];
  let stopped = false;
  let count = 0;
  const leaveSampler = sampleRunner(testInfo.title); // the runner's load, from now on (#600), kept across the worker's tests (#715)
  if (traceWantedFor(testInfo)) startMojoTrace(browser); // opt-in: QUIRE_MOJO_TRACE=1 and not @serial (#737)

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
    count += 1;
    const path = testInfo.outputPath(`stall-capture-${count}.json`);
    // written when the native stacks are in and again at the end, so what the
    // native step found survives a teardown that does not wait for the rest
    const save = (partial) => { try { writeFileSync(path, JSON.stringify(partial, null, 2)); } catch (error) { /* the output directory is gone: the test is over */ } };
    const result = await capture(page, armedPage, reason, browser, save, scope, (pid) => testInfo.outputPath(`stall-core-${count}-${pid}.core`));
    save(result);
    await testInfo.attach(`stall-capture-${count}`, { path, contentType: 'application/json' }).catch(() => {});
    console.error(summary(result));
    captures.push({ page, result });
    for (const waiter of waiters.splice(0)) waiter();
    return result;
  };
  const start = (page, reason) => {
    starts.push(page);
    for (const waiter of waiters.splice(0)) waiter();
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
      const timing = ready.has(page) && ready.get(page).timing;
      if (timing) { timing.heardFrom(); await timing.harvest(true).catch(() => {}); }
      await delay(PROBE_EVERY_MS);
    }
  }

  // A test that did not end as it should have (failed, timed out) keeps the
  // runner's load over the last minute and each page's attempts, durations and
  // long tasks (#600), whether or not a page was captured: a page that was
  // only slow is not. Never fails the teardown.
  const evidence = async () => {
    const load = (() => { try { return runnerLoad(LOAD_WINDOW_MS); } catch (error) { return `not available: ${String(error && error.message || error)}`; } })();
    const pages = [];
    for (const [page, pending] of armed) {
      const arming = await within(pending, 500);
      const timing = arming.value && arming.value.timing;
      let url = '';
      try { url = page.url(); } catch (gone) { url = ''; }
      pages.push({ url, ...(timing ? timing.snapshot() : { notAvailable: 'not available: the page was still being armed' }) });
    }
    return { runnerLoad: load, pageTiming: pages };
  };
  const keepEvidence = async () => {
    try {
      if (!testInfo.status || testInfo.status === 'skipped' || testInfo.status === testInfo.expectedStatus) return;
      const found = await evidence();
      const attach = async (name, body) => {
        const path = testInfo.outputPath(`${name}.json`);
        writeFileSync(path, JSON.stringify(body, null, 2));
        await testInfo.attach(name, { path, contentType: 'application/json' });
      };
      const load = found.runnerLoad;
      await attach('runner-load', { status: testInfo.status, at: new Date().toISOString(), ...(typeof load === 'string' ? { notAvailable: load } : load) });
      await attach('page-timing', { status: testInfo.status, at: new Date().toISOString(), pages: found.pageTiming });
    } catch (error) {
      console.error(`[stall-capture] the runner's load could not be kept: ${error && error.message || error}`);
    }
  };

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

  // what `found` gives once it gives anything, woken by a capture's start
  // or end; it fails, saying `missing`, when `ms` pass first
  const waitFor = async (found, ms, missing) => {
    const deadline = Date.now() + ms;
    for (;;) {
      const value = found();
      if (value !== undefined) return value;
      if (Date.now() >= deadline) throw new Error(`${missing} within ${ms} ms`);
      await new Promise((resolve) => { waiters.push(resolve); setTimeout(resolve, 250); });
    }
  };

  return {
    captures,
    watchContext,
    /** What a failed test keeps (#600): the runner's load and each page's attempts and long tasks. */
    evidence,
    async next(page, ms) {
      const found = () => { const entry = captures.find((each) => each.page === page); return entry && entry.result; };
      return waitFor(found, ms, 'no stall capture of the page');
    },
    async started(page, ms) {
      await waitFor(() => (starts.includes(page) ? true : undefined), ms, 'no stall capture of the page began');
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
      // the captures running are waited for, but not for ever: a native step
      // started at the margin before the timeout would hold the teardown
      const settled = await within(Promise.all([...running]), TEARDOWN_MS);
      if (!settled.answered) {
        // a capture still running outside node (gdb attached to a renderer that
        // the browser, shared by the worker's next tests, would keep stopped) is
        // ended, and none starts
        await within(scope.abort(), HELPER_MS);
        await within(Promise.all([...running]), 1500);
      }
      await keepEvidence();
      await releaseMojoTrace(browser);
      leaveSampler();
      for (const pending of armed.values()) {
        const arming = await within(pending, COMMAND_MS);
        if (arming.value && arming.value.session) arming.value.session.detach().catch(() => {});
      }
    },
  };
}
