/**
 * The kernel half of the flight recorder (#575), the part that runs as root:
 * an ftrace instance of its own, a ring buffer that overwrites its oldest
 * events, scoped to the e2e run's process tree. `flight-recorder.js` calls it
 * in-process as root, else through `sudo -n node flight-tracefs.js <op> <json>`.
 * Every op returns plain data and never throws.
 */

import { constants, chmodSync, closeSync, createReadStream, createWriteStream, existsSync, mkdirSync, openSync, readdirSync, readFileSync, readSync, renameSync, rmdirSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { once } from 'node:events';
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

// the snapshot file is opened for writing and never made (O_WRONLY, no O_CREAT): a kernel without it answers ENOENT, and a stand-in directory gets no stray file
const writeSnapshotFile = (instance, value) => writeFileSync(`${instance}/snapshot`, value, { flag: constants.O_WRONLY });
const attempt = (what, action) => { try { return action(); } catch (error) { return `${what}: ${String((error && error.code) || (error && error.message) || error)}`; } };

// The ring is never stopped for a capture (#910; keyword: ring snapshot). A capture asks tracefs for a snapshot of the running ring
// (the `snapshot` file of the instance, "to take a snapshot of the current running trace", the kernel's documentation; LTTng's snapshot
// mode is the same design for a flight recorder) and reads that; every worker goes on recording into the live ring meanwhile. The snapshot
// is one buffer for the instance, so a capture takes it and reads it under the ring lock below. The swap leaves the live ring empty, so what
// a capture read is kept as a segment (`ring-segment-<seq>-<events>.gz`) in the output directory and the next capture's file begins with the
// segments before it: a wait that began before an earlier capture is in the later capture's file (the whole ring, up to LINES_KEPT events).

// The lock: the sequence of a capture (the swap, the read of the snapshot into the file and the segment, the clearing of the snapshot) is one step to
// the other captures, because there is one snapshot buffer: a second swap while the first is read would swap the unread snapshot back into the
// live ring. A lock file made with `wx` (the time as its content, no file time is read) serialises them. A capture reads for seconds, so its
// holder renews the lock's time every LOCK_RENEW_MS while it works; a lock older than LOCK_STALE_MS is a dead holder's and is taken over. A lock
// that cannot be had in LOCK_MOST_MS is not waited for any longer: the action runs without it (a capture is worth more than none) and the failure
// is a record, `ring-lock-failed-*` in the output directory and a line on stderr, which the run's monitor and the job's check turn into
// `EVIDENCE MISSING: ring lock`. LOCK_MOST_MS is under the 60 s that the sudo call of a capture lives (ROOT_MS in flight-recorder.js) and over the
// seconds that two captures take one after the other (13 s for a ring of 12,000,000 lines, quire#910). Keyword: ring lock.
// A lock whose content is not a time (empty after a write that hit ENOSPC, or text) is a dead holder's too: it is taken over once it has
// been seen as the same unreadable lock (same file, same content) for LOCK_UNREADABLE_MS, a window measured against a live holder's write
// (ring lock, unreadable lock; #844; the measurement and the research are in .claude/rules/e2e.md).
export const LOCK_NAME = 'ring-lock';
export const LOCK_STALE_MS = 2000;
export const LOCK_MOST_MS = 40000;
export const LOCK_RENEW_MS = 200;
export const LOCK_UNREADABLE_MS = 500;
export const LOCK_FAILED_PREFIX = 'ring-lock-failed-';
// Which lock a read was of: its inode, the nanosecond its file was born and its content. An inode number is reused at once by tmpfs and ext4,
// so a lock re-created in a removed lock's place has the same inode and, while it is still empty, the same content; its birth is new.
// The birth is only compared for equality, never against the clock (ring lock, unreadable lock; #870).
const lockIdentity = (path) => { const found = statSync(path, { bigint: true }); return `${found.ino}:${found.birthtimeNs}:${readFileSync(path, 'utf8')}`; };
const nap = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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
 * One try at the lock: 'taken', 'again' (a dead holder's lock was taken down: try at once), 'wait' (a live holder has it) or 'gone' (the
 * directory is gone: nothing to take turns over). `state` is the waiter's memory across tries: the text of the lock it saw last (`holder`) and
 * the unreadable lock whose window is running.
 */
function tryLock(path, state, stale) {
  try { writeFileSync(path, `${new Date().toISOString()} ${process.pid}\n`, { flag: 'wx' }); return 'taken'; } catch (error) {
    if (!error || error.code !== 'EEXIST') return 'gone';
    let at = Number.NaN;
    let seen = null; // which lock this read was of (lockIdentity); null when the lock is gone
    try { seen = lockIdentity(path); state.holder = readFileSync(path, 'utf8').trim(); at = Date.parse(state.holder.split(/\s/)[0]); } catch (gone) { /* it was given back meanwhile */ }
    // ring lock: unreadable lock. The timer belongs to one observed lock: a lock that is gone, valid, or another file or content restarts it
    if (seen === null || !Number.isNaN(at)) { state.unreadableSince = 0; state.unreadableSeen = null; } else if (seen !== state.unreadableSeen) { state.unreadableSince = Date.now(); state.unreadableSeen = seen; }
    const unreadable = seen !== null && Number.isNaN(at);
    let dead = unreadable ? Date.now() - state.unreadableSince >= LOCK_UNREADABLE_MS : seen !== null && Date.now() - at > stale;
    // looked at once more just before it is taken down, so a lock replaced since the read is not the one unlinked
    if (dead) { try { dead = lockIdentity(path) === seen; } catch (gone) { dead = false; } }
    if (dead) { attempt('unlock', () => unlinkSync(path)); return 'again'; }
    return 'wait';
  }
}

const freshState = () => ({ holder: '', unreadableSince: 0, unreadableSeen: null });

/** The record and the line of a lock that was not had. */
function lockFailed(dir, begun, most, state) {
  const text = `${new Date().toISOString()} process ${process.pid} did not get the ring lock in ${Date.now() - begun} ms (limit ${most} ms; the lock said: ${state.holder || 'nothing readable'}); its action ran without the lock, so its swap of the snapshot may have crossed another capture's read`;
  attempt('lock-failed', () => writeFileSync(`${dir}/${LOCK_FAILED_PREFIX}${process.pid}-${Date.now()}`, `${text}\n`));
  console.error(`[ring lock] ${text}`);
}

/**
 * Runs `action` while holding the ring's lock in `dir` (no lock without a directory), and answers what it answers. `most` and `stale` (ms) are
 * the limits, the constants above unless a test shortens them. A lock not had within `most` leaves a record (see above) and the action runs.
 * The action is synchronous; a capture, which waits for the processes that read the ring, uses `withRingLockAsync`.
 */
export function withRingLock(dir, action, { most = LOCK_MOST_MS, stale = LOCK_STALE_MS } = {}) {
  if (!dir) return action();
  const path = `${dir}/${LOCK_NAME}`;
  const begun = Date.now();
  const state = freshState();
  let locked = false;
  while (!locked && Date.now() - begun < most) {
    const step = tryLock(path, state, stale);
    if (step === 'taken') locked = true;
    else if (step === 'gone') break;
    else if (step === 'wait') nap(2);
  }
  if (!locked) lockFailed(dir, begun, most, state);
  try { return action(); } finally { if (locked) attempt('unlock', () => unlinkSync(path)); }
}

/**
 * `withRingLock` for an action that is a promise: the waiter waits on a timer, so the process it is in (the watchdog, which beats on a timer of its
 * own) keeps running, and the holder renews the lock's time every LOCK_RENEW_MS while the action runs, so a read of seconds is not a dead holder's.
 * The renewal writes only a lock that is still its own (the pid it holds is in the text).
 */
export async function withRingLockAsync(dir, action, { most = LOCK_MOST_MS, stale = LOCK_STALE_MS } = {}) {
  if (!dir) return action();
  const path = `${dir}/${LOCK_NAME}`;
  const begun = Date.now();
  const state = freshState();
  let locked = false;
  while (!locked && Date.now() - begun < most) {
    const step = tryLock(path, state, stale);
    if (step === 'taken') locked = true;
    else if (step === 'gone') break;
    else if (step === 'wait') await sleep(2);
  }
  if (!locked) lockFailed(dir, begun, most, state);
  const renewing = locked ? setInterval(() => attempt('renew', () => {
    if (readFileSync(path, 'utf8').trim().endsWith(` ${process.pid}`)) writeFileSync(path, `${new Date().toISOString()} ${process.pid}\n`);
  }), LOCK_RENEW_MS) : null;
  try { return await action(); } finally {
    if (renewing) clearInterval(renewing);
    if (locked) attempt('unlock', () => unlinkSync(path));
  }
}

/** Makes the instance and starts it for the process tree of `pid`; { instance, skipped } or { error }. */
export function start({ tracefs = TRACEFS, name, pid, bufferKb = BUFFER_KB, events = EVENTS, alsoRequired = [] }) {
  const instance = `${tracefs}/instances/${name}`;
  try {
    if (!existsSync(`${tracefs}/instances`)) return { error: 'no tracefs instances directory (tracefs is not mounted here; tracefs is mounted per boot, and a restarted container may lack it: as root run `grep -q tracefs /proc/mounts || mount -t tracefs nodev /sys/kernel/tracing`, the allowed command, then run again)' };
    mkdirSync(instance);
  } catch (error) { return { error: `cannot make ${instance}: ${(error && error.code) || error}` }; }
  const skipped = [];
  const missing = [];
  const set = (file, value) => { const bad = attempt(file, () => writeFileSync(`${instance}/${file}`, String(value))); if (bad) { skipped.push(bad); if ([...REQUIRED_EVENTS, ...alsoRequired].some((event) => file === `events/${event}/enable`) || ['buffer_size_kb', 'trace_clock', 'set_event_pid', 'tracing_on'].includes(file)) missing.push(bad); } };
  set('buffer_size_kb', bufferKb);
  // The snapshot buffer, made now at the ring's size (a capture's swap then needs no memory) and before any event is on, so the swap that allocates it
  // exchanges two empty buffers. A kernel with no `snapshot` file (built without CONFIG_TRACER_SNAPSHOT) cannot give a capture without stopping the
  // ring, so the preflight fails on it: `snapshot` answers { available, why } (capabilities.json records it). Keyword: ring snapshot.
  const probe = attempt('snapshot', () => writeSnapshotFile(instance, '1'));
  const snapshotProbe = probe ? { available: false, why: probe.endsWith('ENOENT') ? 'the instance has no snapshot file: the kernel is built without CONFIG_TRACER_SNAPSHOT' : probe.replace(/^snapshot: /, '') } : { available: true };
  // the same clock as Chrome's trace events (CLOCK_MONOTONIC), so the two records line up
  set('trace_clock', 'mono');
  for (const event of [...events, ...alsoRequired]) set(`events/${event}/enable`, 1);
  set('options/event-fork', 1);
  set('set_event_pid', pid);
  set('tracing_on', 1);
  return { instance, skipped, missing, snapshot: snapshotProbe };
}

/** Stops recording (the ring keeps what it holds). Not a capture's step: the cost measurement before the tests, and the specs that break a ring on purpose. */
export function pause({ instance }) {
  const bad = attempt('tracing_on', () => writeFileSync(`${instance}/tracing_on`, '0'));
  return bad ? { error: bad } : { paused: true };
}

const RING_STAMP = /^\s*.+-\d+\s+\[\d+\]\s+\S+\s+(\d+\.\d+):/;

/** Takes the snapshot: the live ring and the snapshot buffer exchange places (tracefs `snapshot`, 1). Answers { swapped } or { error }. */
export function takeSnapshot({ instance }) {
  const bad = attempt('snapshot', () => writeSnapshotFile(instance, '1'));
  return bad ? { error: bad } : { swapped: true };
}

/** Empties the snapshot buffer (tracefs `snapshot`, 2), so the next swap leaves the live ring empty. Answers { cleared } or { error }. */
export function clearSnapshot({ instance }) {
  const bad = attempt('snapshot', () => writeSnapshotFile(instance, '2'));
  return bad ? { error: bad } : { cleared: true };
}

// A segment is the events a swap took out of the live ring: `ring-segment-<seq>-<events>.gz` (gzip), its sequence number rising by one for each swap
// and the events it holds in its name, so the segments to keep are chosen without reading them. The file being written is `ring-segment-<seq>.tmp`.
const SEGMENT_NAME = /^ring-segment-(\d+)-(\d+)\.gz$/;
const SEGMENT_TEMPORARY = /^ring-segment-\d+\.tmp$/;

/** The segments in `dir`, the oldest first: [{ name, seq, events }]. */
export function segmentsIn(dir) {
  if (!dir) return [];
  try {
    return readdirSync(dir).map((name) => ({ name, found: SEGMENT_NAME.exec(name) })).filter((each) => each.found)
      .map((each) => ({ name: each.name, seq: Number(each.found[1]), events: Number(each.found[2]) })).sort((a, b) => a.seq - b.seq);
  } catch (error) { return []; }
}

/** The newest segments that together hold at most `budget` events, in order, oldest first (a segment too large for the budget ends the choice). */
function newestWithin(segments, budget) {
  const chosen = [];
  let total = 0;
  for (let at = segments.length - 1; at >= 0; at -= 1) {
    if (total + segments[at].events > budget) break;
    total += segments[at].events;
    chosen.unshift(segments[at]);
  }
  return chosen;
}

const closed = (stream) => new Promise((resolve, reject) => { stream.once('finish', resolve); stream.once('error', reject); });
const ended = (child) => new Promise((resolve) => child.on('close', (code) => resolve(code)));

/** Writes the bytes of `file` into `sink`, waiting for it when it is full (a sink that is a pipe nobody reads yet holds this up, as it should). */
async function copyInto(file, sink) {
  for await (const chunk of createReadStream(file)) { if (!sink.write(chunk)) await once(sink, 'drain'); }
}

/**
 * Writes the record of the ring, gzipped, to `out` (a file anyone can read): the segments of the captures before this one, then the snapshot this
 * capture takes. The ring is never stopped: the snapshot is a swap of the live ring with the snapshot buffer (tracefs `snapshot`), taken and read under
 * the ring lock (see above; `dir` is the lock's directory and the segments'). cat and gzip do the bulk: the kernel formats the text, and a ring of
 * 600 MB must not pass through node's lines. The snapshot is kept as a segment for the next capture; the segments before it are chosen up to `lines`
 * events (the whole ring, not its tail: a wait that began before the tail would be lost). Answers `lastAt`, the time (CLOCK_MONOTONIC, seconds) of the
 * last event in the file, `lines` (the events in it), `seen` (the events the ring had written) and `segments` (how many earlier captures' it begins with).
 * `lockMost` is the lock's patience (ms). `swap` and `clear` are the kernel's two steps, a test's stand-in where there is no snapshot.
 */
export async function snapshot({ instance, out, lines = LINES_KEPT, dir, lockMost = LOCK_MOST_MS, swap = takeSnapshot, clear = clearSnapshot }) {
  return withRingLockAsync(dir, () => capture({ instance, out, lines, dir, swap, clear }), { most: lockMost });
}

async function capture({ instance, out, lines, dir, swap, clear }) {
  // the readers of the ring and the files they write: ended on every outcome. A file that cannot be written (a directory that is gone) left cat and gzip
  // blocked on pipes nobody read, holding the caller's stderr, so the root call ran its whole limit (ROOT_MS, 60 s; CI's 'lost' capture). Keyword: ring readers.
  let reader = null;
  let gzip = null;
  let sink = null;
  let tee = null;
  let temporary = null;
  try {
    const swapped = swap({ instance });
    if (swapped.error) return { error: swapped.error }; // nothing was taken; the live ring is as it was
    let header = '';
    const descriptor = openSync(`${instance}/snapshot`, 'r');
    try {
      const chunk = Buffer.alloc(4096);
      const got = readSync(descriptor, chunk, 0, 4096, null);
      header = chunk.toString('utf8', 0, got).split('\n').find((line) => line.includes('entries-in-buffer')) || '';
    } finally { closeSync(descriptor); }
    const counts = header.match(/entries-in-buffer\/entries-written: (\d+)\/(\d+)/);
    const inSnapshot = counts ? Number(counts[1]) : 0;
    const clock = (readFileSync(`${instance}/trace_clock`, 'utf8').match(/\[(\w+)\]/) || [])[1] || 'unknown';
    const before = segmentsIn(dir);
    const earlier = newestWithin(before, Math.max(0, lines - inSnapshot));
    const seq = before.length ? before[before.length - 1].seq + 1 : 1;
    // the segment of this snapshot is made first, so the snapshot's swap is known by its file (a test that reads while a capture is held reads it so)
    if (dir) { temporary = `${dir}/ring-segment-${seq}.tmp`; tee = createWriteStream(temporary); }
    const teeClosed = tee ? closed(tee) : Promise.resolve();
    sink = createWriteStream(out);
    const sinkClosed = closed(sink);
    for (const segment of earlier) await copyInto(`${dir}/${segment.name}`, sink);
    gzip = spawn('gzip', ['-1'], { stdio: ['pipe', 'pipe', 'inherit'] });
    gzip.stdin.on('error', () => {}); // a gzip ended on purpose (the finally below) is written to no more
    gzip.stdout.pipe(sink, { end: false });
    if (tee) gzip.stdout.pipe(tee, { end: false });
    gzip.stdin.write(`${header}\n# the snapshot of the ring taken for this capture, after ${earlier.length} earlier ones; clock: ${clock}\n`);
    reader = spawn('cat', [`${instance}/snapshot`], { stdio: ['ignore', 'pipe', 'inherit'] });
    // the end of the text passes by here: the last event's time says whether the file reaches as far as the red
    let end = Buffer.alloc(0);
    reader.stdout.on('data', (piece) => { end = Buffer.concat([end, piece]).subarray(-16384); });
    reader.stdout.pipe(gzip.stdin);
    // a sink or a segment that cannot be written ends the wait at once (the finally ends the readers)
    const codes = await Promise.race([Promise.all([ended(reader), ended(gzip)]), sinkClosed.then(() => new Promise(() => {})), teeClosed.then(() => new Promise(() => {}))]);
    if (codes[0] !== 0 || codes[1] !== 0) return { error: `cat exited ${codes[0]}, gzip exited ${codes[1]}` };
    if (tee) tee.end();
    sink.end();
    await Promise.all([sinkClosed, teeClosed]);
    chmodSync(out, 0o644);
    const name = `ring-segment-${seq}-${inSnapshot}.gz`;
    if (dir) { renameSync(temporary, `${dir}/${name}`); temporary = null; chmodSync(`${dir}/${name}`, 0o644); }
    // read in full: the snapshot buffer is emptied, so the next swap leaves the live ring empty (a snapshot that was not read in full is swapped back
    // into the live ring by the next one, and is in that capture's file)
    const cleared = clear({ instance });
    // the segments no later capture will begin with go: the newest ones that fit `lines`, and this one whatever its size
    const all = segmentsIn(dir);
    const keep = new Set(newestWithin(all, lines).map((each) => each.name));
    for (const old of all.slice(0, -1)) { if (!keep.has(old.name)) attempt('prune', () => unlinkSync(`${dir}/${old.name}`)); }
    const stamps = end.toString('utf8').split('\n').map((line) => RING_STAMP.exec(line)).filter(Boolean);
    const total = earlier.reduce((sum, each) => sum + each.events, 0) + inSnapshot;
    return { file: out, lines: total, seen: counts ? Number(counts[2]) : 0, header, lastAt: stamps.length ? Number(stamps[stamps.length - 1][1]) : null, segments: earlier.length, ...(cleared.error ? { clearError: cleared.error } : {}) };
  } catch (error) { return { error: String((error && error.stack) || error) }; } finally {
    for (const child of [reader, gzip]) { if (child && child.exitCode === null && child.signalCode === null) attempt('kill', () => child.kill('SIGKILL')); }
    for (const stream of [sink, tee]) { if (stream) stream.destroy(); }
    if (temporary) attempt('unlink', () => unlinkSync(temporary));
  }
}

/** Stops the instance and removes it, and the segments of the captures in `dir` (their ring is gone). */
export function stop({ instance, dir }) {
  pause({ instance });
  for (const each of segmentsIn(dir)) attempt('segment', () => unlinkSync(`${dir}/${each.name}`));
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

/** What the main thread of process `pid` is in right now (/proc/<pid>/task/<pid>/syscall, root reads it): { syscall } or { error }. */
export function readsyscall({ pid }) {
  try { return { syscall: readFileSync(`/proc/${Number(pid)}/task/${Number(pid)}/syscall`, 'utf8').trim() }; } catch (error) { return { error: String((error && error.code) || (error && error.message) || error) }; }
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

const ops = { start, pause, snapshot, stop, readmem, readsyscall, resume, state, stats, silence };

// `sudo -n node flight-tracefs.js <op> <json>`: the answer is one line of JSON
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [op, json] = process.argv.slice(2);
  Promise.resolve(ops[op] ? ops[op](JSON.parse(json || '{}')) : { error: `no such op: ${op}` })
    .then((answer) => process.stdout.write(`${JSON.stringify(answer)}\n`))
    .catch((error) => process.stdout.write(`${JSON.stringify({ error: String(error) })}\n`));
}
