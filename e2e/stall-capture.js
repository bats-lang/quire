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
 *     executable anonymous regions where JIT code lives).
 */

import { execFile } from 'node:child_process';
import { accessSync, constants, readdirSync, readFileSync, readlinkSync, writeFileSync } from 'node:fs';
import { delimiter, isAbsolute, join } from 'node:path';

const ANSWER_MS = 5000;     // a page that takes longer to evaluate is captured
const PROBE_EVERY_MS = 2000;
const SCAN_EVERY_MS = 1000; // new contexts and pages are armed this often
const COMMAND_MS = 2000;    // how long a DevTools command is waited for
const PAUSE_MS = 3000;
const PROFILE_MS = 2000;
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
const GDB_SECONDS = 15;                 // `timeout` ends gdb after this (and kills it 1 s later)
const GDB_MS = GDB_SECONDS * 1000 + 2000;     // node's own limit on the same command: after `timeout -k 1`, so a backstop
const HELPER_MS = 5000;                 // readelf, sudo tail, the gdb version check
const NATIVE_MOST = 6;                  // renderers whose stacks are taken, at once
const STACK_FRAMES = 40;
// stop() waits this long for captures still running (the native step can
// outlast the test); what they found by then is already written (`save`)
export const TEARDOWN_MS = 10000;
// and stop() then ends their commands (at most HELPER_MS) and waits 1.5 s more
export const TEARDOWN_MOST_MS = TEARDOWN_MS + HELPER_MS + 1500;

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
 * What the native stacks of a frozen page add, every wait run out: an
 * evaluate of an unarmed page (1 command); the renderers' CPU time awaited
 * (the browser session, two reads and CPU_WINDOW_MS: 3 commands and the
 * window, all of it counted, though it began alongside the probes above);
 * gdb's version; per renderer (side by side) readelf, `sudo tail` for the
 * kernel stacks and gdb. A capture of a frozen page takes at most
 * CAPTURE_MOST_MS and this.
 */
export const NATIVE_MOST_MS = COMMAND_MS + (3 * COMMAND_MS + CPU_WINDOW_MS) + HELPER_MS + 2 * HELPER_MS + GDB_MS;

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
 * never rejected: { ok, code, stdout, stderr, ms, timedOut, error }. It runs
 * in a process group of its own, which is killed (SIGKILL) at `ms`, so no
 * capture waits on one for ever. A command that needs root and so runs
 * through sudo is also wrapped, inside sudo, in `timeout -k` (see
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
 * A command that needs root, ended by `timeout -k 1 <seconds>` as root (so
 * the real command is killed even if sudo is not), through sudo without a
 * password prompt where this user is not root (the runners allow it).
 */
function privileged(args, ms) {
  const limited = ['timeout', '-k', '1', String(Math.max(1, Math.floor(ms / 1000) - 2)), ...args];
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
    /**
     * Ends what this watch runs: SIGTERM to each child's process group (all a
     * root user can reach through; a user that is not root cannot signal
     * sudo's group, root's), and `pkill -f` of the token that gdb's command
     * line carries, as root through sudo (so `timeout`, which forwards the
     * signal to gdb, and gdb are signalled whoever started them); SIGKILL a
     * second later. Without any of it gdb still ends by `timeout -k 1
     * GDB_SECONDS`, about 16 s after it started.
     */
    async abort() {
      this.aborted = true;
      const groups = [...this.children].map((child) => child.pid).filter(Boolean);
      for (const group of groups) { try { process.kill(-group, 'SIGTERM'); } catch (gone) { /* it ended, or it is root's */ } }
      // the pattern matches the token in gdb's command line and not pkill's own
      const pattern = `[${token[0]}]${token.slice(1)}`;
      const signal = (name) => runPrivileged(['pkill', `-${name}`, '-f', pattern], HELPER_MS);
      await signal('TERM');
      setTimeout(() => {
        for (const group of groups) { try { process.kill(-group, 'SIGKILL'); } catch (gone) { /* it ended */ } }
        signal('KILL').catch(() => {});
      }, 1000).unref();
      return groups.length;
    },
  };
}

const cap = (text, most) => (text.length > most ? `${text.slice(0, most)}\n... (${text.length - most} more characters cut)` : text);

// A path to gdb, instead of the one PATH finds (the specs' stand-in). An
// absolute path, not a PATH entry: the privileged command runs under sudo,
// whose own PATH (secure_path) is not this process's
const GDB_PATH_VARIABLE = 'QUIRE_STALL_GDB';

/** The absolute path of an executable on this process's PATH, or null. */
function whichExecutable(name) {
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
export const CANNOT_ATTACH = /ptrace: (Operation not permitted|Permission denied)|Could not attach to process|yama\/ptrace_scope|sudo: (a password is required|a terminal is required|sorry, you are not allowed)/;

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

/** gdb attached to one process, to its end or GDB_MS, then let go. */
async function backtrace(pid, maps, scope, gdbPath) {
  const args = [gdbPath, '-batch', '-nx', '-q',
    '-iex', 'set auto-load off', '-iex', 'set debuginfod enabled off', '-iex', 'set pagination off', '-iex', 'set confirm off',
    // the watch's token on the command line, so teardown can find this command by it (`abort`)
    ...(scope ? ['-iex', `echo ${scope.token}\\n`] : []),
    '-ex', 'info threads', '-ex', `thread apply all bt ${STACK_FRAMES}`, '-p', String(pid)];
  const out = await runPrivileged(args, GDB_MS, { DEBUGINFOD_URLS: '' }, scope);
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
async function nativeStacks(renderers, scope) {
  const result = { ptraceScope: '(absent)' };
  try { result.ptraceScope = readFileSync('/proc/sys/kernel/yama/ptrace_scope', 'utf8').trim(); } catch (error) { /* no Yama: ptrace is the kernel's usual rule */ }
  result.root = isRoot;
  const gdb = await findGdb(scope);
  result.gdb = gdb;
  const taken = renderers.slice(0, NATIVE_MOST);
  result.renderers = await Promise.all(taken.map(async (renderer) => {
    // the kernel's view and the addresses first: gdb stops the process
    const { result: entry, maps } = await identity(renderer.pid, scope);
    entry.kernel = await kernelTasks(renderer.pid, scope);
    entry.gdbStacks = gdb.available ? await backtrace(renderer.pid, maps, scope, gdb.path) : { ok: false, error: gdb.error };
    return entry;
  }));
  // no gdb, or none that may attach: the capture carries on without the stacks, and says so
  if (!gdb.available) result.unavailable = `native capture unavailable: ${gdb.error}`;
  else if (result.renderers.length && result.renderers.every((renderer) => !renderer.gdbStacks.ok && CANNOT_ATTACH.test(`${renderer.gdbStacks.stderr}\n${renderer.gdbStacks.text}`))) {
    result.unavailable = `native capture unavailable: gdb cannot attach (ptrace_scope ${result.ptraceScope}, root ${isRoot}): ${result.renderers[0].gdbStacks.stderr.trim().slice(0, 200)}`;
  }
  return result;
}

/** Where a page's main thread is: see the top of this file. */
export async function capture(page, armed, reason, browser, save = () => {}, scope = nativeScope()) {
  armed.capturing = true;
  try { return await captureArmed(page, armed, reason, browser, save, scope); } finally { armed.capturing = false; }
}

async function captureArmed(page, armed, reason, browser, save, scope) {
  const result = { reason, at: new Date().toISOString(), url: page.url(), armed: !armed.error, armError: armed.error };
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
        result.native = await nativeStacks(renderers, scope).catch((error) => ({ error: String(error && error.stack || error) }));
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
      if (result.native.unavailable) lines.push(`  ${result.native.unavailable}`);
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
  const scope = nativeScope(); // what they run outside node
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
    count += 1;
    const path = testInfo.outputPath(`stall-capture-${count}.json`);
    // written when the native stacks are in and again at the end, so what the
    // native step found survives a teardown that does not wait for the rest
    const save = (partial) => { try { writeFileSync(path, JSON.stringify(partial, null, 2)); } catch (error) { /* the output directory is gone: the test is over */ } };
    const result = await capture(page, armedPage, reason, browser, save, scope);
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
      for (const pending of armed.values()) {
        const arming = await within(pending, COMMAND_MS);
        if (arming.value && arming.value.session) arming.value.session.detach().catch(() => {});
      }
    },
  };
}
