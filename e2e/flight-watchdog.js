/**
 * The watchdog (#575): a root process outside the run's workers and browsers, started by global-setup.js, that sees a
 * frozen renderer with no help from the page: no DevTools, no debugger, no worker. Keyword: watchdog. It covers
 *  - a freeze while the stall watch is off, unarmed, dead or itself stuck (the watch lives in the Playwright worker);
 *  - a gap in time that is the machine's, not a process's (a stolen second shows as a late tick of every task at once).
 * Every 1 s it looks at each renderer of the run's process tree; one whose main thread has been in an untimed futex wait
 * with no CPU used for `sustainMs` is written out (the process table, every thread, the word and its neighbours, the
 * kernel ring's view of the word, user-space stacks if a tool is there) to `<out>/watchdog-<root>-<n>.json`.
 * A tick that comes late by more than `gapMs` is kept in `<out>/host-stalls-<root>.json` with the steal time that passed.
 */

import { execFile } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import * as tracefs from './flight-tracefs.js';
import { futexAnalysis } from './flight-recorder.js';
import { parseFutexSyscall } from './evidence.js';

export const SCAN_MS = 1000;
export const SUSTAIN_MS = 10000;
export const TICK_MS = 100;
export const GAP_MS = 300;
const STACK_MS = 15000;

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
  constructor({ root, out, instance, proc = '/proc', sustainMs = SUSTAIN_MS, gapMs = GAP_MS, stacks = true }) {
    Object.assign(this, { root, out, instance, proc, sustainMs, gapMs, stacks });
    this.seen = new Map();      // renderer pid -> { since, ticks }
    this.reported = new Set();
    this.stalls = [];
    this.count = 0;
    this.lastTick = null;
    this.lastSteal = stealMs(proc);
    mkdirSync(out, { recursive: true });
  }

  /** Called every TICK_MS: a tick later than its time by more than gapMs is a stall of the machine or of this process. */
  tick(now) {
    if (this.lastTick !== null && now - this.lastTick - TICK_MS > this.gapMs) {
      const steal = stealMs(this.proc);
      this.stalls.push({ at: new Date().toISOString(), gapMs: now - this.lastTick - TICK_MS, stealMsDuring: steal - this.lastSteal });
      if (this.stalls.length > 100) this.stalls.shift();
      this.lastSteal = steal;
      try { writeFileSync(join(this.out, `host-stalls-${this.root}-${process.pid}.json`), JSON.stringify(this.stalls, null, 2)); } catch (error) { /* the output directory is gone */ }
    }
    this.lastTick = now;
  }

  /** One look at the tree; resolves with the reports it wrote (their file names). */
  async scan(now) {
    const table = processTable(this.proc);
    const below = tree(table, this.root);
    const written = [];
    for (const pid of below) {
      const entry = table.get(pid);
      if (!entry || !/--type=renderer\b/.test(entry.cmdline)) continue;
      const call = parseFutexSyscall(text(`${this.proc}/${pid}/task/${pid}/syscall`));
      if (!call || !call.untimed) { this.seen.delete(pid); continue; }
      const seen = this.seen.get(pid);
      if (!seen || seen.ticks !== entry.ticks) { this.seen.set(pid, { since: now, ticks: entry.ticks }); continue; }
      if (now - seen.since >= this.sustainMs && !this.reported.has(pid)) {
        this.reported.add(pid);
        written.push(await this.report(pid, table, below, call, now - seen.since));
      }
    }
    return written;
  }

  async report(pid, table, below, call, heldMs) {
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
    const body = {
      reason: `renderer ${pid}: the main thread has been in an untimed futex wait with no CPU used for ${heldMs} ms (seen by the watchdog, outside the run)`,
      at: new Date().toISOString(), futex: { ...call, memory: tracefs.readmem({ pid, address: `0x${call.address}`, length: 64 }) },
      processes: [...below].map((each) => ({ pid: each, ...table.get(each) })), threads, hostStalls: this.stalls,
    };
    if (this.instance) {
      const ring = join(this.out, `${name}-kernel.txt.gz`);
      const kept = await tracefs.snapshot({ instance: this.instance, out: ring });
      body.kernelRing = kept;
      if (kept.file) body.futex.ring = await futexAnalysis(ring, { address: call.address, tid: pid }).catch((error) => ({ error: String(error && error.message || error) }));
    } else body.kernelRing = { unavailable: 'no ring was started' };
    if (this.stacks) {
      const stacks = await run('eu-stack', ['-p', String(pid), '-m', '-n', '40'], STACK_MS);
      body.userSpaceStacks = /#\d+\s/.test(stacks.stdout) ? stacks.stdout.slice(0, 20000) : `not available: ${stacks.error || stacks.stderr.slice(0, 200) || 'no frames'}`;
    }
    writeFileSync(join(this.out, `${name}.json`), JSON.stringify(body, null, 2));
    console.error(`[watchdog] ${body.reason}: ${name}.json`);
    return `${name}.json`;
  }
}

// node flight-watchdog.js <root pid> <out dir> [<ring instance>]: until the root is gone
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [root, out, instance, sustain] = [Number(process.argv[2]), process.argv[3], process.argv[4] || undefined, Number(process.argv[5]) || SUSTAIN_MS];
  const dog = new Watchdog({ root, out, instance, sustainMs: sustain });
  const ticker = setInterval(() => dog.tick(Date.now()), TICK_MS);
  let busy = false;
  const scanner = setInterval(async () => {
    if (busy) return;
    busy = true;
    try {
      if (!processTable().has(root)) { clearInterval(ticker); clearInterval(scanner); return; }
      await dog.scan(Date.now());
    } catch (error) { console.error(`[watchdog] ${error && error.stack || error}`); } finally { busy = false; }
  }, SCAN_MS);
  process.on('SIGTERM', () => process.exit(0));
}
