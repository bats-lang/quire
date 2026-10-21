/**
 * The apparatus fails closed (#575): before any test, every part of the evidence is shown to work, and while the run goes on a
 * part that stops is the job's failure at that moment. `EVIDENCE MISSING` at the end of a red is the last net, not the plan.
 * Keyword: preflight. Where the recorder is not wanted (a local run) none of this runs.
 *
 *  preflight: sudo -n usable; the output directory written and read back by this user; the kernel ring made with every required
 *  event, on, and taking events from this process; the watchdog alive (its child checked, not its spawn assumed) and its first heartbeat
 *  read; the capabilities of the runner logged (capabilities.json). Each failure throws `PREFLIGHT FAILED: <part>: <why>`.
 *  monitor: every 2 s the watchdog's child, its heartbeat (content, not file times) and the ring's reading; a part that is gone
 *  prints the named error and ends the run with a failure.
 *  The browser's trace ring is checked where the browser lives, in the stall watch's fixture (`traceReady`).
 */

import { execFile } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { request } from 'node:https';
import { join } from 'node:path';
import { capabilities } from './evidence.js';
import { INSTANCE_VARIABLE, OUT_VARIABLE, WATCHDOG_DIRECTORY, markKept, pauseInstance, resumeKernel, ringStats, serialRun, settleOutstanding, startBrowserTrace, startKernel, startWatchdog, stopKernel, stopWatchdog, wanted } from './flight-recorder.js';
import { HEARTBEAT_STALE_MS } from './flight-watchdog.js';
import { holdersIn } from './flight-tracefs.js';

const isRoot = typeof process.getuid === 'function' && process.getuid() === 0;
const FIRST_HEARTBEAT_MS = 20000;
const MONITOR_EVERY_MS = 2000;
const RING_QUIET_MS = 60000;
// a capture reads a ring in seconds (6 s for 600 MB) and its sudo call is killed at 60 s: a hold older than twice that is a capture that died holding the ring
export const HOLD_MOST_MS = 120000;

export class PreflightFailed extends Error {
  constructor(part, why) { super(`PREFLIGHT FAILED: ${part}: ${why}`); this.part = part; }
}

const run = (command, args, ms = 15000) => new Promise((resolve) => {
  execFile(command, args, { timeout: ms, killSignal: 'SIGKILL', maxBuffer: 1 << 20, encoding: 'utf8' }, (error, stdout, stderr) => resolve({ ok: !error, stdout: stdout || '', stderr: stderr || '', error: error ? String(error.message).slice(0, 200) : undefined }));
});

const head = (url) => new Promise((resolve) => {
  const call = request(url, { method: 'HEAD', timeout: 15000 }, (response) => { resolve(response.statusCode); response.resume(); });
  call.on('error', () => resolve(0));
  call.on('timeout', () => { call.destroy(); resolve(0); });
  call.end();
});

/** The heartbeat files of a watchdog directory: [{ file, at, ... }], the newest first (read by content: `at` is written by the watchdog). */
export function heartbeats(out) {
  try {
    return readdirSync(out).filter((name) => /^heartbeat-\d+-\d+\.json$/.test(name)).flatMap((name) => {
      try { return [{ file: name, ...JSON.parse(readFileSync(join(out, name), 'utf8')) }]; } catch (partial) { return []; }
    }).sort((a, b) => b.at - a.at);
  } catch (error) { return []; }
}

/**
 * What the recording costs, measured in this job's log at its start (`[cost]`, every job and both runs): the same loop of page cycles (nothing but
 * IPC, the worst case for a recorder) with the rings off (the kernel ring paused under a hold, no trace) and on (both), the least of the rounds of each.
 * One measurement per run is enough because the cost is a property of this runner, this Chromium and these rings, not of a spec; QUIRE_NO_COST=1 skips it
 * (the nested runs of the real-path tests). It never fails the run: a number is a report.
 */
export async function measureCost(env = process.env, launchOptions = null, { rounds = 2, cycles = 8 } = {}) {
  if (env.QUIRE_NO_COST || !env[INSTANCE_VARIABLE]) return null;
  try {
    const { chromium } = await import('@playwright/test');
    const launch = () => chromium.launch({ headless: true, ...(launchOptions || {}) });
    const loop = async (browser) => {
      const began = performance.now();
      for (let i = 0; i < cycles; i += 1) {
        const context = await browser.newContext();
        const page = await context.newPage();
        await page.setContent('<button id="b">x</button>');
        await page.click('#b');
        await page.evaluate(() => fetch('data:text/plain,hi').then((answer) => answer.text()));
        await context.close();
      }
      return performance.now() - began;
    };
    const off = [];
    const on = [];
    for (let round = 0; round < rounds; round += 1) {
      const plain = await launch();
      markKept(env, 'cost');
      try { await pauseInstance(env[INSTANCE_VARIABLE]); off.push(await loop(plain)); } finally { await resumeKernel(env, 'cost'); await plain.close(); }
      const traced = await launch();
      try { await startBrowserTrace(traced, env); on.push(await loop(traced)); } finally { await traced.close(); }
    }
    const least = (list) => Math.min(...list);
    console.error(`[cost] ${cycles} page cycles${serialRun() ? ' (the @serial run)' : ''}: ${Math.round(least(off))} ms with the rings off, ${Math.round(least(on))} ms with both on (x${(least(on) / least(off)).toFixed(2)}); rounds off ${off.map(Math.round)}, on ${on.map(Math.round)}`);
    return { off, on };
  } catch (error) {
    console.error(`[cost] not measured: ${String((error && error.message) || error).split('\n')[0]}`);
    return null;
  }
}

/** Runs the preflight; resolves with what the run needs to keep and to stop, null where nothing is recorded. */
export async function preflight(env = process.env, { cwd = process.cwd(), version = '149.0.7827.55', launchOptions = null } = {}) {
  if (!wanted(env)) return null;
  // sudo -n: the ring, the watchdog and the memory reads need root, and a password prompt would hang
  if (!isRoot) {
    const sudo = await run('sudo', ['-n', 'true']);
    if (!sudo.ok) throw new PreflightFailed('sudo -n', `not usable (${sudo.error || sudo.stderr.trim()}): the kernel ring, the watchdog and the word reads need it`);
  }
  // the output directory: written, and read back by this user (the upload runs as this user)
  const out = join(cwd, WATCHDOG_DIRECTORY);
  try {
    mkdirSync(out, { recursive: true });
    const file = join(out, '.preflight');
    writeFileSync(file, 'written\n');
    if (readFileSync(file, 'utf8') !== 'written\n') throw new Error('read back differently');
    unlinkSync(file);
  } catch (error) { throw new PreflightFailed('output directory', `${out} cannot be written and read back (${error.message})`); }
  env[OUT_VARIABLE] = out;
  // the kernel ring: made, with every required event, on, and taking events
  const kernel = await startKernel(env);
  if (!kernel || kernel.error) throw new PreflightFailed('kernel ring', (kernel && kernel.error) || 'did not start');
  if (kernel.missing && kernel.missing.length) throw new PreflightFailed('kernel ring', `${kernel.missing.join('; ')} could not be set (a kernel without these events cannot answer the question)`);
  // recording: this process is in the ring's tree, so what it does (a few reads, a timer) must add events
  const before = await ringStats(env);
  readFileSync('/proc/self/stat');
  await new Promise((resolve) => setTimeout(resolve, 150));
  const after = await ringStats(env);
  if (before.error || after.error || after.on !== '1' || !(after.written > before.written)) throw new PreflightFailed('kernel ring', `made but not recording: before ${JSON.stringify(before)}, after ${JSON.stringify(after)}`);
  // the watchdog: its child alive and its first heartbeat read back
  const watchdog = startWatchdog(kernel.instance, env, out);
  const deadline = Date.now() + FIRST_HEARTBEAT_MS;
  let first = null;
  while (Date.now() < deadline) {
    if (watchdog.error) throw new PreflightFailed('watchdog', `did not start: ${watchdog.error}`);
    if (watchdog.exited) throw new PreflightFailed('watchdog', `exited at start (code ${watchdog.exited.code}, signal ${watchdog.exited.signal})`);
    first = heartbeats(out).find((each) => each.file.startsWith(`heartbeat-${process.pid}-`));
    if (first) break;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  if (!first) throw new PreflightFailed('watchdog', `no heartbeat in ${FIRST_HEARTBEAT_MS} ms`);
  if (first.ring && first.ring.on !== '1') throw new PreflightFailed('watchdog', `its first reading of the ring: ${JSON.stringify(first.ring)}`);
  // what the runner can do that bears on the classes the record cannot see (rr, symbols): in the log and in capabilities.json
  const found = await capabilities({ run: (command, args) => run(command, args, 20000), fetchHead: head, version });
  writeFileSync(join(out, 'capabilities.json'), JSON.stringify(found, null, 2));
  console.error(`[capabilities] perf cycles available: ${found.counters.available}; symbols: ${JSON.stringify(found.symbols)}`);
  console.error(`[preflight] ok${serialRun() ? ' (the @serial run)' : ''}: sudo, ${out} written and read back, ring ${kernel.instance} recording (${(kernel.skipped || []).length} optional events skipped), watchdog ${first.pid} beating; perf cycles ${found.counters.available ? 'AVAILABLE' : 'unsupported'}; symbols ${JSON.stringify(found.symbols)}`);
  for (const notice of found.notice) console.error(`::notice title=capabilities changed::${notice}`);
  await measureCost(env, launchOptions);
  return { kernel, watchdog, out };
}

/** Prints the named error and ends the run with a failure: a part of the evidence is gone, and the job is red now. */
export function fatal(part, why, out) {
  const message = `EVIDENCE MISSING: ${part}: ${why}`;
  console.error(`::error title=EVIDENCE MISSING::${message}`);
  if (out) { try { writeFileSync(join(out, 'FATAL.txt'), `${message}\n`); } catch (error) { /* the directory is gone */ } }
  process.exit(1);
}

/** Watches the parts while the run goes on. Returns a function that ends the watching. Logs a line at its start and a summary at its end (or at its fatal). */
export function startMonitor(started, env = process.env) {
  if (!started || env.QUIRE_FLIGHT_MONITOR === 'off') return () => {};
  const { watchdog, out } = started;
  const began = Date.now();
  let lastWritten = null;
  let lastMoved = Date.now();
  let stoppedSeenAt = null;
  let unreadable = 0;
  const seen = { checks: 0, beats: new Set(), holdsMost: 0, lastRing: null, lastScans: null };
  const summary = () => `${seen.checks} checks in ${Math.round((Date.now() - began) / 1000)} s; ${seen.beats.size} distinct heartbeats of the watchdog read (last: ${seen.lastScans === null ? 'none' : `${seen.lastScans} scans`}); the ring had written ${seen.lastRing === null ? 'nothing read' : seen.lastRing} events at the last reading; ring holds seen at once: ${seen.holdsMost}`;
  const die = (part, why) => { console.error(`[monitor] ended the run: ${summary()}`); return fatal(part, why, out); };
  console.error(`[monitor] started (${serialRun() ? 'the @serial run' : 'the run'}): every ${MONITOR_EVERY_MS} ms the watchdog ${started.watchdog.child ? started.watchdog.child.pid : '?'} (child and heartbeat), the ring ${started.kernel.instance} (on, taking events, held paused only by a capture that ends within ${HOLD_MOST_MS / 1000} s)`);
  const timer = setInterval(() => {
    seen.checks += 1;
    if (watchdog.exited && !watchdog.stopping) return die('watchdog', `exited during the run (code ${watchdog.exited.code}, signal ${watchdog.exited.signal})`);
    const beat = heartbeats(out).find((each) => each.file.startsWith(`heartbeat-${process.pid}-`));
    if (!beat) { unreadable += 1; if (unreadable >= 3) return die('watchdog', 'its heartbeat file is gone'); return; }
    unreadable = 0;
    seen.beats.add(beat.at);
    seen.lastScans = beat.scans;
    if (Date.now() - beat.at > HEARTBEAT_STALE_MS) return die('watchdog', `no heartbeat for ${Date.now() - beat.at} ms`);
    const ring = beat.ring || {};
    if (ring.error) return die('kernel ring', `unreadable by the watchdog: ${ring.error}`);
    if (ring.written !== undefined) seen.lastRing = ring.written;
    // a ring paused by a capture is held by a file of that capture (ring hold); one held longer than a capture can take is a capture that died holding it
    const holders = holdersIn(out);
    seen.holdsMost = Math.max(seen.holdsMost, holders.length);
    const stale = holders.find((each) => Number.isFinite(each.at) && Date.now() - each.at > HOLD_MOST_MS);
    if (stale) return die('kernel ring', `held paused by ${stale.holder} for ${Math.round((Date.now() - stale.at) / 1000)} s: a capture that does not end (a capture takes seconds)`);
    if (ring.on !== '1' && !holders.length) {
      // a capture resumes the ring and then takes its hold down, so a heartbeat read just before the resume shows a stopped ring with no hold:
      // it is the ring's failure only when a reading made after the hold was first seen missing still shows it stopped
      if (stoppedSeenAt === null) stoppedSeenAt = Date.now();
      else if (beat.at > stoppedSeenAt) return die('kernel ring', `stopped (tracing_on is ${ring.on}) and no capture paused it`);
    } else stoppedSeenAt = null;
    if (ring.written !== lastWritten) { lastWritten = ring.written; lastMoved = Date.now(); }
    else if (ring.on === '1' && Date.now() - lastMoved > RING_QUIET_MS) return die('kernel ring', `takes no events: ${ring.written} written, unchanged for ${Math.round((Date.now() - lastMoved) / 1000)} s`);
  }, MONITOR_EVERY_MS);
  timer.unref();
  return () => { clearInterval(timer); console.error(`[monitor] stopped: ${summary()}`); };
}

export async function teardown(started, stopMonitoring) {
  if (stopMonitoring) stopMonitoring();
  // the reporter's snapshots of reds the workers left no record for need the ring: they finish before it is removed
  await settleOutstanding();
  if (!started) return;
  stopWatchdog(started.watchdog);
  await stopKernel(started.kernel);
}
