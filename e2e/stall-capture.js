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
 *   - when the page is judged stalled (it answered no evaluate, or its main
 *     thread answers no task), the renderers' native stacks (#575, #591):
 *     gdb's backtrace of every thread, the kernel's stack, wait channel
 *     and system call of every thread, and what resolves the raw offsets
 *     offline (the binary's path and build id, the load address of every
 *     module, the executable anonymous regions where JIT code lives).
 * The capture is written to the test's output directory
 * (stall-capture-<n>.json, uploaded by CI), attached to the test, and
 * summed up on stderr.
 */

import { execFile } from 'node:child_process';
import { readdirSync, readFileSync, readlinkSync, writeFileSync } from 'node:fs';

const ANSWER_MS = 5000;     // a page that takes longer to evaluate is captured
const PROBE_EVERY_MS = 2000;
const SCAN_EVERY_MS = 1000; // new contexts and pages are armed this often
const COMMAND_MS = 2000;    // how long a DevTools command is waited for
const PAUSE_MS = 3000;
const PROFILE_MS = 2000;
// a test's pages are captured this long before its timeout (a third of a shorter one)
const TIMEOUT_MARGIN_MS = 15000;

// The native stacks (#575, #591) of a page judged stalled. Every external
// command has a hard limit, so a capture never hangs the run
const GDB_SECONDS = 15;                 // `timeout` ends gdb after this (and kills it 2 s later)
const GDB_MS = (GDB_SECONDS + 2 + 3) * 1000; // node's own limit on the same command, a backstop
const INSTALL_MS = 60000;               // gdb installed on the spot, all its commands together
const HELPER_MS = 5000;                 // readelf, sudo cat, version checks
const NATIVE_MOST = 6;                  // renderers whose stacks are taken, at once
const STACK_FRAMES = 40;
const UNANSWERED = 'page did not answer';

/**
 * The longest a capture of a page that answers can take, every wait in
 * `record` and `captureArmed` run out one after another: the arming
 * waited for (1 command); the interrupting command, the task and
 * Debugger.pause (3); the pause itself (PAUSE_MS); the debugger
 * disabled, enabled and its breakpoints made inactive again (3);
 * Profiler.enable and Profiler.start (2); the profile (PROFILE_MS);
 * Profiler.stop (1). The renderers' CPU time (a session, two reads and
 * 1 s between them) is taken alongside, and is shorter.
 * 10 x 2 s + 3 s + 2 s = 25 s.
 */
export const CAPTURE_MOST_MS = 10 * COMMAND_MS + PAUSE_MS + PROFILE_MS;

/**
 * What the native stacks of a page judged stalled add, again every wait
 * run out: gdb installed on the spot (INSTALL_MS, all its commands
 * together), gdb itself (GDB_MS; the renderers' run side by side), the
 * build id and the kernel stacks (2 x HELPER_MS). 60 s + 20 s + 10 s =
 * 90 s, and a capture of a stalled page takes at most CAPTURE_MOST_MS
 * and this.
 */
export const NATIVE_MOST_MS = INSTALL_MS + GDB_MS + 2 * HELPER_MS;

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

/**
 * A page's DevTools session, made while the page still answers, with
 * the debugger enabled; `scripts` maps a script id to its URL.
 */
export async function arm(page) {
  const armed = { session: null, scripts: new Map(), error: null, pausing: false };
  if (armingOff()) {
    // the capture then says the page was not armed (`armed: false`, this reason)
    armed.error = `not armed: ${NO_ARM}=${process.env[NO_ARM]} (the debugger is never enabled)`;
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
 * never rejected: { ok, code, stdout, stderr, ms, timedOut, error }. A
 * command that outlives `ms` is killed (SIGKILL), so no capture waits on
 * one for ever.
 */
function run(command, args, ms, env) {
  return new Promise((resolve) => {
    const started = Date.now();
    try {
      execFile(command, args, { timeout: ms, killSignal: 'SIGKILL', maxBuffer: 16 * 1024 * 1024, env: { ...process.env, ...env }, encoding: 'utf8' },
        (error, stdout, stderr) => resolve({
          ok: !error,
          code: error ? (typeof error.code === 'number' ? error.code : String(error.code || error.signal || 'error')) : 0,
          stdout: stdout || '',
          stderr: stderr || '',
          ms: Date.now() - started,
          timedOut: !!(error && error.killed),
          error: error ? String(error.message || error).slice(0, 300) : undefined,
        }));
    } catch (error) {
      resolve({ ok: false, code: 'error', stdout: '', stderr: '', ms: Date.now() - started, timedOut: false, error: String(error && error.message || error).slice(0, 300) });
    }
  });
}

const isRoot = typeof process.getuid === 'function' && process.getuid() === 0;
/** A command that needs root: itself as root, else through sudo without a password prompt (the runners allow it). */
const privileged = (args) => (isRoot ? args : ['sudo', '-n', ...args]);
const runPrivileged = (args, ms, env) => { const full = privileged(args); return run(full[0], full.slice(1), ms, env); };

const cap = (text, most) => (text.length > most ? `${text.slice(0, most)}\n... (${text.length - most} more characters cut)` : text);

// gdb is put in the machine once per process: the promise of how that went
let gdbReady = null;

/**
 * gdb, found or installed on the spot. A stopgap (quire#575): the e2e jobs
 * should install it (pwa's e2e-setup action, bats-lang/pwa#109), and
 * until they do it is installed when the first page stalls, so a healthy
 * job pays nothing. `apt-get install` first (the runner image's package
 * lists), then `apt-get update` and again if that failed, all within
 * INSTALL_MS.
 */
function ensureGdb() {
  if (!gdbReady) {
    gdbReady = (async () => {
      const deadline = Date.now() + INSTALL_MS;
      const left = () => Math.max(1000, deadline - Date.now());
      const log = [];
      const have = async () => {
        const version = await run('gdb', ['--version'], HELPER_MS);
        return version.ok ? version.stdout.split('\n')[0] : null;
      };
      let version = await have();
      if (version) return { available: true, version, installed: false, log };
      const env = { DEBIAN_FRONTEND: 'noninteractive' };
      const apt = (...args) => runPrivileged(['env', 'DEBIAN_FRONTEND=noninteractive', 'apt-get', '-q', '-y', '-o', 'DPkg::Lock::Timeout=30', ...args], left(), env);
      const step = (name, outcome) => log.push({ step: name, ok: outcome.ok, code: outcome.code, ms: outcome.ms, error: outcome.error, tail: outcome.stderr.slice(-300) || outcome.stdout.slice(-300) });
      const install = await apt('install', '--no-install-recommends', 'gdb');
      step('apt-get install gdb', install);
      if (!install.ok && Date.now() < deadline) {
        step('apt-get update', await apt('update'));
        if (Date.now() < deadline) step('apt-get install gdb', await apt('install', '--no-install-recommends', 'gdb'));
      }
      version = await have();
      return { available: !!version, version, installed: !!version, log };
    })();
  }
  return gdbReady;
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
async function identity(pid) {
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
    const notes = await run('readelf', ['-n', exe], HELPER_MS);
    const id = /Build ID:\s*([0-9a-f]+)/.exec(notes.stdout);
    result.buildId = id ? id[1] : null;
    if (!id) result.buildIdError = notes.error || cap(notes.stderr || notes.stdout, 300) || 'no build id note';
  }
  return { result, maps };
}

/**
 * The kernel's view of every thread: its name, state, wait channel,
 * system call (a futex's address and operation) and stack. The stack is
 * readable by root only, so it is read through sudo when this user cannot.
 */
async function kernelTasks(pid) {
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
    const out = await runPrivileged(['tail', '-v', '-n', '+1', ...files], HELPER_MS);
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

/** gdb attached to one process, to its end or GDB_MS, then let go. */
async function backtrace(pid, maps) {
  const args = ['-k', '2', String(GDB_SECONDS), 'gdb', '-batch', '-nx', '-q',
    '-iex', 'set auto-load off', '-iex', 'set debuginfod enabled off', '-iex', 'set pagination off', '-iex', 'set confirm off',
    '-ex', 'info threads', '-ex', `thread apply all bt ${STACK_FRAMES}`, '-p', String(pid)];
  const out = await runPrivileged(['timeout', ...args], GDB_MS, { DEBUGINFOD_URLS: '' });
  const parsed = parseGdb(out.stdout, pid, maps);
  return {
    ok: out.ok,
    exitCode: out.code,
    timedOut: out.timedOut || out.code === 124 || out.code === 137,
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
 * The native stacks of these renderers (a page judged stalled: see the top
 * of this file). Nothing here throws, and every command is limited.
 */
async function nativeStacks(renderers) {
  const result = { ptraceScope: '(absent)' };
  try { result.ptraceScope = readFileSync('/proc/sys/kernel/yama/ptrace_scope', 'utf8').trim(); } catch (error) { /* no Yama: ptrace is the kernel's usual rule */ }
  result.root = isRoot;
  const gdb = await ensureGdb();
  result.gdb = { available: gdb.available, version: gdb.version, installedNow: gdb.installed, install: gdb.log };
  const taken = renderers.slice(0, NATIVE_MOST);
  result.renderers = await Promise.all(taken.map(async (renderer) => {
    // the kernel's view and the addresses first: gdb stops the process
    const { result: entry, maps } = await identity(renderer.pid);
    entry.kernel = await kernelTasks(renderer.pid);
    entry.gdbStacks = gdb.available ? await backtrace(renderer.pid, maps) : { ok: false, error: 'gdb is not installed and could not be' };
    return entry;
  }));
  return result;
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
  let stalled = reason.startsWith(UNANSWERED);
  if (session && !armed.error) {
    // An interrupting command (answered while script runs) and a task
    const interrupt = await within(session.send('Debugger.setBreakpointsActive', { active: false }), COMMAND_MS);
    const task = await within(session.send('Runtime.evaluate', { expression: '1' }), COMMAND_MS);
    result.answers = {
      interrupt: { answered: interrupt.answered, ms: interrupt.ms, error: interrupt.error },
      task: { answered: task.answered, ms: task.ms, error: task.error },
    };
    // a page whose main thread runs no task is stalled, whatever the reason of the capture
    stalled = !task.answered;
  }
  let processes = null;
  if (stalled) {
    // the native stacks first, before the pause and the profile below
    // change what the renderer does: the wait it is stuck in is the evidence
    processes = await cpu;
    if (Array.isArray(processes)) {
      result.native = await nativeStacks(processes.filter((process) => process.type === 'renderer')).catch((error) => ({ error: String(error && error.stack || error) }));
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
  result.machine = machineState();
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
      lines.push(`  native stacks: gdb ${result.native.gdb.available ? result.native.gdb.version : 'not available'}, ptrace_scope ${result.native.ptraceScope}`);
      for (const renderer of result.native.renderers) {
        const stacks = renderer.gdbStacks;
        lines.push(`  renderer ${renderer.pid}: ${renderer.exe}, build id ${renderer.buildId}, loaded at ${renderer.exeBase}; gdb ${stacks.ok ? 'ok' : `failed (${stacks.error})`}, ${stacks.threadCount || 0} threads`);
        if (stacks.mainThread) for (const frame of stacks.mainThread.frames.slice(0, 12)) lines.push(`    main thread ${frame.text}${frame.module ? ` [${frame.module}${frame.offset ? ` +${frame.offset}` : ''}]` : ''}`);
      }
    }
  }
  if (Array.isArray(result.otherProcesses)) for (const process of result.otherProcesses) {
    lines.push(`  ${process.type} ${process.pid}: CPU ${process.cpuSeconds}s over 1 s; threads: ${process.threads.join('; ')}`);
  }
  if (result.machine) {
    lines.push(`  machine: load ${result.machine.loadAverage}, ${result.machine.memoryAvailableMiB} MiB available`);
    for (const [resource, rows] of Object.entries(result.machine.pressure)) if (rows[0]) lines.push(`  pressure ${resource}: ${rows.join(' | ')}`);
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
  const captures = [];
  const starts = [];           // the pages whose capture has begun
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
      await Promise.all([...running]);
      for (const pending of armed.values()) {
        const arming = await within(pending, COMMAND_MS);
        if (arming.value && arming.value.session) arming.value.session.detach().catch(() => {});
      }
    },
  };
}
