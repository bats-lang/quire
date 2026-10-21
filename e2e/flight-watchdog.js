/**
 * The watchdog (#575): a root process outside the run's workers and browsers, started by global-setup.js, that sees a
 * frozen process with no help from the page: no DevTools, no debugger, no worker. Keyword: watchdog. It covers
 *  - a freeze while the stall watch is off, unarmed, dead or itself stuck (the watch lives in the Playwright worker);
 *  - a main thread blocked in any call that has no timeout (a futex, epoll_wait, poll, read, recv, a write to a full pipe);
 *  - a gap in time that is the machine's, not a process's (a stolen second shows as a late tick of every task at once), and a
 *    jump of the wall clock against the monotonic one.
 * Every second it writes `<out>/heartbeat-<root>-<pid>.json` (when it looked, what the ring has taken): the run's monitor
 * (preflight.js) fails the job when that stops, so a dead watchdog is not found by reading a log after a loss.
 * A renderer (or a process matching `match`) whose main thread has been in an untimed wait with no CPU used for `sustainMs` is
 * written out to `<out>/watchdog-<root>-<pid>-<n>.json`; a tick late by more than `gapMs` is kept in `host-stalls-*.json`.
 */

import { execFile } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import * as tracefs from './flight-tracefs.js';
import { futexAnalysis } from './flight-recorder.js';
import { fdPeers, fdTarget, parseBlocked, parseFutexSyscall } from './evidence.js';

export const SCAN_MS = 1000;
export const SUSTAIN_MS = 10000;
export const TICK_MS = 100;
export const GAP_MS = 300;
export const CLOCK_JUMP_MS = 500;
export const HEARTBEAT_STALE_MS = 6000;
const STACK_MS = 15000;
const RINGS_MOST = 3;       // reports that keep the ring (each is up to tens of MB); later ones keep the rest
const RING_LINES = 600000;  // the last of the ring a watchdog report keeps

const text = (path) => { try { return readFileSync(path, 'utf8'); } catch (error) { return ''; } };

/** pid -> { ppid, comm, state, ticks, cmdline } for every process (`proc` is a directory laid out like /proc). */
export function processTable(proc = '/proc') {
  const table = new Map();
  let names = [];
  try { names = readdirSync(proc).filter((name) => /^\d+$/.test(name)); } catch (error) { return table; }
  for (const name of names) {
    const stat = text(`${proc}/${name}/stat`);
    const close = stat.lastIndexOf(')');
    if (close < 0) continue;
    const fields = stat.slice(close + 2).split(' ');
    table.set(Number(name), {
      ppid: Number(fields[1]), comm: stat.slice(stat.indexOf('(') + 1, close), state: fields[0], ticks: Number(fields[11]) + Number(fields[12]),
      cmdline: text(`${proc}/${name}/cmdline`).replace(/\0/g, ' ').trim(),
    });
  }
  return table;
}

/** `root` and every process below it. */
export function tree(table, root) {
  const found = new Set([root]);
  let grew = true;
  while (grew) {
    grew = false;
    for (const [pid, entry] of table) if (!found.has(pid) && found.has(entry.ppid)) { found.add(pid); grew = true; }
  }
  return found;
}

/** Aggregate CPU steal in milliseconds since boot (/proc/stat, 8th value of the `cpu` line, in ticks of 10 ms). */
export function stealMs(proc = '/proc') {
  const line = text(`${proc}/stat`).split('\n').find((each) => each.startsWith('cpu '));
  return line ? Number(line.trim().split(/\s+/)[8] || 0) * 10 : 0;
}

const run = (command, args, ms) => new Promise((resolve) => {
  execFile(command, args, { timeout: ms, killSignal: 'SIGKILL', maxBuffer: 4 << 20, encoding: 'utf8' }, (error, stdout, stderr) => resolve({ ok: !error, stdout: stdout || '', stderr: stderr || '', error: error ? String(error.message).slice(0, 200) : undefined }));
});

export class Watchdog {
  constructor({ root, out, instance, proc = '/proc', sustainMs = SUSTAIN_MS, gapMs = GAP_MS, stacks = true, match = '--type=renderer\\b', holdDir = null }) {
    Object.assign(this, { root, out, instance, proc, sustainMs, gapMs, stacks, holdDir: holdDir || out });
    this.match = new RegExp(match || '--type=renderer\\b');
    this.seen = new Map();      // pid -> { since, ticks }
    this.reported = new Set();
    this.stalls = [];
    this.clockJumps = [];
    this.count = 0;
    this.rings = 0;
    this.scans = 0;
    this.lastTick = null;
    this.lastWall = null;
    this.lastSteal = stealMs(proc);
    mkdirSync(out, { recursive: true });
  }

  /**
   * Called every TICK_MS with the monotonic clock and the wall clock (milliseconds): a tick later than its time by more than gapMs
   * is a stall of the machine or of this process; a wall clock that moved differently from the monotonic one is a jump of the clock.
   */
  tick(now, wall = Date.now()) {
    if (this.lastTick !== null) {
      if (now - this.lastTick - TICK_MS > this.gapMs) {
        const steal = stealMs(this.proc);
        this.stalls.push({ at: new Date().toISOString(), gapMs: now - this.lastTick - TICK_MS, stealMsDuring: steal - this.lastSteal });
        if (this.stalls.length > 100) this.stalls.shift();
        this.lastSteal = steal;
        try { writeFileSync(join(this.out, `host-stalls-${this.root}-${process.pid}.json`), JSON.stringify(this.stalls, null, 2)); } catch (error) { /* the output directory is gone */ }
      }
      const jump = (wall - this.lastWall) - (now - this.lastTick);
      if (Math.abs(jump) > CLOCK_JUMP_MS) {
        this.clockJumps.push({ at: new Date(wall).toISOString(), jumpMs: Math.round(jump) });
        try { writeFileSync(join(this.out, `clock-jumps-${this.root}-${process.pid}.json`), JSON.stringify(this.clockJumps, null, 2)); } catch (error) { /* the output directory is gone */ }
      }
    }
    this.lastTick = now;
    this.lastWall = wall;
  }

  /** What the monitor reads: when this looked last, what the ring has taken, and what was seen. */
  heartbeat() {
    this.scans += 1;
    const ring = this.instance ? tracefs.stats({ instance: this.instance }) : { unavailable: 'no ring' };
    const body = { at: Date.now(), pid: process.pid, scans: this.scans, ring, stalls: this.stalls.length, clockJumps: this.clockJumps.length, reports: this.count };
    // written whole or not at all: the monitor reads this file while it is written, and a half-written one must not look like a missing one
    try {
      const file = join(this.out, `heartbeat-${this.root}-${process.pid}.json`);
      writeFileSync(`${file}.part`, JSON.stringify(body));
      renameSync(`${file}.part`, file);
    } catch (error) { /* the output directory is gone */ }
    return body;
  }

  /** One look at the tree; resolves with the reports it wrote (their file names). */
  async scan(now) {
    const table = processTable(this.proc);
    const below = tree(table, this.root);
    const written = [];
    for (const pid of below) {
      const entry = table.get(pid);
      if (!entry || pid === process.pid || !this.match.test(entry.cmdline)) continue;
      const syscall = text(`${this.proc}/${pid}/task/${pid}/syscall`);
      const blocked = parseBlocked(syscall);
      if (!blocked || !blocked.untimed) { this.seen.delete(pid); continue; }
      const seen = this.seen.get(pid);
      if (!seen || seen.ticks !== entry.ticks) { this.seen.set(pid, { since: now, ticks: entry.ticks }); continue; }
      if (now - seen.since >= this.sustainMs && !this.reported.has(pid)) {
        this.reported.add(pid);
        written.push(await this.report(pid, table, below, blocked, syscall, now - seen.since));
      }
    }
    return written;
  }

  async report(pid, table, below, blocked, syscall, heldMs) {
    this.count += 1;
    const name = `watchdog-${this.root}-${process.pid}-${this.count}`;
    const threads = (() => {
      try {
        return readdirSync(`${this.proc}/${pid}/task`).map((tid) => ({
          tid: Number(tid), comm: text(`${this.proc}/${pid}/task/${tid}/comm`).trim(), state: text(`${this.proc}/${pid}/task/${tid}/stat`).split(') ')[1]?.[0],
          wchan: text(`${this.proc}/${pid}/task/${tid}/wchan`).trim(), syscall: text(`${this.proc}/${pid}/task/${tid}/syscall`).trim(), kernelStack: text(`${this.proc}/${pid}/task/${tid}/stack`).trim(),
        }));
      } catch (error) { return `unreadable: ${error.code}`; }
    })();
    const futex = parseFutexSyscall(syscall);
    const body = {
      reason: `process ${pid}: the main thread has been in an untimed wait (${blocked.name}) with no CPU used for ${heldMs} ms (seen by the watchdog, outside the run)`,
      at: new Date().toISOString(), blocked,
      target: blocked.fd === null ? null : fdTarget(pid, blocked.fd, this.proc),
      peers: blocked.fd === null ? [] : fdPeers(pid, blocked.fd, this.proc),
      processes: [...below].map((each) => ({ pid: each, ...table.get(each) })), threads, hostStalls: this.stalls, clockJumps: this.clockJumps,
    };
    if (futex) body.futex = { ...futex, memory: tracefs.readmem({ pid, address: `0x${futex.address}`, length: 64 }) };
    if (this.instance && this.rings >= RINGS_MOST) {
      body.kernelRing = { unavailable: `the first ${RINGS_MOST} reports of a run keep the ring; this one is the process table, the threads and the word only` };
    } else if (this.instance) {
      this.rings += 1;
      const ring = join(this.out, `${name}-kernel.txt.gz`);
      // the snapshot holds the ring paused while it reads (its hold file is down first, so the monitor never sees a pause without it) and releases it on
      // every outcome: the ring records again for the reds after this one
      const kept = await tracefs.snapshot({ instance: this.instance, out: ring, lines: RING_LINES, dir: this.holdDir, holder: `watchdog-${process.pid}-${this.rings}` });
      body.kernelRing = kept;
      if (kept.file && futex) body.futex.ring = await futexAnalysis(ring, { address: futex.address, tid: pid }).catch((error) => ({ error: String(error && error.message || error) }));
    } else body.kernelRing = { unavailable: 'no ring was started' };
    // written now and again with the stacks, which take up to STACK_MS: what is known is not held back by them
    writeFileSync(join(this.out, `${name}.json`), JSON.stringify(body, null, 2));
    if (this.stacks) {
      const stacks = await run('eu-stack', ['-p', String(pid), '-m', '-n', '40'], STACK_MS);
      body.userSpaceStacks = /#\d+\s/.test(stacks.stdout) ? stacks.stdout.slice(0, 20000) : `not available: ${stacks.error || stacks.stderr.slice(0, 200) || 'no frames'}`;
    }
    writeFileSync(join(this.out, `${name}.json`), JSON.stringify(body, null, 2));
    console.error(`[watchdog] ${body.reason}: ${name}.json`);
    return `${name}.json`;
  }
}

// node flight-watchdog.js <root pid> <out dir> [<ring instance> [<sustain ms> [<match>]]]: until the root is gone
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [root, out, instance, sustain, match, marker] = [Number(process.argv[2]), process.argv[3], process.argv[4] || undefined, Number(process.argv[5]) || SUSTAIN_MS, process.argv[6] || undefined, process.argv[7] || undefined];
  const dog = new Watchdog({ root, out, instance, sustainMs: sustain, match, holdDir: marker });
  const origin = performance.now();
  const ticker = setInterval(() => dog.tick(performance.now() - origin, Date.now()), TICK_MS);
  // on a timer of its own: a report that takes seconds (the ring written, the stacks) must not look like a dead watchdog
  dog.heartbeat();
  const beater = setInterval(() => dog.heartbeat(), SCAN_MS);
  let busy = false;
  const scanner = setInterval(async () => {
    if (busy) return;
    busy = true;
    try {
      if (!processTable().has(root)) { clearInterval(ticker); clearInterval(scanner); clearInterval(beater); return; }
      await dog.scan(performance.now() - origin);
    } catch (error) { console.error(`[watchdog] ${error && error.stack || error}`); } finally { busy = false; }
  }, SCAN_MS);
  process.on('SIGTERM', () => process.exit(0));
}
