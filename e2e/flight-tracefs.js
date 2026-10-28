/**
 * The kernel half of the flight recorder (#575), the part that runs as root:
 * an ftrace instance of its own, a ring buffer that overwrites its oldest
 * events, scoped to the e2e run's process tree. `flight-recorder.js` calls it
 * in-process as root, else through `sudo -n node flight-tracefs.js <op> <json>`.
 * Every op returns plain data and never throws.
 */

import { chmodSync, closeSync, createWriteStream, existsSync, mkdirSync, openSync, readdirSync, readFileSync, readSync, rmdirSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export const TRACEFS = '/sys/kernel/tracing';
// What is recorded, by what the question is: who woke whom and who slept (sched), which futex a thread waited on or woke
// and with what result (the untimed wait of #575), the signals, the processes' births and ends, and the byte traffic
// between the processes (the Mojo pipes are unix sockets and pipes, so read, write, sendmsg, recvmsg and the pollers).
// Measured on Chrome 149 (a loop of 30 page cycles): about 44,000 events a second, 3.9 s with and 3.7 s without
// Without any of the REQUIRED ones the ring cannot answer the ticket's question, so the preflight fails the job; the others are
// refinements a kernel may lack (a machine with no block device has no block events), and are reported, not fatal.
export const REQUIRED_EVENTS = [
  'syscalls/sys_enter_futex', 'syscalls/sys_exit_futex',
  'sched/sched_switch', 'sched/sched_wakeup', 'sched/sched_process_fork', 'sched/sched_process_exit',
  'signal/signal_generate',
  'syscalls/sys_enter_read', 'syscalls/sys_enter_write', 'syscalls/sys_enter_sendmsg', 'syscalls/sys_enter_recvmsg',
  'syscalls/sys_enter_epoll_pwait',
];
export const OPTIONAL_EVENTS = [
  'sched/sched_process_exec', 'syscalls/sys_enter_poll', 'syscalls/sys_enter_ppoll', 'syscalls/sys_enter_eventfd2',
  // the disk: when a request was issued and when it completed (an I/O stall is the gap between the two)
  'block/block_rq_issue', 'block/block_rq_complete',
  // the kernel's own choice of a process to kill for want of memory (the OOM killer): which, and why
  'oom/mark_victim',
];
export const EVENTS = [...REQUIRED_EVENTS, ...OPTIONAL_EVENTS];
export const BUFFER_KB = 65536; // for each CPU: 4 CPUs hold about 100 s at the measured rate
// the whole ring, not its tail: a wait that began before the tail would be lost (the CI run of a futex capture kept 1.5 of 2.1 million lines)
export const LINES_KEPT = 12000000;

const attempt = (what, action) => { try { return action(); } catch (error) { return `${what}: ${String((error && error.code) || (error && error.message) || error)}`; } };

// Who holds the ring paused (a capture reading it): one file for each holder in the run's output directory, named `ring-kept-<holder>`,
// written (the time and the holder, as its content: no file time is read) before the ring is paused and taken down after the last
// reader is done; the ring records again when no holder is left. Keyword: ring hold.
export const HOLD_PREFIX = 'ring-kept-';

/** The holders of the ring in `dir`: [{ holder, at }] (at: the time the file says, in ms, NaN when unreadable). */
export function holdersIn(dir) {
  if (!dir) return [];
  try {
    return readdirSync(dir).filter((name) => name.startsWith(HOLD_PREFIX)).map((name) => {
      let at = Number.NaN;
      try { at = Date.parse(readFileSync(`${dir}/${name}`, 'utf8').split(/\s/)[0]); } catch (gone) { /* it was taken down meanwhile */ }
      return { holder: name.slice(HOLD_PREFIX.length), at };
    });
  } catch (error) { return []; }
}

export function hold({ dir, holder }) { if (dir) attempt('hold', () => writeFileSync(`${dir}/${HOLD_PREFIX}${holder}`, `${new Date().toISOString()} ${holder}\n`)); return { held: true }; }

// The two sequences that decide whether the ring records are each one step to the other captures: a hold (the file, then the pause) and a
// release (the file down, who is left, then the resume). Without a lock a capture that wrote its hold and paused between another's look at
// the directory (empty) and its resume had its ring switched back on while `tail` read it (a ring read as it records never ends).
// A lock file made with `wx` (the time as its content, no file time is read) serialises them; the critical sections take milliseconds,
// so a lock older than LOCK_STALE_MS is a dead holder's and is taken over. A lock that cannot be had in LOCK_MOST_MS is not waited for any
// longer: the action runs without it (a capture is worth more than none) and the failure is a record, `ring-lock-failed-*` in the output
// directory and a line on stderr, which the run's monitor and the job's check turn into `EVIDENCE MISSING: ring lock`. Keyword: ring lock.
// A lock whose content is not a time (empty after a write that hit ENOSPC, or text) is a dead holder's too: it is taken over once it has
// been seen as the same unreadable lock (same file, same content) for LOCK_UNREADABLE_MS, a window measured against a live holder's write
// (ring lock, unreadable lock; #844; the measurement and the research are in .claude/rules/e2e.md).
export const LOCK_NAME = 'ring-lock';
export const LOCK_STALE_MS = 2000;
export const LOCK_MOST_MS = 5000;
export const LOCK_UNREADABLE_MS = 500;
export const LOCK_FAILED_PREFIX = 'ring-lock-failed-';
// Which lock a read was of: its inode, the nanosecond its file was born and its content. An inode number is reused at once by tmpfs and ext4,
// so a lock re-created in a removed lock's place has the same inode and, while it is still empty, the same content; its birth is new.
// The birth is only compared for equality, never against the clock (ring lock, unreadable lock; #870).
const lockIdentity = (path) => { const found = statSync(path, { bigint: true }); return `${found.ino}:${found.birthtimeNs}:${readFileSync(path, 'utf8')}`; };
const nap = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

/** The records of locks that were not had: [{ name, text }], in the output directory `dir`. */
export function lockFailuresIn(dir) {
  if (!dir) return [];
  try {
    return readdirSync(dir).filter((name) => name.startsWith(LOCK_FAILED_PREFIX)).map((name) => {
      let text = '';
      try { text = readFileSync(`${dir}/${name}`, 'utf8').trim(); } catch (gone) { /* taken down meanwhile */ }
      return { name, text };
    });
  } catch (error) { return []; }
}

/**
 * Runs `action` while holding the ring's lock in `dir` (no lock without a directory), and answers what it answers. `most` and `stale` (ms) are
 * the limits, the constants above unless a test shortens them. A lock not had within `most` leaves a record (see above) and the action runs.
 */
export function withRingLock(dir, action, { most = LOCK_MOST_MS, stale = LOCK_STALE_MS } = {}) {
  if (!dir) return action();
  const path = `${dir}/${LOCK_NAME}`;
  const begun = Date.now();
  let locked = false;
  let holder = '';
  let unreadableSince = 0; // when the unreadable lock named by `unreadableSeen` was first seen
  let unreadableSeen = null;
  while (!locked && Date.now() - begun < most) {
    try { writeFileSync(path, `${new Date().toISOString()} ${process.pid}\n`, { flag: 'wx' }); locked = true; } catch (error) {
      if (!error || error.code !== 'EEXIST') break; // the directory is gone: nothing to take turns over
      let at = Number.NaN;
      let seen = null; // which lock this read was of (lockIdentity); null when the lock is gone
      try { seen = lockIdentity(path); holder = readFileSync(path, 'utf8').trim(); at = Date.parse(holder.split(/\s/)[0]); } catch (gone) { /* it was given back meanwhile */ }
      // ring lock: unreadable lock. The timer belongs to one observed lock: a lock that is gone, valid, or another file or content restarts it
      if (seen === null || !Number.isNaN(at)) { unreadableSince = 0; unreadableSeen = null; } else if (seen !== unreadableSeen) { unreadableSince = Date.now(); unreadableSeen = seen; }
      const unreadable = seen !== null && Number.isNaN(at);
      let dead = unreadable ? Date.now() - unreadableSince >= LOCK_UNREADABLE_MS : seen !== null && Date.now() - at > stale;
      // looked at once more just before it is taken down, so a lock replaced since the read is not the one unlinked
      if (dead) { try { dead = lockIdentity(path) === seen; } catch (gone) { dead = false; } }
      if (dead) attempt('unlock', () => unlinkSync(path));
      else nap(2);
    }
  }
  if (!locked) {
    const text = `${new Date().toISOString()} process ${process.pid} did not get the ring lock in ${Date.now() - begun} ms (limit ${most} ms; the lock said: ${holder || 'nothing readable'}); its action ran without the lock, so a ring it paused or resumed may have crossed another capture's`;
    attempt('lock-failed', () => writeFileSync(`${dir}/${LOCK_FAILED_PREFIX}${process.pid}-${Date.now()}`, `${text}\n`));
    console.error(`[ring lock] ${text}`);
  }
  try { return action(); } finally { if (locked) attempt('unlock', () => unlinkSync(path)); }
}

/** The start of a hold: the holder's file, then the ring paused, as one step to the other holders. */
export function holdAndPause({ instance, dir, holder }) {
  return withRingLock(dir, () => { hold({ dir, holder }); return pause({ instance }); });
}

/**
 * The end of a hold, on every outcome of a capture (a snapshot that failed, a crash, a freeze, a pass): the holder's file goes down
 * first, then the ring records again unless another holder is still reading it (the last one out resumes it, whichever it is).
 * Without a directory there are no holders to ask and the ring records again.
 */
export function release({ instance, dir, holder }) {
  return withRingLock(dir, () => {
    if (dir) attempt('unhold', () => unlinkSync(`${dir}/${HOLD_PREFIX}${holder}`));
    const others = holdersIn(dir).map((each) => each.holder);
    if (others.length) return { released: true, resumed: false, others };
    return { released: true, ...resume({ instance }), others };
  });
}

/** Makes the instance and starts it for the process tree of `pid`; { instance, skipped } or { error }. */
export function start({ tracefs = TRACEFS, name, pid, bufferKb = BUFFER_KB, events = EVENTS, alsoRequired = [] }) {
  const instance = `${tracefs}/instances/${name}`;
  try {
    if (!existsSync(`${tracefs}/instances`)) return { error: 'no tracefs instances directory (tracefs is not mounted here; tracefs is mounted per boot, and a restarted container may lack it: as root run `grep -q tracefs /proc/mounts || mount -t tracefs nodev /sys/kernel/tracing`, the allowed command (.claude/settings.json), then run again)' };
    mkdirSync(instance);
  } catch (error) { return { error: `cannot make ${instance}: ${(error && error.code) || error}` }; }
  const skipped = [];
  const missing = [];
  const set = (file, value) => { const bad = attempt(file, () => writeFileSync(`${instance}/${file}`, String(value))); if (bad) { skipped.push(bad); if ([...REQUIRED_EVENTS, ...alsoRequired].some((event) => file === `events/${event}/enable`) || ['buffer_size_kb', 'trace_clock', 'set_event_pid', 'tracing_on'].includes(file)) missing.push(bad); } };
  set('buffer_size_kb', bufferKb);
  // the same clock as Chrome's trace events (CLOCK_MONOTONIC), so the two records line up
  set('trace_clock', 'mono');
  for (const event of [...events, ...alsoRequired]) set(`events/${event}/enable`, 1);
  set('options/event-fork', 1);
  set('set_event_pid', pid);
  set('tracing_on', 1);
  return { instance, skipped, missing };
}

/** Stops recording (the ring keeps what it holds). */
export function pause({ instance }) {
  const bad = attempt('tracing_on', () => writeFileSync(`${instance}/tracing_on`, '0'));
  return bad ? { error: bad } : { paused: true };
}

const RING_STAMP = /^\s*.+-\d+\s+\[\d+\]\s+\S+\s+(\d+\.\d+):/;

/**
 * Writes the last `lines` lines of the record, gzipped, to `out` (a file anyone can read). tail and gzip do the bulk: the kernel formats the text,
 * and a ring of 600 MB must not pass through node's lines. The ring is held paused while it is read and released on every outcome (`holder` in `dir`,
 * see the ring hold above): a record leaves the ring recording again, whether it was written or not. Answers `lastAt`, the time (CLOCK_MONOTONIC, seconds) of the
 * last event in the file, and `others`, the holders that already held the ring when this one began (events between their pause and this one are not in it).
 */
export async function snapshot({ instance, out, lines = LINES_KEPT, dir, holder = `snapshot-${process.pid}` }) {
  const others = holdersIn(dir).map((each) => each.holder).filter((each) => each !== holder);
  // the readers of the ring and the file they write: ended on every outcome. A file that cannot be written (a directory that is gone) left tail and gzip
  // blocked on pipes nobody read, holding the caller's stderr, so the root call ran its whole limit (ROOT_MS, 60 s; CI's 'lost' capture). Keyword: ring readers.
  let tail = null;
  let gzip = null;
  let sink = null;
  try {
    // the ring is paused while it is read (a ring read as it records never reaches its end: tail ran for an hour on 44,000 events a second)
    holdAndPause({ instance, dir, holder });
    let header = '';
    const descriptor = openSync(`${instance}/trace`, 'r');
    try {
      const chunk = Buffer.alloc(4096);
      const got = readSync(descriptor, chunk, 0, 4096, null);
      header = chunk.toString('utf8', 0, got).split('\n').find((line) => line.includes('entries-in-buffer')) || '';
    } finally { closeSync(descriptor); }
    const clock = (readFileSync(`${instance}/trace_clock`, 'utf8').match(/\[(\w+)\]/) || [])[1] || 'unknown';
    sink = createWriteStream(out);
    const finished = new Promise((resolve, reject) => { sink.on('finish', resolve); sink.on('error', reject); });
    gzip = spawn('gzip', ['-1'], { stdio: ['pipe', 'pipe', 'inherit'] });
    gzip.stdin.on('error', () => {}); // a gzip ended on purpose (the finally below) is written to no more
    gzip.stdout.pipe(sink);
    gzip.stdin.write(`${header}\n# the last ${lines} lines at most; clock: ${clock}\n`);
    tail = spawn('tail', ['-n', String(lines), `${instance}/trace`], { stdio: ['ignore', 'pipe', 'inherit'] });
    // the end of the text passes by here: the last event's time says whether the file reaches as far as the red
    let end = Buffer.alloc(0);
    tail.stdout.on('data', (piece) => { end = Buffer.concat([end, piece]).subarray(-16384); });
    tail.stdout.pipe(gzip.stdin);
    const ended = (child) => new Promise((resolve) => child.on('close', (code) => resolve(code)));
    const codes = await Promise.all([ended(tail), ended(gzip), finished]);
    chmodSync(out, 0o644);
    if (codes[0] !== 0 || codes[1] !== 0) return { error: `tail exited ${codes[0]}, gzip exited ${codes[1]}`, others };
    const counts = header.match(/entries-in-buffer\/entries-written: (\d+)\/(\d+)/);
    const inBuffer = counts ? Number(counts[1]) : 0;
    const stamps = end.toString('utf8').split('\n').map((line) => RING_STAMP.exec(line)).filter(Boolean);
    return { file: out, lines: Math.min(lines, inBuffer), seen: counts ? Number(counts[2]) : 0, header, lastAt: stamps.length ? Number(stamps[stamps.length - 1][1]) : null, others };
  } catch (error) { return { error: String((error && error.stack) || error), others }; } finally {
    for (const child of [tail, gzip]) { if (child && child.exitCode === null && child.signalCode === null) attempt('kill', () => child.kill('SIGKILL')); }
    if (sink) sink.destroy();
    release({ instance, dir, holder });
  }
}

/** Stops the instance and removes it. */
export function stop({ instance }) {
  pause({ instance });
  const bad = attempt('rmdir', () => rmdirSync(instance));
  return bad ? { error: bad } : { removed: true };
}

/** `length` bytes of process `pid`'s memory at `address` (a hex string): what a futex word and its neighbours hold. */
export function readmem({ pid, address, length = 64 }) {
  let descriptor;
  try {
    descriptor = openSync(`/proc/${pid}/mem`, 'r');
    const buffer = Buffer.alloc(length);
    const got = readSync(descriptor, buffer, 0, length, BigInt(address));
    return { address, bytes: buffer.subarray(0, got).toString('hex') };
  } catch (error) { return { address, error: String((error && error.code) || (error && error.message) || error) }; } finally { if (descriptor !== undefined) closeSync(descriptor); }
}

/** How many events the ring has taken so far, and whether it records: the heartbeat's reading. { on, written } or { error }. */
export function stats({ instance }) {
  try {
    const on = readFileSync(`${instance}/tracing_on`, 'utf8').trim();
    let written = 0;
    for (const cpu of readdirSync(`${instance}/per_cpu`)) {
      const text = readFileSync(`${instance}/per_cpu/${cpu}/stats`, 'utf8');
      written += Number((/^entries: (\d+)/m.exec(text) || [0, 0])[1]) + Number((/^overrun: (\d+)/m.exec(text) || [0, 0])[1]);
    }
    return { on, written };
  } catch (error) { return { error: String((error && error.code) || (error && error.message) || error) }; }
}

/** Stops the instance taking events while it stays on (every event disabled): what the monitor's idle-ring check is shown against. A test's. */
export function silence({ instance }) {
  const bad = attempt('set_event', () => writeFileSync(`${instance}/set_event`, ''));
  return bad ? { error: bad } : { silenced: true };
}

/** Starts recording again after a pause. */
export function resume({ instance }) {
  const bad = attempt('tracing_on', () => writeFileSync(`${instance}/tracing_on`, '1'));
  return bad ? { error: bad } : { resumed: true };
}

/** Whether the ring is recording: { on: '1' | '0' }. */
export function state({ instance }) {
  try { return { on: readFileSync(`${instance}/tracing_on`, 'utf8').trim() }; } catch (error) { return { error: String((error && error.code) || error) }; }
}

const ops = { start, pause, snapshot, stop, readmem, resume, release, hold, holdAndPause, state, stats, silence };

// `sudo -n node flight-tracefs.js <op> <json>`: the answer is one line of JSON
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [op, json] = process.argv.slice(2);
  Promise.resolve(ops[op] ? ops[op](JSON.parse(json || '{}')) : { error: `no such op: ${op}` })
    .then((answer) => process.stdout.write(`${JSON.stringify(answer)}\n`))
    .catch((error) => process.stdout.write(`${JSON.stringify({ error: String(error) })}\n`));
}
