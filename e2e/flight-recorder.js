/**
 * The flight recorder (#575): what happened in the seconds before a page froze, kept in rings
 * while the e2e run goes on and written out only when a renderer is frozen. Keyword: flight recorder.
 *  - the kernel's ring (flight-tracefs.js): futex waits and wakes, wakeups, switches, signals and
 *    the byte traffic of the run's process tree, in an ftrace instance of its own;
 *  - Chrome's own ring (the DevTools `Tracing` domain, `recordContinuously`): toplevel, ipc, mojom, sync.
 * On in CI, and anywhere with QUIRE_FLIGHT=1; QUIRE_NO_RECORDER=1 turns it off (the hunt's bare arm).
 */

import { execFile } from 'node:child_process';
import { createGzip } from 'node:zlib';
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
export const TRACE_CATEGORIES = ['toplevel', 'ipc', 'mojom', 'sync'];

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
      try { resolve(JSON.parse(last)); } catch (bad) { resolve({ error: `sudo node ${op} gave no answer: ${String((error && error.message) || stderr || stdout).slice(0, 300)}` }); }
    });
  });
}

/** Starts the kernel ring for this process tree; the instance goes to the workers by the environment. */
export async function startKernel(env = process.env) {
  if (!wanted(env)) return null;
  const started = await asRoot('start', { name: `quire-${process.pid}`, pid: process.pid });
  if (started.instance) env[INSTANCE_VARIABLE] = started.instance;
  return started;
}

export async function stopKernel(started) {
  if (!started || !started.instance) return null;
  return asRoot('stop', { instance: started.instance });
}

/** Pauses the kernel ring and writes its last lines to `out` (gzipped). */
export async function keepKernel(out, env = process.env) {
  const instance = env[INSTANCE_VARIABLE];
  if (!instance) return { unavailable: wanted(env) ? 'the kernel ring did not start (no tracefs, or sudo refused: see the run\'s first lines)' : 'not recording (neither CI nor QUIRE_FLIGHT=1, or QUIRE_NO_RECORDER)' };
  const kept = await asRoot('snapshot', { instance, out });
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
    const chunks = (async function* () {
      for (;;) {
        const part = await session.send('IO.read', { handle: flushed.stream, size: 1 << 20 });
        yield part.base64Encoded ? Buffer.from(part.data, 'base64') : part.data;
        if (part.eof) break;
      }
    })();
    await pipeline(Readable.from(chunks), createGzip({ level: 6 }), createWriteStream(out));
    return { file: out, bytes: statSync(out).size, dataLoss: !!flushed.dataLossOccurred, ms: Date.now() - began };
  } catch (error) { return { unavailable: `reading the trace failed: ${String((error && error.message) || error).slice(0, 300)}` }; }
}

/** Both records for one capture, kernel first (its ring is paused at once); each says why when it cannot. */
export async function keepBoth(browser, pathFor, env = process.env) {
  const kernel = await keepKernel(pathFor('kernel.txt.gz'), env);
  const browserTrace = await keepBrowserTrace(browser, pathFor('browser-trace.json.gz'));
  return { kernel, browserTrace };
}
