/**
 * The kernel half of the flight recorder (#575), the part that runs as root:
 * an ftrace instance of its own, a ring buffer that overwrites its oldest
 * events, scoped to the e2e run's process tree. `flight-recorder.js` calls it
 * in-process as root, else through `sudo -n node flight-tracefs.js <op> <json>`.
 * Every op returns plain data and never throws.
 */

import { chmodSync, closeSync, createWriteStream, existsSync, mkdirSync, openSync, readdirSync, readFileSync, readSync, rmdirSync, writeFileSync } from 'node:fs';
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

/** Makes the instance and starts it for the process tree of `pid`; { instance, skipped } or { error }. */
export function start({ tracefs = TRACEFS, name, pid, bufferKb = BUFFER_KB, events = EVENTS }) {
  const instance = `${tracefs}/instances/${name}`;
  try {
    if (!existsSync(`${tracefs}/instances`)) return { error: 'no tracefs instances directory (tracefs is not mounted here)' };
    mkdirSync(instance);
  } catch (error) { return { error: `cannot make ${instance}: ${(error && error.code) || error}` }; }
  const skipped = [];
  const missing = [];
  const set = (file, value) => { const bad = attempt(file, () => writeFileSync(`${instance}/${file}`, String(value))); if (bad) { skipped.push(bad); if (REQUIRED_EVENTS.some((event) => file === `events/${event}/enable`) || ['buffer_size_kb', 'trace_clock', 'set_event_pid', 'tracing_on'].includes(file)) missing.push(bad); } };
  set('buffer_size_kb', bufferKb);
  // the same clock as Chrome's trace events (CLOCK_MONOTONIC), so the two records line up
  set('trace_clock', 'mono');
  for (const event of events) set(`events/${event}/enable`, 1);
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

/** Writes the last `lines` lines of the record, gzipped, to `out` (a file anyone can read). tail and gzip do the bulk: the kernel formats the text, and a ring of 600 MB must not pass through node's lines. */
export async function snapshot({ instance, out, lines = LINES_KEPT, resume = false }) {
  try {
    // the ring is paused while it is read (a ring read as it records never reaches its end: tail ran for an hour on 44,000 events a second);
    // a record kept for a freeze stays paused (the first record is kept), one kept for a failure is resumed by its caller (keepKernel)
    pause({ instance });
    let header = '';
    const descriptor = openSync(`${instance}/trace`, 'r');
    try {
      const chunk = Buffer.alloc(4096);
      const got = readSync(descriptor, chunk, 0, 4096, null);
      header = chunk.toString('utf8', 0, got).split('\n').find((line) => line.includes('entries-in-buffer')) || '';
    } finally { closeSync(descriptor); }
    const clock = (readFileSync(`${instance}/trace_clock`, 'utf8').match(/\[(\w+)\]/) || [])[1] || 'unknown';
    const sink = createWriteStream(out);
    const finished = new Promise((resolve, reject) => { sink.on('finish', resolve); sink.on('error', reject); });
    const gzip = spawn('gzip', ['-1'], { stdio: ['pipe', 'pipe', 'inherit'] });
    gzip.stdout.pipe(sink);
    gzip.stdin.write(`${header}\n# the last ${lines} lines at most; clock: ${clock}\n`);
    const tail = spawn('tail', ['-n', String(lines), `${instance}/trace`], { stdio: ['ignore', 'pipe', 'inherit'] });
    tail.stdout.pipe(gzip.stdin);
    const ended = (child) => new Promise((resolve) => child.on('close', (code) => resolve(code)));
    const codes = await Promise.all([ended(tail), ended(gzip), finished]);
    chmodSync(out, 0o644);
    if (codes[0] !== 0 || codes[1] !== 0) return { error: `tail exited ${codes[0]}, gzip exited ${codes[1]}` };
    const counts = header.match(/entries-in-buffer\/entries-written: (\d+)\/(\d+)/);
    const inBuffer = counts ? Number(counts[1]) : 0;
    return { file: out, lines: Math.min(lines, inBuffer), seen: counts ? Number(counts[2]) : 0, header };
  } catch (error) { return { error: String((error && error.stack) || error) }; }
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

/** Starts recording again after a pause. */
export function resume({ instance }) {
  const bad = attempt('tracing_on', () => writeFileSync(`${instance}/tracing_on`, '1'));
  return bad ? { error: bad } : { resumed: true };
}

/** Whether the ring is recording: { on: '1' | '0' }. */
export function state({ instance }) {
  try { return { on: readFileSync(`${instance}/tracing_on`, 'utf8').trim() }; } catch (error) { return { error: String((error && error.code) || error) }; }
}

const ops = { start, pause, snapshot, stop, readmem, resume, state, stats };

// `sudo -n node flight-tracefs.js <op> <json>`: the answer is one line of JSON
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [op, json] = process.argv.slice(2);
  Promise.resolve(ops[op] ? ops[op](JSON.parse(json || '{}')) : { error: `no such op: ${op}` })
    .then((answer) => process.stdout.write(`${JSON.stringify(answer)}\n`))
    .catch((error) => process.stdout.write(`${JSON.stringify({ error: String(error) })}\n`));
}
