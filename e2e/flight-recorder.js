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
import { createWriteStream, statSync } from 'node:fs';
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

const isRoot = typeof process.getuid === 'function' && process.getuid() === 0;

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
      const last = String(stdout).trim().split('\n').pop();
      try { resolve(JSON.parse(last)); } catch (bad) { resolve({ error: `sudo node ${op} gave no answer (exit ${error && error.code}${error && error.killed ? ', killed after its limit' : ''}): stderr ${String(stderr).slice(0, 300)}; stdout ${String(stdout).slice(0, 200)}` }); }
    });
  });
}

/** Starts the kernel ring for this process tree; the instance goes to the workers by the environment. */
export async function startKernel(env = process.env) {
  if (!wanted(env)) return null;
  // QUIRE_FLIGHT_TRACEFS: the spec's way to make the ring fail to start (a directory that is no tracefs)
  const started = await asRoot('start', { name: `quire-${process.pid}`, pid: process.pid, ...(env.QUIRE_FLIGHT_TRACEFS ? { tracefs: env.QUIRE_FLIGHT_TRACEFS } : {}) });
  if (started.instance) env[INSTANCE_VARIABLE] = started.instance;
  return started;
}

export async function stopKernel(started) {
  if (!started || !started.instance) return null;
  return asRoot('stop', { instance: started.instance });
}

/** Pauses the kernel ring and writes its last lines to `out` (gzipped). */
export async function keepKernel(out, env = process.env, resume = false) {
  const instance = env[INSTANCE_VARIABLE];
  if (!instance) return { unavailable: wanted(env) ? 'the kernel ring did not start (no tracefs, or sudo refused: see the run\'s first lines)' : 'not recording (neither CI nor QUIRE_FLIGHT=1, or QUIRE_NO_RECORDER)' };
  const kept = await asRoot('snapshot', { instance, out, resume });
  if (kept.file) { try { kept.bytes = statSync(kept.file).size; } catch (gone) { /* kept.file is not there */ } }
  return kept;
}

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

/**
 * Both records for one capture, kernel first (its ring is paused at once); each says why when it cannot.
 * `resume`: a failure that is not a freeze, after which both rings start again for the tests that follow.
 */
export async function keepBoth(browser, pathFor, env = process.env, resume = false) {
  const kernel = await keepKernel(pathFor('kernel.txt.gz'), env, resume);
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

// FUTEX_WAIT 0, WAKE 1, REQUEUE 3, WAKE_OP 5, WAIT_BITSET 9, WAKE_BITSET 10 (flags 0x80 private and 0x100 realtime are masked off)
const FUTEX_WAITS = new Set([0, 9, 11, 13]);
const FUTEX_WAKES = new Set([1, 3, 4, 5, 10, 12]);
const RING_LINE = /^\s*(.+)-(\d+)\s+\[\d+\]\s+\S+\s+(\d+\.\d+):\s+(.*)$/;
const FUTEX_CALL = /sys_futex\(uaddr: 0x([0-9a-f]+), op: 0x([0-9a-f]+), val: (\S+), utime: (\S+?),/;

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
export function startWatchdog(instance, env = process.env, out = join(process.cwd(), WATCHDOG_DIRECTORY), sustainMs = 10000) {
  if (!wanted(env)) return null;
  const args = [WATCHDOG_SCRIPT, String(process.pid), out, instance || '', String(sustainMs)];
  try {
    const child = isRoot ? spawn(process.execPath, args, { stdio: ['pipe', 'inherit', 'inherit'] }) : spawn('sudo', ['-n', process.execPath, ...args], { stdio: ['pipe', 'inherit', 'inherit'] });
    child.on('error', () => { /* sudo missing: the run goes on without it */ });
    return { child, out };
  } catch (error) { return { unavailable: String((error && error.message) || error) }; }
}

export function stopWatchdog(started) {
  if (started && started.child) { try { started.child.kill('SIGTERM'); } catch (gone) { /* already gone */ } }
}

/** Starts the kernel ring recording again after a capture paused it (a test that induced a freeze does, for the tests after it). */
export function resumeKernel(env = process.env) {
  const instance = env[INSTANCE_VARIABLE];
  return instance ? asRoot('resume', { instance }) : Promise.resolve({ unavailable: 'no ring' });
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
