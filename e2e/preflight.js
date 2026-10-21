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
import { existsSync, mkdirSync, readdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { request } from 'node:https';
import { join } from 'node:path';
import { capabilities } from './evidence.js';
import { OUT_VARIABLE, WATCHDOG_DIRECTORY, keptMarker, ringStats, settleOutstanding, startKernel, startWatchdog, stopKernel, stopWatchdog, wanted } from './flight-recorder.js';
import { HEARTBEAT_STALE_MS } from './flight-watchdog.js';

const isRoot = typeof process.getuid === 'function' && process.getuid() === 0;
const FIRST_HEARTBEAT_MS = 20000;
const MONITOR_EVERY_MS = 2000;
const RING_QUIET_MS = 60000;

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

/** Runs the preflight; resolves with what the run needs to keep and to stop, null where nothing is recorded. */
export async function preflight(env = process.env, { cwd = process.cwd(), version = '149.0.7827.55' } = {}) {
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
  console.error(`[preflight] ok: sudo, ${out} written and read back, ring ${kernel.instance} recording (${(kernel.skipped || []).length} optional events skipped), watchdog ${first.pid} beating; perf cycles ${found.counters.available ? 'AVAILABLE' : 'unsupported'}; symbols ${JSON.stringify(found.symbols)}`);
  for (const notice of found.notice) console.error(`::notice title=capabilities changed::${notice}`);
  return { kernel, watchdog, out };
}

/** Prints the named error and ends the run with a failure: a part of the evidence is gone, and the job is red now. */
export function fatal(part, why, out) {
  const message = `EVIDENCE MISSING: ${part}: ${why}`;
  console.error(`::error title=EVIDENCE MISSING::${message}`);
  if (out) { try { writeFileSync(join(out, 'FATAL.txt'), `${message}\n`); } catch (error) { /* the directory is gone */ } }
  process.exit(1);
}

/** Watches the parts while the run goes on. Returns a function that ends the watching. */
export function startMonitor(started, env = process.env) {
  if (!started || env.QUIRE_FLIGHT_MONITOR === 'off') return () => {};
  const { watchdog, out } = started;
  let lastWritten = null;
  let lastMoved = Date.now();
  let stoppedSeenAt = null;
  let unreadable = 0;
  const timer = setInterval(() => {
    if (watchdog.exited && !watchdog.stopping) return fatal('watchdog', `exited during the run (code ${watchdog.exited.code}, signal ${watchdog.exited.signal})`, out);
    const beat = heartbeats(out).find((each) => each.file.startsWith(`heartbeat-${process.pid}-`));
    if (!beat) { unreadable += 1; if (unreadable >= 3) return fatal('watchdog', 'its heartbeat file is gone', out); return; }
    unreadable = 0;
    if (Date.now() - beat.at > HEARTBEAT_STALE_MS) return fatal('watchdog', `no heartbeat for ${Date.now() - beat.at} ms`, out);
    const ring = beat.ring || {};
    if (ring.error) return fatal('kernel ring', `unreadable by the watchdog: ${ring.error}`, out);
    const marker = keptMarker(env);
    const paused = marker && existsSync(marker);
    if (ring.on !== '1' && !paused) {
      // a capture resumes the ring and then takes its marker down, so a heartbeat read just before the resume shows a stopped ring with no marker:
      // it is the ring's failure only when a reading made after the marker was first seen missing still shows it stopped
      if (stoppedSeenAt === null) stoppedSeenAt = Date.now();
      else if (beat.at > stoppedSeenAt) return fatal('kernel ring', `stopped (tracing_on is ${ring.on}) and no capture paused it`, out);
    } else stoppedSeenAt = null;
    if (ring.written !== lastWritten) { lastWritten = ring.written; lastMoved = Date.now(); }
    else if (ring.on === '1' && Date.now() - lastMoved > RING_QUIET_MS) return fatal('kernel ring', `takes no events: ${ring.written} written, unchanged for ${Math.round((Date.now() - lastMoved) / 1000)} s`, out);
  }, MONITOR_EVERY_MS);
  timer.unref();
  return () => clearInterval(timer);
}

export async function teardown(started, stopMonitoring) {
  if (stopMonitoring) stopMonitoring();
  // the reporter's snapshots of reds the workers left no record for need the ring: they finish before it is removed
  await settleOutstanding();
  if (!started) return;
  stopWatchdog(started.watchdog);
  await stopKernel(started.kernel);
}
