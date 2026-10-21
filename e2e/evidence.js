/**
 * What a capture holds beyond the stall watch's own (#575), one function for each thing that identifies a class
 * of failure, and the check that a failing run has them. Keyword: evidence. Every function is a note, never a failure.
 */

import { existsSync, readdirSync, readFileSync, readlinkSync, statSync, statfsSync } from 'node:fs';
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
    if (!call) {
      // not a futex: another call it waits in, with the file it waits on and who else holds that file (the other end of a pipe or socket)
      const blocked = main && parseBlocked(main.syscall);
      if (blocked) found.push({ pid: renderer.pid, notInFutex: `main thread waits in ${blocked.name}`, blocked, target: blocked.fd === null ? null : fdTarget(renderer.pid, blocked.fd), peers: blocked.fd === null ? [] : fdPeers(renderer.pid, blocked.fd), candidates: tasks.filter((task) => task.tid !== renderer.pid).map((task) => ({ tid: task.tid, comm: task.comm, state: task.state, wchan: task.wchan, syscall: String(task.syscall).split(' ').slice(0, 3).join(' ') })) });
      else found.push({ pid: renderer.pid, notInFutex: main ? `main thread syscall: ${String(main.syscall).slice(0, 80)}` : 'no kernel view of the main thread' });
      continue;
    }
    const words = String(main.syscall).trim().split(/\s+/);
    // the stack pointer and the program counter of the wait: where on its stack the word lies and in which code it sleeps (G4 of #575)
    const entry = { pid: renderer.pid, ...call, registers: { sp: words[7] || null, pc: words[8] || null } };
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
  // a test that did not end as expected (failed, timed out, interrupted) or whose renderer froze or crashed owes its record
  const unexpected = !!state.status && !['passed', 'skipped'].includes(state.status) && state.status !== state.expectedStatus;
  const failing = unexpected || state.frozen;
  // only a test of the capture's own teardown sets this: it ends the capture's native step on purpose, so the fields that step gives are not owed
  if (!failing || !wanted(env) || state.cutOnPurpose) return [];
  const missing = [];
  const flight = state.flight;
  if (!flight) return ['flight recorder (nothing was written for the failure)'];
  missing.push(...incompleteCapture(state.captureResult));
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

// x86-64 system calls a thread can wait in: the name, and which argument is the file it waits on
const BLOCKING = { 0: ['read', 0], 1: ['write', 0], 7: ['poll', null], 17: ['pread64', 0], 23: ['select', null], 34: ['pause', null], 43: ['accept', 0], 45: ['recvfrom', 0], 47: ['recvmsg', 0], 61: ['wait4', null], 202: ['futex', null], 232: ['epoll_wait', 0], 247: ['waitid', null], 270: ['pselect6', null], 271: ['ppoll', null], 281: ['epoll_pwait', 0], 288: ['accept4', 0], 299: ['recvmmsg', 0] };

/**
 * What a thread's /proc/<pid>/task/<tid>/syscall says of a wait that has no end in sight: the call, its arguments, the file it
 * waits on, and whether it has a timeout (epoll_wait and poll with -1, ppoll and select with no timeout; read, recv*, accept and
 * pause wait for ever by nature; a write that has not returned is a pipe or socket nobody reads). null when the thread is running,
 * sleeps with a timeout (nanosleep) or in a call this table does not name.
 */
export function parseBlocked(text) {
  const words = String(text).trim().split(/\s+/);
  if (words.length < 8 || !/^\d+$/.test(words[0])) return null;
  const number = Number(words[0]);
  const entry = BLOCKING[number];
  if (!entry) return null;
  const args = words.slice(1, 7).map((word) => BigInt(word));
  const minusOne = (value) => (value & 0xffffffffn) === 0xffffffffn;
  let untimed = true;
  if (number === 202) { const futex = parseFutexSyscall(text); untimed = !!(futex && futex.untimed); }
  else if (number === 232 || number === 281) untimed = minusOne(args[3]);
  else if (number === 7) untimed = minusOne(args[2]);
  else if (number === 271) untimed = args[2] === 0n;
  else if (number === 23 || number === 270) untimed = args[4] === 0n;
  return { nr: number, name: entry[0], args: words.slice(1, 7), untimed, fd: entry[1] === null ? null : Number(args[entry[1]]), sp: words[7], pc: words[8] || null };
}

/** What a process's file descriptor points at: `pipe:[123]`, `socket:[456]`, a path, `anon_inode:[eventpoll]`. */
export function fdTarget(pid, fd, proc = '/proc') {
  try { return readlinkSync(`${proc}/${pid}/fd/${fd}`); } catch (error) { return `unreadable: ${(error && error.code) || error}`; }
}

/** The other processes that hold the same pipe or socket open (the other end of a wait): [{ pid, comm, fd }], at most 20. */
export function fdPeers(pid, fd, proc = '/proc') {
  const target = fdTarget(pid, fd, proc);
  // an anonymous pipe or a socket is told by its inode; a named pipe by its path, and only a pipe's path is matched (a file's other holders are not the other end of a wait)
  let named = false;
  try { named = target.startsWith('/') && statSync(`${proc}/${pid}/fd/${fd}`).isFIFO(); } catch (error) { named = false; }
  if (!named && !/^(pipe|socket):\[\d+\]$/.test(target)) return [];
  const found = [];
  let names = [];
  try { names = readdirSync(proc).filter((name) => /^\d+$/.test(name)); } catch (error) { return []; }
  for (const name of names) {
    let fds = [];
    try { fds = readdirSync(`${proc}/${name}/fd`); } catch (error) { continue; }
    for (const each of fds) {
      let link = '';
      try { link = readlinkSync(`${proc}/${name}/fd/${each}`); } catch (error) { continue; }
      if (link === target && !(Number(name) === pid && Number(each) === fd)) {
        let comm = '';
        try { comm = readFileSync(`${proc}/${name}/comm`, 'utf8').trim(); } catch (error) { comm = '?'; }
        found.push({ pid: Number(name), comm, fd: Number(each) });
        if (found.length >= 20) return found;
      }
    }
  }
  return found;
}

/**
 * The fields of a frozen capture that should hold something and do not, each named: the capture's own error, the futex word's
 * memory, the ring's analysis, a wait that is not in the ring (older than the ring, or lost). A frozen capture whose futex
 * entry cannot say what the thread waits on is not evidence.
 */
export function incompleteCapture(capture) {
  if (!capture) return [];
  const missing = [];
  if (capture.evidenceError) missing.push(`capture fields (${String(capture.evidenceError).split('\n')[0].slice(0, 160)})`);
  if (capture.flight && capture.flight.error) missing.push(`flight record (${String(capture.flight.error).slice(0, 160)})`);
  for (const each of capture.futex || []) {
    if (each.notInFutex) { if (!each.blocked && /^no kernel view/.test(each.notInFutex)) missing.push(`kernel view of renderer ${each.pid}`); continue; }
    if (each.memory && each.memory.error) missing.push(`futex word memory of renderer ${each.pid} (${each.memory.error})`);
    if (typeof each.ring === 'string') missing.push(`futex ring analysis of renderer ${each.pid} (${each.ring})`);
    else if (each.ring && each.ring.error) missing.push(`futex ring analysis of renderer ${each.pid} (${each.ring.error})`);
    else if (each.ring && each.ring.waiter && each.ring.waiter.lastWait === null) missing.push(`futex wait of renderer ${each.pid} (not in the kernel ring: it began before the ring or was lost)`);
  }
  return missing;
}

/**
 * What is on the page when a test fails and the page still answers (#556: a banner or a toast over a control; #600: a page busy
 * with a task): its address and title, the scroll, the focused element, and every fixed or sticky element that is shown (banners,
 * toasts, bars, dialogs) with its box, its text and its stacking, the dialogs and inert regions. Bounded to `ms`.
 */
export async function pageState(page, ms = 2000) {
  const read = await within(page.evaluate(() => {
    const shown = (e) => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const describe = (e) => (e ? `${e.tagName.toLowerCase()}${e.id ? `#${e.id}` : ''}${e.className && typeof e.className === 'string' ? `.${e.className.trim().split(/\s+/).join('.')}` : ''}` : null);
    const overlays = [];
    for (const e of document.querySelectorAll('body *')) {
      const style = getComputedStyle(e);
      if ((style.position === 'fixed' || style.position === 'sticky') && shown(e)) {
        const box = e.getBoundingClientRect();
        overlays.push({ element: describe(e), role: e.getAttribute('role'), text: (e.textContent || '').trim().slice(0, 80), box: [box.left, box.top, box.right, box.bottom].map(Math.round), zIndex: style.zIndex, pointerEvents: style.pointerEvents });
        if (overlays.length >= 40) break;
      }
    }
    return {
      url: location.href, title: document.title, scroll: [window.scrollX, window.scrollY], viewport: [window.innerWidth, window.innerHeight], visibility: document.visibilityState,
      focused: describe(document.activeElement), overlays,
      dialogs: [...document.querySelectorAll('dialog[open], [aria-modal="true"]')].slice(0, 10).map(describe),
      inert: [...document.querySelectorAll('[inert]')].slice(0, 10).map(describe),
      alerts: [...document.querySelectorAll('[role="alert"], [role="status"]')].filter(shown).slice(0, 10).map((e) => `${describe(e)}: ${(e.textContent || '').trim().slice(0, 80)}`),
    };
  }), ms);
  return read.answered ? (read.error ? { error: read.error } : read.value) : { notAnswered: `no answer within ${ms} ms` };
}

/**
 * What a run can do that bears on the classes it cannot see, read each run and written to the job's log: whether the hardware
 * counters rr needs are there (perf stat on cycles), and whether a symbol file now exists for the Chrome for Testing build.
 * `notice` is set when either changed from what the design records, so the proof of impossibility is not one old measurement.
 */
export async function capabilities({ run, fetchHead, version, platform = 'linux64' }) {
  const result = { at: new Date().toISOString(), counters: null, symbols: null, notice: [] };
  const perf = await run('perf', ['stat', '-e', 'cycles', 'true']);
  result.counters = { available: perf.ok && !/not supported|No supported events|Permission denied/i.test(`${perf.stdout}${perf.stderr}`), text: `${perf.stdout}${perf.stderr}`.trim().slice(0, 300) };
  if (result.counters.available) result.notice.push('perf can count cycles on this runner: rr may now work here (the design records that it did not, 2026-10-20)');
  if (version && fetchHead) {
    const names = [`chrome-headless-shell-${platform}-symbols.zip`, `chrome-${platform}-symbols.zip`, `chrome-${platform}.debug`];
    result.symbols = [];
    for (const name of names) {
      const code = await fetchHead(`https://storage.googleapis.com/chrome-for-testing-public/${version}/${platform}/${name}`);
      result.symbols.push({ name, status: code });
      if (code === 200) result.notice.push(`a symbol file now exists for Chrome for Testing ${version}: ${name}`);
    }
  }
  return result;
}
