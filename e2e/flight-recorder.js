/**
 * The flight recorder (#575): what happened in the seconds before a page froze, kept in rings
 * while the e2e run goes on and written out only when a renderer is frozen. Keyword: flight recorder.
 *  - the kernel's ring (flight-tracefs.js): futex waits and wakes, wakeups, switches, signals and
 *    the byte traffic of the run's process tree, in an ftrace instance of its own;
 *  - Chrome's own ring (the DevTools `Tracing` domain, `recordContinuously`): toplevel, ipc, mojom, sync.
 * On in CI, and anywhere with QUIRE_FLIGHT=1; QUIRE_NO_RECORDER=1 turns it off.
 */

import { execFile, spawn } from 'node:child_process';
import { createGunzip, createGzip } from 'node:zlib';
import { createReadStream, existsSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { createWriteStream, statSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { Readable } from 'node:stream';
import { fileURLToPath } from 'node:url';
import * as tracefs from './flight-tracefs.js';

export const INSTANCE_VARIABLE = 'QUIRE_FLIGHT_INSTANCE';
const ROOT_SCRIPT = join(dirname(fileURLToPath(import.meta.url)), 'flight-tracefs.js');
const ROOT_MS = 60000;
export const ROOT_MOST_MS = ROOT_MS;
export const TRACE_END_MS = 15000;
export const TRACE_BUFFER_KB = 32768;
// the light set: +5% on a loop of page cycles with the kernel ring, the nine-category set +10% (measured, quire#575)
// devtools.timeline adds ResourceSendRequest and ResourceFinish: a fetch a service worker never answers reaches no network layer, so only these show it (+1%)
export const TRACE_CATEGORIES = ['toplevel', 'ipc', 'mojom', 'sync', 'devtools.timeline'];

// QUIRE_FLIGHT_VIA_SUDO=1 takes the runner's path (every root step through `sudo -n`, as on CI's non-root user) even where the machine is root, so a
// worker's machine reproduces what CI does; no job sets it. Keyword: via sudo.
export const isRoot = typeof process.getuid === 'function' && process.getuid() === 0 && !process.env.QUIRE_FLIGHT_VIA_SUDO;

/** Whether this run records: CI or QUIRE_FLIGHT=1, on Linux, unless QUIRE_NO_RECORDER is set. */
export function wanted(env = process.env) {
  const on = (name) => env[name] !== undefined && env[name] !== '' && env[name] !== '0';
  return process.platform === 'linux' && !on('QUIRE_NO_RECORDER') && (on('CI') || on('QUIRE_FLIGHT'));
}

// as root in this process, else through sudo (the runners allow it without a password)
function asRoot(op, args) {
  if (isRoot) return Promise.resolve(tracefs[op](args));
  return new Promise((resolve) => {
    execFile('sudo', ['-n', process.execPath, ROOT_SCRIPT, op, JSON.stringify(args)], { timeout: ROOT_MS, killSignal: 'SIGKILL', maxBuffer: 1 << 20, encoding: 'utf8' }, (error, stdout, stderr) => {
      // what the root step said on stderr (a `[ring lock]` line) is said here as it is by the in-process path of a root runner: the runner on CI is not root
      if (stderr) process.stderr.write(String(stderr));
      const last = String(stdout).trim().split('\n').pop();
      try { resolve(JSON.parse(last)); } catch (bad) { resolve({ error: `sudo node ${op} gave no answer (exit ${error && error.code}${error && error.killed ? ', killed after its limit' : ''}): stderr ${String(stderr).slice(0, 300)}; stdout ${String(stdout).slice(0, 200)}` }); }
    });
  });
}

/** Starts the kernel ring for this process tree; the instance goes to the workers by the environment. */
export async function startKernel(env = process.env) {
  if (!wanted(env)) return null;
  // The specs' ways to make the ring fail to start or to record (evidence-real.spec.js; nothing else sets them):
  // QUIRE_FLIGHT_TRACEFS a directory that is no tracefs; QUIRE_FLIGHT_REQUIRE_EVENT an event this kernel has not, required as the others are;
  // QUIRE_FLIGHT_TRACE_PID the process the ring is scoped to, one that is not this run's, so the ring is made and on and records nothing of it
  const started = await asRoot('start', {
    name: `quire-${process.pid}`, pid: Number(env.QUIRE_FLIGHT_TRACE_PID) || process.pid,
    ...(env.QUIRE_FLIGHT_TRACEFS ? { tracefs: env.QUIRE_FLIGHT_TRACEFS } : {}),
    ...(env.QUIRE_FLIGHT_REQUIRE_EVENT ? { alsoRequired: env.QUIRE_FLIGHT_REQUIRE_EVENT.split(',') } : {}),
  });
  if (started.instance) env[INSTANCE_VARIABLE] = started.instance;
  return started;
}

export async function stopKernel(started, env = process.env) {
  if (!started || !started.instance) return null;
  return asRoot('stop', { instance: started.instance, dir: env[OUT_VARIABLE] });
}

const nowSeconds = () => Number(process.hrtime.bigint()) / 1e9; // CLOCK_MONOTONIC, the clock of the ring
// a ring that reaches the red ends no earlier than the red: the snapshot is taken after it, and the snapshot's own process adds events. The slack is for the
// clock reads that differ by a few thousand cycles
export const REACH_SLACK_S = 0.5;

/**
 * Writes the kernel ring's record to `out` (gzipped): a snapshot of the live ring, which goes on recording (ring snapshot, flight-tracefs.js). A capture
 * stops nothing, so a freeze that begins in another worker while this one reads is in the ring.
 * The answer has `reach` (the red's time, the last event's time, whether the file reaches the red).
 * QUIRE_FLIGHT_LOCK_MOST_MS: the spec's way to see a lock that is not had without waiting its whole limit; nothing else sets it.
 */
export async function keepKernel(out, env = process.env) {
  const instance = env[INSTANCE_VARIABLE];
  if (!instance) return { unavailable: wanted(env) ? 'the kernel ring did not start (no tracefs, or sudo refused: see the run\'s first lines)' : 'not recording (neither CI nor QUIRE_FLIGHT=1, or QUIRE_NO_RECORDER)' };
  const dir = env[OUT_VARIABLE];
  const lockMost = Number(env.QUIRE_FLIGHT_LOCK_MOST_MS) > 0 ? Number(env.QUIRE_FLIGHT_LOCK_MOST_MS) : null;
  const redAt = nowSeconds();
  let kept;
  try { kept = await asRoot('snapshot', { instance, out, dir, ...(lockMost ? { lockMost } : {}) }); } catch (error) { kept = { error: String((error && error.message) || error) }; }
  if (kept.file) {
    try { kept.bytes = statSync(kept.file).size; } catch (gone) { /* kept.file is not there */ }
    const lastAt = typeof kept.lastAt === 'number' ? kept.lastAt : null;
    kept.reach = { redAt, lastAt, reaches: lastAt !== null && lastAt >= redAt - REACH_SLACK_S };
    if (!kept.reach.reaches) kept.reach.why = lastAt === null ? 'the snapshot holds no event since the capture before it' : `the last event is ${(redAt - lastAt).toFixed(1)} s before the red`;
    try { writeFileSync(`${out}.reach.json`, JSON.stringify(kept.reach)); kept.reachFile = `${out}.reach.json`; } catch (error) { /* the directory is gone */ }
  }
  return kept;
}

export const OUT_VARIABLE = 'QUIRE_FLIGHT_OUT';
const within = (promise, ms) => new Promise((resolve) => {
  const timer = setTimeout(() => resolve({ timedOut: true }), ms);
  promise.then((value) => { clearTimeout(timer); resolve({ value }); }, (error) => { clearTimeout(timer); resolve({ error: String((error && error.message) || error) }); });
});

const traces = new WeakMap(); // browser -> its trace (a promise of { session } or { unavailable })

/** Starts Chrome's ring on the browser (once for it). Never throws. */
export function startBrowserTrace(browser, env = process.env) {
  if (!wanted(env) || typeof browser.newBrowserCDPSession !== 'function') return null;
  if (traces.has(browser)) return traces.get(browser);
  const trace = (async () => {
    try {
      const session = await browser.newBrowserCDPSession();
      await session.send('Tracing.start', {
        traceConfig: { recordMode: 'recordContinuously', includedCategories: TRACE_CATEGORIES, traceBufferSizeInKb: TRACE_BUFFER_KB },
        transferMode: 'ReturnAsStream',
        streamFormat: 'json',
      });
      return { session };
    } catch (error) { return { unavailable: `Tracing.start failed: ${String((error && error.message) || error).slice(0, 300)}` }; }
  })();
  traces.set(browser, trace);
  return trace;
}

/** Ends Chrome's ring and writes it to `out` (gzipped): every process that answers hands over what it holds. */
export async function keepBrowserTrace(browser, out) {
  const trace = traces.get(browser);
  if (!trace) return { unavailable: 'not recording (neither CI nor QUIRE_FLIGHT=1, or QUIRE_NO_RECORDER)' };
  const started = await trace;
  if (!started.session) return { unavailable: started.unavailable };
  const { session } = started;
  const began = Date.now();
  try {
    const complete = new Promise((resolve) => session.once('Tracing.tracingComplete', resolve));
    const ended = await within(session.send('Tracing.end'), TRACE_END_MS);
    if (ended.timedOut || ended.error) return { unavailable: `Tracing.end ${ended.error || `was not answered within ${TRACE_END_MS} ms`}` };
    const done = await within(complete, TRACE_END_MS);
    if (!done.value) return { unavailable: `the browser did not finish the trace within ${TRACE_END_MS} ms` };
    const flushed = done.value;
    // read the stream out chunk by chunk into the gzip file
    const parts = [];
    const chunks = (async function* () {
      for (;;) {
        const part = await session.send('IO.read', { handle: flushed.stream, size: 1 << 20 });
        const piece = part.base64Encoded ? Buffer.from(part.data, 'base64') : part.data;
        parts.push(piece);
        yield piece;
        if (part.eof) break;
      }
    })();
    await pipeline(Readable.from(chunks), createGzip({ level: 6 }), createWriteStream(out));
    return { file: out, bytes: statSync(out).size, dataLoss: !!flushed.dataLossOccurred, ms: Date.now() - began, pendingRequests: pendingRequests(parts.map(String).join('')) };
  } catch (error) { return { unavailable: `reading the trace failed: ${String((error && error.message) || error).slice(0, 300)}` }; }
}

/** Both records for one capture, kernel first (its snapshot is taken at once); each says why when it cannot. Neither ring stops. */
export async function keepBoth(browser, pathFor, env = process.env) {
  const kernel = await keepKernel(pathFor('kernel.txt.gz'), env);
  const browserTrace = await keepBrowserTrace(browser, pathFor('browser-trace.json.gz'));
  // the trace starts again for the tests that follow (the first record is kept; a later failure has a record of its own)
  if (typeof browser.isConnected === 'function' && browser.isConnected()) { traces.delete(browser); startBrowserTrace(browser, env); }
  return { kernel, browserTrace };
}

/** Whether a Playwright command line is the run of the @serial tests (`--grep @serial`, as gen-pwa passes it; `--grep-invert` is the other run). */
export function serialRun(argv = process.argv) {
  return argv.some((argument, index) => {
    if (argument === '--grep' || argument === '-g') return String(argv[index + 1] || '').includes('@serial');
    return argument.startsWith('--grep=') && argument.includes('@serial');
  });
}

/** Memory of a process (root reads /proc/<pid>/mem): { address, bytes: hex } or { address, error }. */
export function readMemory(pid, address, length = 64) { return asRoot('readmem', { pid, address, length }); }

/** The system call the main thread of a process is in (root reads /proc/<pid>/task/<pid>/syscall): { syscall: '202 0xaddress 0x189 ...' } or { error }. */
export function readSyscall(pid) { return asRoot('readsyscall', { pid }); }

// FUTEX_WAIT 0, WAKE 1, REQUEUE 3, WAKE_OP 5, WAIT_BITSET 9, WAKE_BITSET 10 (flags 0x80 private and 0x100 realtime are masked off)
const FUTEX_WAITS = new Set([0, 9, 11, 13]);
const FUTEX_WAKES = new Set([1, 3, 4, 5, 10, 12]);
const RING_LINE = /^\s*(.+)-(\d+)\s+\[\d+\]\s+\S+\s+(\d+\.\d+):\s+(.*)$/;
// the kernel prints the arguments in hex with a 0x on some versions (6.18) and without on others (7.0, the runners'): both are read
const FUTEX_CALL = /sys_futex\(uaddr: (?:0x)?([0-9a-f]+), op: (?:0x)?([0-9a-f]+), val: (\S+), utime: (\S+?),/;

/**
 * What the kernel ring says of one futex word and the thread that waits on it (#575): the waiter's last wait
 * (its op and whether it has a timeout), every wait and wake on the address, who woke the waiter last and when, and
 * how long the ring has been silent about it. `address` is hex (no 0x), `tid` the waiter's. Streams the gzipped
 * ring; keeps the last 40 events on the address.
 */
export async function futexAnalysis(ringFile, { address, tid }) {
  if (!existsSync(ringFile)) throw new Error(`${ringFile} is not there`);
  const wanted = address.toLowerCase().replace(/^0x/, '').replace(/^0+/, '');
  const last = [];
  const wakers = new Map();
  let lastWait = null, wokenLast = null, switchedOut = null, ringEnd = 0, lines = 0, onAddress = 0;
  const reader = createInterface({ input: createReadStream(ringFile).pipe(createGunzip()), crlfDelay: Infinity });
  for await (const line of reader) {
    if (line.startsWith('#')) continue;
    const parts = RING_LINE.exec(line);
    if (!parts) continue;
    lines += 1;
    const [, task, thread, stamp, text] = parts;
    const at = Number(stamp);
    ringEnd = at;
    const call = FUTEX_CALL.exec(text);
    if (call) {
      const where = call[1].replace(/^0+/, '');
      const op = parseInt(call[2], 16) & 0x7f;
      const untimed = FUTEX_WAITS.has(op) && /^(0x)?0+$/.test(call[4]);
      const entry = { at, task: task.trim(), tid: Number(thread), op: `0x${call[2]}`, kind: FUTEX_WAITS.has(op) ? 'wait' : FUTEX_WAKES.has(op) ? 'wake' : 'other', untimed };
      if (Number(thread) === tid && entry.kind === 'wait') lastWait = { ...entry, address: call[1] };
      if (where === wanted) {
        onAddress += 1;
        last.push(entry);
        if (last.length > 40) last.shift();
        if (entry.kind === 'wake') wakers.set(`${entry.task}-${entry.tid}`, { task: entry.task, tid: entry.tid, lastAt: at });
      }
      continue;
    }
    const woken = /^sched_wakeup: comm=(.*) pid=(\d+) /.exec(text);
    if (woken && Number(woken[2]) === tid) wokenLast = { at, by: `${task.trim()}-${thread}` };
    const switched = /^sched_switch: prev_comm=.* prev_pid=(\d+) prev_prio=\d+ prev_state=(\S+) ==>/.exec(text);
    if (switched && Number(switched[1]) === tid) switchedOut = { at, state: switched[2] };
  }
  return {
    address: `0x${wanted}`, waiterTid: tid, ringLines: lines, ringEnd,
    waiter: {
      lastWait, switchedOut, wokenLast,
      silentMs: wokenLast ? Math.round((ringEnd - wokenLast.at) * 1000) : null,
      sleepingMs: switchedOut ? Math.round((ringEnd - switchedOut.at) * 1000) : null,
    },
    onAddress: { events: onAddress, wakers: [...wakers.values()], last },
  };
}

/** Whether a kept ring file has content: { ok, lines } or { ok: false, why }. */
/**
 * The first line of the ring file that each pattern matches: { name: line | null }, read as a stream a line at a time. A ring that
 * recorded a whole run is larger than a string can be (0x1fffffe8 characters), so no reader of a ring builds one string of it.
 */
export async function ringSeen(file, patterns) {
  const seen = Object.fromEntries(Object.keys(patterns).map((name) => [name, null]));
  const reader = createInterface({ input: createReadStream(file).pipe(createGunzip()), crlfDelay: Infinity });
  let open = Object.keys(patterns).length;
  for await (const line of reader) {
    for (const [name, pattern] of Object.entries(patterns)) {
      if (seen[name] === null && pattern.test(line)) { seen[name] = line; open -= 1; }
    }
    if (open === 0) break;
  }
  reader.close();
  return seen;
}

export async function ringContent(file) {
  if (!existsSync(file)) return { ok: false, why: `unreadable: ${file} is not there` };
  try {
    const reader = createInterface({ input: createReadStream(file).pipe(createGunzip()), crlfDelay: Infinity });
    let header = false, lines = 0;
    for await (const line of reader) { if (line.includes('entries-in-buffer')) header = true; else if (!line.startsWith('#') && line.trim()) lines += 1; if (lines > 0 && header) break; }
    return lines > 0 && header ? { ok: true, lines } : { ok: false, why: `the ring file holds ${lines} events${header ? '' : ' and no header'}` };
  } catch (error) { return { ok: false, why: `unreadable: ${String((error && error.message) || error).slice(0, 200)}` }; }
}

export const WATCHDOG_DIRECTORY = 'flight-watchdog';
const WATCHDOG_SCRIPT = join(dirname(fileURLToPath(import.meta.url)), 'flight-watchdog.js');

/** Starts the watchdog (flight-watchdog.js) as root for this process tree; { child } or { unavailable }. Ends with `stopWatchdog`. */
export function startWatchdog(instance, env = process.env, out = join(process.cwd(), WATCHDOG_DIRECTORY), sustainMs = 10000, match = '') {
  if (!wanted(env)) return null;
  // QUIRE_FLIGHT_WATCHDOG_SCRIPT: the spec's way to make the watchdog really fail (a script that dies); nothing else sets it
  const args = [env.QUIRE_FLIGHT_WATCHDOG_SCRIPT || WATCHDOG_SCRIPT, String(process.pid), out, instance || '', String(sustainMs), match, env[OUT_VARIABLE] || ''];
  // what became of the child is kept, never swallowed: the preflight and the monitor read it
  const started = { out, stopping: false, exited: null, error: null, child: null };
  try {
    const child = isRoot ? spawn(process.execPath, args, { stdio: ['pipe', 'inherit', 'inherit'] }) : spawn('sudo', ['-n', process.execPath, ...args], { stdio: ['pipe', 'inherit', 'inherit'] });
    child.on('error', (error) => { started.error = String((error && error.message) || error); });
    child.on('exit', (code, signal) => { started.exited = { code, signal }; });
    started.child = child;
  } catch (error) { started.error = String((error && error.message) || error); }
  return started;
}

export function stopWatchdog(started) {
  if (started && started.child) { started.stopping = true; try { started.child.kill('SIGTERM'); } catch (gone) { /* already gone */ } }
}

/** The ring's readings: { on, written } (the heartbeat), and the probe of the preflight. */
export function ringStats(env = process.env) {
  const instance = env[INSTANCE_VARIABLE];
  return instance ? asRoot('stats', { instance }) : Promise.resolve({ error: 'no ring' });
}
/** Whether the browser's trace ring is on: the answer of Tracing.start, awaited. Throws PREFLIGHT FAILED where it is wanted and is not. */
export async function traceReady(browser, env = process.env) {
  if (!wanted(env)) return null;
  const trace = traces.get(browser) || startBrowserTrace(browser, env);
  const started = await trace;
  if (!started || !started.session) throw new Error(`PREFLIGHT FAILED: browser trace ring: ${(started && started.unavailable) || 'it did not start'}`);
  return started;
}

/** Whether the ring records now: { on: '1' | '0' } or { error }. */
export function ringState(env = process.env) {
  const instance = env[INSTANCE_VARIABLE];
  return instance ? asRoot('state', { instance }) : Promise.resolve({ unavailable: 'no ring' });
}

/**
 * The requests the renderer began and did not see finish, from Chrome's trace text (ResourceSendRequest against
 * ResourceReceiveResponse and ResourceFinish): the only record of a fetch a service worker holds, which reaches no network
 * layer. [{ url, requestId, ageMs }], ageMs from the request to the last event of the trace.
 */
export function pendingRequests(text) {
  try {
    const parsed = JSON.parse(text);
    const events = Array.isArray(parsed) ? parsed : parsed.traceEvents || [];
    const sent = new Map();
    let last = 0;
    for (const event of events) {
      if (event.ts > last) last = event.ts;
      const id = event.args && event.args.data && event.args.data.requestId;
      if (!id) continue;
      if (event.name === 'ResourceSendRequest') sent.set(`${event.pid}:${id}`, { url: event.args.data.url, requestId: id, at: event.ts });
      else if (event.name === 'ResourceReceiveResponse' || event.name === 'ResourceFinish') sent.delete(`${event.pid}:${id}`);
    }
    return [...sent.values()].map((each) => ({ url: each.url, requestId: each.requestId, ageMs: Math.round((last - each.at) / 1000) })).slice(-100);
  } catch (error) { return { error: String((error && error.message) || error).slice(0, 200) }; }
}

/** Stops the recording of a ring by its instance path (what a fault in the run does; the spec's way to kill a ring mid-run). */
export function pauseInstance(instance) { return asRoot('pause', { instance }); }
/** Starts a ring recording again after `pauseInstance` (the cost measurement before the tests; a capture never pauses a ring). */
export function resumeInstance(instance) { return asRoot('resume', { instance }); }
/** Removes a ring by its instance path (the spec's way to make the red-time snapshot fail). */
export function removeInstance(instance) { return asRoot('stop', { instance }); }
/** Disables every event of the ring while it stays on (a test's: the ring then takes no events). */
export function silenceInstance(instance) { return asRoot('silence', { instance }); }

// Work the runner has started that needs the ring (the reporter's snapshots): the global teardown waits for it before the ring is removed.
const outstanding = new Set();
export function track(promise) { outstanding.add(promise); promise.finally(() => outstanding.delete(promise)); return promise; }
export async function settleOutstanding() { await Promise.allSettled([...outstanding]); }
