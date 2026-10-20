/**
 * What a capture holds beyond the stall watch's own (#575), one function for each thing that identifies a class
 * of failure, and the check that a failing run has them. Keyword: evidence. Every function is a note, never a failure.
 */

import { existsSync, readdirSync, readFileSync, statfsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { futexAnalysis, readMemory, ringContent, wanted } from './flight-recorder.js';

const within = (promise, ms) => new Promise((resolve) => {
  const timer = setTimeout(() => resolve({ answered: false }), ms);
  promise.then((value) => { clearTimeout(timer); resolve({ answered: true, value }); }, (error) => { clearTimeout(timer); resolve({ answered: true, error: String((error && error.message) || error).slice(0, 200) }); });
});

/** The free space and inodes where a run writes: a full disk is a class of its own. */
export function diskEvidence(paths = [process.cwd(), tmpdir(), '/', ...(process.env.QUIRE_EVIDENCE_PATHS || '').split(':').filter(Boolean)]) {
  return [...new Set(paths)].map((path) => {
    try {
      const fs = statfsSync(path);
      return { path, freeBytes: fs.bavail * fs.bsize, totalBytes: fs.blocks * fs.bsize, freeInodes: fs.ffree, totalInodes: fs.files };
    } catch (error) { return { path, error: String((error && error.code) || error) }; }
  });
}

// futex(uaddr, op, val, timeout, ...): syscall 202, the waits are FUTEX_WAIT 0 and FUTEX_WAIT_BITSET 9 (flags 0x80 private, 0x100 realtime)
export function parseFutexSyscall(text) {
  const found = /^202 0x([0-9a-f]+) 0x([0-9a-f]+) 0x[0-9a-f]+ 0x([0-9a-f]+)/.exec(String(text).trim());
  if (!found) return null;
  const op = parseInt(found[2], 16);
  return { address: found[1], op: `0x${found[2]}`, timeoutPointer: `0x${found[3]}`, wait: [0, 9].includes(op & 0x7f), untimed: [0, 9].includes(op & 0x7f) && /^0+$/.test(found[3]) };
}

/**
 * For each frozen renderer whose main thread is in a futex: the word (its address, the 64 bytes around it as
 * the process holds them), whether the wait has a timeout, what the kernel ring says of the address and of the
 * waiter (who woke it last and how long ago, every wait and wake on the word), and the process's other threads as
 * the candidates for the one that should have woken it.
 */
export async function futexEvidence(native, ringFile) {
  if (!native || !Array.isArray(native.renderers)) return [];
  const found = [];
  for (const renderer of native.renderers) {
    const tasks = (renderer.kernel && renderer.kernel.tasks) || [];
    const main = tasks.find((task) => task.tid === renderer.pid);
    const call = main && parseFutexSyscall(main.syscall);
    if (!call) { found.push({ pid: renderer.pid, notInFutex: main ? `main thread syscall: ${String(main.syscall).slice(0, 80)}` : 'no kernel view of the main thread' }); continue; }
    const entry = { pid: renderer.pid, ...call };
    entry.memory = await readMemory(renderer.pid, `0x${call.address}`, 64).catch((error) => ({ error: String(error) }));
    entry.candidates = tasks.filter((task) => task.tid !== renderer.pid).map((task) => ({ tid: task.tid, comm: task.comm, state: task.state, wchan: task.wchan, syscall: String(task.syscall).split(' ').slice(0, 3).join(' ') }));
    entry.ring = ringFile ? await futexAnalysis(ringFile, { address: call.address, tid: renderer.pid }).catch((error) => ({ error: String(error && error.message || error) })) : 'the kernel ring was not kept';
    found.push(entry);
  }
  return found;
}

/**
 * Whether the frames of a frozen renderer have names, and if not, why and what resolves them later. A frame is
 * named by the binary's own symbols (.symtab), or by a separate debug file for its build id (QUIRE_SYMBOLS_DIR,
 * /usr/lib/debug); the Chrome for Testing 149 headless shell has neither and no public source holds one (its
 * bucket has no symbols object: 404 for each name tried; Playwright 1.61 downloads the same build), so the state is
 * `unavailable` with the module and offset of every frame (what an offline lookup takes) and the thread, task and
 * Mojo interface names of the kernel ring and Chrome's trace stand in.
 */
export function symbolEvidence(native, env = process.env) {
  if (!native || !Array.isArray(native.renderers)) return [];
  return native.renderers.map((renderer) => {
    const frames = (renderer.gdbStacks && renderer.gdbStacks.mainThread && renderer.gdbStacks.mainThread.frames) || [];
    const named = frames.filter((frame) => / in (?!\?\?)\S/.test(frame.text)).length;
    const id = renderer.buildId || null;
    const directories = [env.QUIRE_SYMBOLS_DIR, '/usr/lib/debug'].filter(Boolean);
    const debugFile = id ? directories.map((directory) => join(directory, '.build-id', id.slice(0, 2), `${id.slice(2)}.debug`)).find((path) => existsSync(path)) : null;
    const hasSymtab = !!(renderer.binary && renderer.binary.hasSymtab);
    let state;
    if (debugFile) state = `debug file found: ${debugFile}`;
    else if (hasSymtab) state = 'named by the binary\'s own symbols (.symtab)';
    else state = `unavailable: the binary is stripped (${renderer.binary && renderer.binary.hasDebugLink ? '.gnu_debuglink only' : 'no symbols'}) and no debug file for build id ${id} was found in ${directories.join(', ')}; none exists publicly for Chrome for Testing`;
    return {
      pid: renderer.pid, buildId: id, state, frames: frames.length, named,
      // what resolves the unnamed ones offline: module and offset of each
      unnamed: frames.filter((frame) => !/ in (?!\?\?)\S/.test(frame.text)).slice(0, 20).map((frame) => ({ pc: frame.pc, module: frame.module || null, offset: frame.offset || null })),
    };
  });
}

/** The page's service worker (controller and registrations) and whether a frame is produced: for a page that answers. */
export async function pageProbes(page, ms = 2000) {
  const worker = await within(page.evaluate(async () => {
    if (!navigator.serviceWorker) return { supported: false };
    const registrations = await navigator.serviceWorker.getRegistrations();
    const controller = navigator.serviceWorker.controller;
    return {
      supported: true,
      controller: controller ? { state: controller.state, scriptURL: controller.scriptURL } : null,
      registrations: registrations.map((each) => ({ scope: each.scope, active: each.active ? each.active.state : null, waiting: each.waiting ? each.waiting.state : null, installing: each.installing ? each.installing.state : null })),
    };
  }), ms);
  const started = Date.now();
  const frame = await within(page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => resolve(1)))), ms);
  return {
    serviceWorker: worker.answered ? (worker.error ? { error: worker.error } : worker.value) : { notAnswered: `no answer within ${ms} ms` },
    frames: { answered: frame.answered && !frame.error, ms: Date.now() - started, error: frame.error },
  };
}

/**
 * What a failing test must have left. `state`: { status, wanted, frozen (a capture of a frozen renderer or a crash was taken),
 * captureFile, flight: { kernel, browserTrace } of the last keepBoth, browserGone }. Returns the missing fields, each named.
 * Applies only to a test that timed out or whose renderer froze or crashed, and only where the recorder is wanted (CI).
 */
export async function missingEvidence(state, env = process.env) {
  const failing = state.status === 'timedOut' || state.frozen;
  if (!failing || !wanted(env)) return [];
  const missing = [];
  const flight = state.flight;
  if (!flight) return ['flight recorder (nothing was written for the failure)'];
  const kernel = flight.kernel || {};
  if (!kernel.file) missing.push(`kernel ring (${kernel.unavailable || kernel.error || 'not written'})`);
  else {
    const content = await ringContent(kernel.file);
    if (!content.ok) missing.push(`kernel ring (${content.why})`);
  }
  const trace = flight.browserTrace || {};
  if (!trace.file && !state.browserGone) missing.push(`browser trace (${trace.unavailable || trace.error || 'not written'})`);
  if (state.frozen && !state.captureFile) missing.push('stall capture');
  return missing;
}

/**
 * The reports a sanitizer wrote (ASAN_OPTIONS=log_path=<dir>/asan, see check.yml's sanitizer step): each file's name,
 * its ERROR line and its first 1500 characters. A memory error in a process of the run lands here, whatever else it
 * did to the process; a crash capture carries it.
 */
export function sanitizerReports(directory = process.env.QUIRE_SANITIZER_LOGS) {
  if (!directory) return [];
  let names = [];
  try { names = readdirSync(directory).filter((name) => /^(asan|tsan|ubsan|msan)\./.test(name)); } catch (error) { return []; }
  return names.map((name) => {
    const body = (() => { try { return readFileSync(join(directory, name), 'utf8'); } catch (error) { return ''; } })();
    return { file: join(directory, name), summary: (/(ERROR|WARNING): \w*Sanitizer[^\n]*/.exec(body) || [''])[0], head: body.slice(0, 1500) };
  });
}
