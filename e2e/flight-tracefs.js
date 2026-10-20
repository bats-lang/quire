/**
 * The kernel half of the flight recorder (#575), the part that runs as root:
 * an ftrace instance of its own, a ring buffer that overwrites its oldest
 * events, scoped to the e2e run's process tree. `flight-recorder.js` calls it
 * in-process as root, else through `sudo -n node flight-tracefs.js <op> <json>`.
 * Every op returns plain data and never throws.
 */

import { createReadStream, existsSync, mkdirSync, readFileSync, rmdirSync, writeFileSync, chmodSync } from 'node:fs';
import { createGzip } from 'node:zlib';
import { createWriteStream } from 'node:fs';
import { createInterface } from 'node:readline';
import { pathToFileURL } from 'node:url';
import { pipeline } from 'node:stream/promises';
import { Readable } from 'node:stream';

export const TRACEFS = '/sys/kernel/tracing';
// What is recorded, by what the question is: who woke whom and who slept (sched), which futex a thread waited on or woke
// and with what result (the untimed wait of #575), the signals, the processes' births and ends, and the byte traffic
// between the processes (the Mojo pipes are unix sockets and pipes, so read, write, sendmsg, recvmsg and the pollers).
// Measured on Chrome 149 (a loop of 30 page cycles): about 44,000 events a second, 3.9 s with and 3.7 s without
export const EVENTS = [
  'syscalls/sys_enter_futex', 'syscalls/sys_exit_futex',
  'sched/sched_switch', 'sched/sched_wakeup', 'sched/sched_process_fork', 'sched/sched_process_exit', 'sched/sched_process_exec',
  'signal/signal_generate',
  'syscalls/sys_enter_read', 'syscalls/sys_enter_write', 'syscalls/sys_enter_sendmsg', 'syscalls/sys_enter_recvmsg',
  'syscalls/sys_enter_epoll_pwait', 'syscalls/sys_enter_poll', 'syscalls/sys_enter_ppoll', 'syscalls/sys_enter_eventfd2',
];
export const BUFFER_KB = 65536; // for each CPU: 4 CPUs hold about 100 s at the measured rate
export const LINES_KEPT = 1500000;

const attempt = (what, action) => { try { return action(); } catch (error) { return `${what}: ${String((error && error.code) || (error && error.message) || error)}`; } };

/** Makes the instance and starts it for the process tree of `pid`; { instance, skipped } or { error }. */
export function start({ tracefs = TRACEFS, name, pid, bufferKb = BUFFER_KB, events = EVENTS }) {
  const instance = `${tracefs}/instances/${name}`;
  try {
    if (!existsSync(`${tracefs}/instances`)) return { error: 'no tracefs instances directory (tracefs is not mounted here)' };
    mkdirSync(instance);
  } catch (error) { return { error: `cannot make ${instance}: ${(error && error.code) || error}` }; }
  const skipped = [];
  const set = (file, value) => { const bad = attempt(file, () => writeFileSync(`${instance}/${file}`, String(value))); if (bad) skipped.push(bad); };
  set('buffer_size_kb', bufferKb);
  // the same clock as Chrome's trace events (CLOCK_MONOTONIC), so the two records line up
  set('trace_clock', 'mono');
  for (const event of events) set(`events/${event}/enable`, 1);
  set('options/event-fork', 1);
  set('set_event_pid', pid);
  set('tracing_on', 1);
  return { instance, skipped };
}

/** Stops recording (the ring keeps what it holds). */
export function pause({ instance }) {
  const bad = attempt('tracing_on', () => writeFileSync(`${instance}/tracing_on`, '0'));
  return bad ? { error: bad } : { paused: true };
}

/** Writes the last `lines` lines of the record, gzipped, to `out` (a file anyone can read). */
export async function snapshot({ instance, out, lines = LINES_KEPT }) {
  try {
    pause({ instance });
    const ring = new Array(lines);
    let count = 0;
    let header = '';
    const reader = createInterface({ input: createReadStream(`${instance}/trace`, { encoding: 'utf8' }), crlfDelay: Infinity });
    for await (const line of reader) {
      if (line.startsWith('#')) { if (line.includes('entries-in-buffer')) header = line; continue; }
      ring[count % lines] = line;
      count += 1;
    }
    const kept = Math.min(count, lines);
    const first = count > lines ? count % lines : 0;
    const body = (function* () {
      yield `${header}\n# kept the last ${kept} of ${count} lines, clock: ${readFileSync(`${instance}/trace_clock`, 'utf8').match(/\[(\w+)\]/)?.[1] || 'unknown'}\n`;
      for (let i = 0; i < kept; i += 1) yield `${ring[(first + i) % lines]}\n`;
    })();
    await pipeline(Readable.from(body), createGzip({ level: 6 }), createWriteStream(out));
    chmodSync(out, 0o644);
    return { file: out, lines: kept, seen: count, header };
  } catch (error) { return { error: String((error && error.stack) || error) }; }
}

/** Stops the instance and removes it. */
export function stop({ instance }) {
  pause({ instance });
  const bad = attempt('rmdir', () => rmdirSync(instance));
  return bad ? { error: bad } : { removed: true };
}

const ops = { start, pause, snapshot, stop };

// `sudo -n node flight-tracefs.js <op> <json>`: the answer is one line of JSON
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [op, json] = process.argv.slice(2);
  Promise.resolve(ops[op] ? ops[op](JSON.parse(json || '{}')) : { error: `no such op: ${op}` })
    .then((answer) => process.stdout.write(`${JSON.stringify(answer)}\n`))
    .catch((error) => process.stdout.write(`${JSON.stringify({ error: String(error) })}\n`));
}
