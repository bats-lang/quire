/**
 * The evidence's failing paths on the real thing (#575): each test starts a Playwright run of its own (e2e/nested/), with the suite's
 * global setup, fixtures and runner reporter, and makes a part of the apparatus really fail: a ring that cannot start, a watchdog
 * that exits, one that is killed in the middle of the run, a ring that is stopped or removed, a real timeout, a launch that fails, a
 * killed runner, a killed worker. What is asserted is what the job would show: the exit code, the named line, the JSON report
 * Playwright wrote and `evidence-check.js` reading it. Keyword: real path.
 */

import { spawn, spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync, chmodSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';
import { test, expect } from './fixtures.js';
import { OUT_VARIABLE, INSTANCE_VARIABLE, isRoot, pauseInstance, removeInstance, ringSeen, silenceInstance, wanted } from './flight-recorder.js';
import { processTable, tree } from './flight-watchdog.js';

test.describe.configure({ mode: 'parallel' });

const here = dirname(fileURLToPath(import.meta.url));
const cli = createRequire(import.meta.url).resolve('@playwright/test/cli');

function desktopOnly(testInfo) {
  test.skip(testInfo.project.name !== 'desktop', 'the machine does not depend on the project: once, in desktop, is enough');
}

// A nested run's output is the evidence of these tests: a test that timed out waiting for the run (quire#749, job 119272940341) said only
// "Test timeout of 90000ms exceeded" and nothing of what the run had printed. Every run of a test is attached to it, whatever the outcome.
const runsOf = new Map();
test.afterEach(async ({}, testInfo) => {
  for (const [index, run] of (runsOf.get(testInfo.testId) || []).entries()) {
    await testInfo.attach(`nested-output-${index}`, { body: run.output() || '(the nested run printed nothing)', contentType: 'text/plain' });
    try { run.child.kill('SIGKILL'); } catch (gone) { /* it ended */ }
  }
  runsOf.delete(testInfo.testId);
});

/** A Playwright run of one case, in a directory of its own. */
function nested(testInfo, name, environment = {}, args = [], prepare = null) {
  const directory = testInfo.outputPath(`nested-${name}`);
  mkdirSync(directory, { recursive: true });
  if (prepare) prepare(directory);
  const env = { ...process.env, CI: 'true', QUIRE_NO_COST: '1', PLAYWRIGHT_JSON_OUTPUT_NAME: join(directory, 'report.json'), ...environment };
  // what the outer worker carries must not reach the run: its own worker numbers, its ring, its output directory
  for (const key of Object.keys(env)) if (/^(PW_TEST|PWTEST|TEST_WORKER_INDEX|TEST_PARALLEL_INDEX)/.test(key)) delete env[key];
  delete env[INSTANCE_VARIABLE];
  delete env[OUT_VARIABLE];
  delete env.QUIRE_RUNNER_EVIDENCE;
  const child = spawn(process.execPath, [cli, 'test', '--config', join(here, 'nested', 'playwright.nested.config.js'), ...args, `${name}.case.js`], { cwd: directory, env, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  const listeners = [];
  const take = (chunk) => { output += chunk.toString(); for (const listener of listeners) listener(); };
  child.stdout.on('data', take);
  child.stderr.on('data', take);
  const finished = new Promise((resolve) => child.on('close', (code, signal) => resolve({ code, signal })));
  const run = {
    directory, child, finished,
    output: () => output,
    /** The run's end, or a failure that carries the output when it has not ended within `ms` (a run that does not close holds a pipe: say which). */
    async done(ms = 30000) {
      let timer = null;
      const late = new Promise((resolve, reject) => { timer = setTimeout(() => reject(new Error(`the nested run did not close within ${ms} ms (exit ${child.exitCode}, signal ${child.signalCode}):\n${output.slice(-3000)}`)), ms); });
      try { return await Promise.race([finished, late]); } finally { clearTimeout(timer); }
    },
    /** Resolves with the match when the run's output has the pattern; fails with the output when it does not within `ms`. */
    async until(pattern, ms = 60000) {
      const started = Date.now();
      for (;;) {
        const found = pattern.exec(output);
        if (found) return found;
        if (Date.now() - started > ms) throw new Error(`the nested run did not print ${pattern} within ${ms} ms:\n${output.slice(-3000)}`);
        await new Promise((resolve) => { listeners.push(resolve); setTimeout(resolve, 250); });
      }
    },
    report() { try { return JSON.parse(readFileSync(join(directory, 'report.json'), 'utf8')); } catch (error) { return null; } },
  };
  runsOf.set(testInfo.testId, [...(runsOf.get(testInfo.testId) || []), run]);
  return run;
}

/** The attachments of every result of a report: [{ name, path }]. */
function attachmentsOf(report) {
  const found = [];
  const walk = (suite) => {
    for (const spec of suite.specs || []) for (const each of spec.tests || []) for (const result of each.results || []) found.push(...(result.attachments || []));
    for (const child of suite.suites || []) walk(child);
  };
  for (const suite of (report && report.suites) || []) walk(suite);
  return found;
}

/** Every result of a report, in the order they ran: [{ title, status, attachments: { name: path } }]. */
function resultsOf(report) {
  const found = [];
  const walk = (suite) => {
    for (const spec of suite.specs || []) for (const each of spec.tests || []) for (const result of each.results || []) found.push({ title: spec.title, status: result.status, attachments: Object.fromEntries((result.attachments || []).filter((a) => a.path).map((a) => [a.name, a.path])) });
    for (const child of suite.suites || []) walk(child);
  };
  for (const suite of (report && report.suites) || []) walk(suite);
  return found;
}

const statusesOf = (report) => {
  const found = [];
  const walk = (suite) => {
    for (const spec of suite.specs || []) for (const each of spec.tests || []) for (const result of each.results || []) found.push(result.status);
    for (const child of suite.suites || []) walk(child);
  };
  for (const suite of (report && report.suites) || []) walk(suite);
  return found;
};

/** The job's own check, as check.yml runs it, on a nested run's files. */
function evidenceCheck(run, extra = []) {
  const result = spawnSync(process.execPath, [join(here, 'evidence-check.js'), run.directory, '--results', join(run.directory, 'test-results'), '--require-report', ...extra], { encoding: 'utf8', cwd: run.directory });
  return { code: result.status, text: `${result.stdout}${result.stderr}` };
}

const kill = (pid, signal = 'SIGKILL') => (isRoot ? process.kill(pid, signal) : spawnSync('sudo', ['-n', 'kill', `-${signal.replace('SIG', '')}`, String(pid)]));

// a ring is read a line at a time: one that recorded a whole run is larger than a string can be
const ringFirst = async (file, pattern) => (await ringSeen(file, { found: pattern })).found;

function needRecorder() {
  expect(wanted(), 'run with CI=true or QUIRE_FLIGHT=1 (and sudo): the evidence tests prove what the apparatus does when a part fails').toBe(true);
}

test('preflight: a ring that cannot start fails the job before any test, by name, and the job-level check names it too', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'quiet', { QUIRE_FLIGHT_TRACEFS: testInfo.outputPath('no-tracefs') });
  const { code } = await run.finished;
  expect(code, run.output()).not.toBe(0);
  expect(run.output()).toMatch(/PREFLIGHT FAILED: kernel ring: no tracefs/);
  expect(run.output(), 'no test ran').not.toMatch(/1 passed/);
  const check = evidenceCheck(run);
  expect(check.code, check.text).toBe(1);
  expect(check.text).toMatch(/EVIDENCE MISSING: /);
});

test('preflight: a watchdog that exits at start fails the job before any test, with its exit code', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const script = testInfo.outputPath('dies.js');
  writeFileSync(script, 'process.exit(3);\n');
  const run = nested(testInfo, 'quiet', { QUIRE_FLIGHT_WATCHDOG_SCRIPT: script });
  const { code } = await run.finished;
  expect(code, run.output()).not.toBe(0);
  expect(run.output()).toMatch(/PREFLIGHT FAILED: watchdog: exited at start \(code 3/);
});

// The other parts of the preflight (Done when 2a of quire#575), each failed for real on the real path: the same nested run, the part's own
// guard in preflight.js, the named line, the job-level check repeating it. Where the failure cannot be had from the outside, the run's
// environment names the induction (QUIRE_FLIGHT_SUDO, _REQUIRE_EVENT, _TRACE_PID and the watchdog's script: set by no job, only here).
const bin = (testInfo, name, source) => {
  const file = testInfo.outputPath(name);
  writeFileSync(file, `#!${process.execPath}\n${source}\n`);
  chmodSync(file, 0o755);
  return file;
};

test('preflight: a sudo that asks for a password fails the job before any test, by name', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const asking = bin(testInfo, 'sudo-asks.js', "process.stderr.write('sudo: a password is required\\n'); process.exit(1);");
  const run = nested(testInfo, 'quiet', { QUIRE_FLIGHT_SUDO: asking });
  const { code } = await run.finished;
  expect(code, run.output()).not.toBe(0);
  expect(run.output()).toMatch(/PREFLIGHT FAILED: sudo -n: not usable .*a password is required/);
  expect(run.output(), 'no test ran').not.toMatch(/1 passed/);
  expect(run.output(), 'and no ring was made').not.toMatch(/\[preflight\] ok/);
});

test('preflight: an output directory that cannot be written and read back fails the job before any test, by name', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  // a file where the directory has to be
  const run = nested(testInfo, 'quiet', {}, [], (directory) => writeFileSync(join(directory, 'flight-watchdog'), 'a file, not a directory\n'));
  const { code } = await run.finished;
  expect(code, run.output()).not.toBe(0);
  expect(run.output()).toMatch(/PREFLIGHT FAILED: output directory: .*flight-watchdog cannot be written and read back/);
  expect(run.output(), 'no ring was made before it').not.toMatch(/ring \/sys\/kernel\/tracing\/instances\/quire-\d+ recording/);
});

test('preflight: a ring made without a required event fails the job before any test, by name, and leaves no ring behind', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'quiet', { QUIRE_FLIGHT_REQUIRE_EVENT: 'syscalls/sys_enter_no_such_call' });
  const { code } = await run.finished;
  expect(code, run.output()).not.toBe(0);
  expect(run.output()).toMatch(/PREFLIGHT FAILED: kernel ring: .*sys_enter_no_such_call.* could not be set/);
  const made = run.output().match(/quire-(\d+)/);
  expect(existsSync('/sys/kernel/tracing/instances/quire-' + (made ? made[1] : 'none')), 'the failed preflight removed the instance it made').toBe(false);
});

test('preflight: a ring that is made and on but takes no event of the run fails the job before any test, by name', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  // the ring is scoped to a process that does nothing, so the runner's own reads and timers are not in it
  const idle = spawn(process.execPath, ['-e', 'setTimeout(() => {}, 120000)'], { stdio: 'ignore' });
  try {
    const run = nested(testInfo, 'quiet', { QUIRE_FLIGHT_TRACE_PID: String(idle.pid) });
    const { code } = await run.finished;
    expect(code, run.output()).not.toBe(0);
    expect(run.output()).toMatch(/PREFLIGHT FAILED: kernel ring: made but not recording: before .*"on":"1".*after/);
  } finally { idle.kill('SIGKILL'); }
});

test('preflight: a watchdog that is alive and never beats fails the job before any test, by name', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  // alive (its child is checked, not its spawn assumed) and silent; it ends when the runner's pipe to it closes
  const silent = bin(testInfo, 'silent-watchdog.js', "process.stdin.resume(); process.stdin.on('end', () => process.exit(0)); setInterval(() => {}, 1000);");
  const run = nested(testInfo, 'quiet', { QUIRE_FLIGHT_WATCHDOG_SCRIPT: silent, QUIRE_FLIGHT_FIRST_BEAT_MS: '3000' });
  const { code } = await run.finished;
  expect(code, run.output()).not.toBe(0);
  expect(run.output()).toMatch(/PREFLIGHT FAILED: watchdog: no heartbeat in 3000 ms/);
});

test('preflight: a browser whose trace ring cannot start fails the test before its body, by name, and the job-level check repeats it', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'trace');
  const { code } = await run.finished;
  expect(code, run.output()).toBe(1);
  expect(run.output()).toMatch(/PREFLIGHT FAILED: browser trace ring: Tracing.start failed: .*already been started/);
  expect(run.output(), 'the body never ran').not.toMatch(/never reached/);
  const check = evidenceCheck(run);
  expect(check.code, check.text).toBe(1);
  expect(check.text).toMatch(/EVIDENCE MISSING: browser trace ring: Tracing.start failed/);
});

test('heartbeat: a watchdog killed in the middle of the run fails the job at that moment, not at the end', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'quiet', { QUIRE_NESTED_SLEEP: '90000', QUIRE_NESTED_TIMEOUT: '120000' });
  try {
    const ok = await run.until(/watchdog (\d+) beating/);
    const killedAt = Date.now();
    kill(Number(ok[1]));
    const { code } = await run.finished;
    expect(code, run.output()).not.toBe(0);
    expect(run.output()).toMatch(/EVIDENCE MISSING: watchdog: /);
    expect(Date.now() - killedAt, 'the job ended when the watchdog did, not when the test would have').toBeLessThan(30000);
    expect(evidenceCheck(run).text).toMatch(/EVIDENCE MISSING: watchdog/);
  } finally { run.child.kill('SIGKILL'); }
});

test('heartbeat: a ring that is stopped in the middle of the run fails the job at that moment', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'quiet', { QUIRE_NESTED_SLEEP: '90000', QUIRE_NESTED_TIMEOUT: '120000' });
  try {
    const ok = await run.until(/ring (\/sys\/kernel\/tracing\/instances\/quire-\d+) recording/);
    const killedAt = Date.now();
    await pauseInstance(ok[1]);
    const { code } = await run.finished;
    expect(code, run.output()).not.toBe(0);
    expect(run.output()).toMatch(/EVIDENCE MISSING: kernel ring: stopped/);
    expect(Date.now() - killedAt).toBeLessThan(30000);
  } finally { run.child.kill('SIGKILL'); }
});

// The monitor's end conditions that the tests above do not reach (Done when 2b): the watchdog goes quiet without dying, and the ring is on
// and takes no events. The limits are shortened by the run's environment (QUIRE_FLIGHT_BEAT_STALE_MS, _RING_QUIET_MS), not waited for: the
// condition and the code that ends the run are the real ones.
test('heartbeat: a watchdog that is alive and stops beating fails the job at that moment, by name', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'quiet', { QUIRE_NESTED_SLEEP: '90000', QUIRE_NESTED_TIMEOUT: '120000', QUIRE_FLIGHT_BEAT_STALE_MS: '3000' });
  let watchdog = null;
  let parent = null;
  try {
    const ok = await run.until(/watchdog (\d+) beating/);
    watchdog = Number(ok[1]);
    // the monitor's line names the process the runner started: on CI's user that is `sudo`, the parent of the watchdog (the heartbeat's pid)
    parent = Number((await run.until(/the watchdog (\d+) \(child and heartbeat\)/))[1]);
    const stoppedAt = Date.now();
    kill(watchdog, 'SIGSTOP'); // not killed: its process is there and its child has not exited
    await run.until(/EVIDENCE MISSING: watchdog: no heartbeat for/, 30000);
    // A stopped watchdog still holds the run's output pipe, and so does its parent: sudo stops itself when its command is stopped (job control) and
    // stays stopped when the command is killed, so the pipe stays open and the run never closes (quire#749, job 119272940341: 90 s, the test's timeout).
    // Both are ended before the run's close is waited for; SIGKILL needs no continue.
    for (const pid of new Set([watchdog, parent])) { try { kill(pid, 'SIGKILL'); } catch (gone) { /* it ended with the run */ } }
    const { code } = await run.done();
    expect(code, run.output()).not.toBe(0);
    expect(run.output()).toMatch(/EVIDENCE MISSING: watchdog: no heartbeat for \d+ ms/);
    expect(run.output(), 'it was not the exit that was seen').not.toMatch(/watchdog: exited during the run/);
    expect(Date.now() - stoppedAt).toBeLessThan(30000);
    expect(evidenceCheck(run).text).toMatch(/EVIDENCE MISSING: watchdog: no heartbeat for/);
  } finally { run.child.kill('SIGKILL'); for (const pid of [watchdog, parent]) if (pid) { try { kill(pid, 'SIGKILL'); } catch (gone) { /* it ended with the run */ } } }
});

// The machine stopping as a whole (quire#908: a host stall of 7965 ms with no steal, run 40232296271): the runner and the watchdog stop together, and the
// monitor, on their return, must not read the beat that was written before the stop as a watchdog gone quiet.
test('heartbeat: the runner and the watchdog stopped together, for longer than the limit, are not a watchdog gone quiet (quire#908)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'quiet', { QUIRE_NESTED_SLEEP: '20000', QUIRE_NESTED_TIMEOUT: '60000', QUIRE_FLIGHT_BEAT_STALE_MS: '3000' });
  let watchdog = null;
  let parent = null;
  const pids = () => [...new Set([run.child.pid, parent, watchdog].filter(Boolean))];
  try {
    watchdog = Number((await run.until(/watchdog (\d+) beating/))[1]);
    parent = Number((await run.until(/the watchdog (\d+) \(child and heartbeat\)/))[1]);
    for (const pid of pids()) kill(pid, 'SIGSTOP');
    await new Promise((resolve) => setTimeout(resolve, 7000));
    // the runner returns first, as in the observed stall (its timer ran before the watchdog's): the monitor's tick finds the beat written before the stop
    // (a process the old rule ended with the run is gone: the expectations below then say so, not a kill)
    const resume = (pid) => { try { kill(pid, 'SIGCONT'); } catch (gone) { /* it ended with the run */ } };
    resume(run.child.pid);
    await new Promise((resolve) => setTimeout(resolve, 600));
    for (const pid of pids()) resume(pid);
    // the run goes on to its own end, which prints the monitor's stopped line: the stall is counted in it
    const { code } = await run.done(60000);
    expect(run.output(), 'a stop of the whole machine is not a quiet watchdog').not.toMatch(/EVIDENCE MISSING/);
    expect(code, run.output()).toBe(0);
    expect(run.output(), 'the stopped line counts the monitor\'s own late tick').toMatch(/\[monitor\] stopped: .*; the monitor itself was late [1-9]\d* time\(s\) \(host stall\)/);
    console.error(`nested run after the stop: ${/\[monitor\] stopped: .*/.exec(run.output())[0]}`);
  } finally { for (const pid of pids()) { try { kill(pid, 'SIGCONT'); kill(pid, 'SIGKILL'); } catch (gone) { /* it ended with the run */ } } run.child.kill('SIGKILL'); }
});

test('heartbeat: a ring that is on and takes no events fails the job at that moment, by name', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'quiet', { QUIRE_NESTED_SLEEP: '90000', QUIRE_NESTED_TIMEOUT: '120000', QUIRE_FLIGHT_RING_QUIET_MS: '4000' });
  try {
    const ok = await run.until(/ring (\/sys\/kernel\/tracing\/instances\/quire-\d+) recording/);
    const silencedAt = Date.now();
    await silenceInstance(ok[1]); // every event off, tracing_on still 1
    const { code } = await run.finished;
    expect(code, run.output()).not.toBe(0);
    expect(run.output()).toMatch(/EVIDENCE MISSING: kernel ring: takes no events: \d+ written, unchanged for \d+ s/);
    expect(run.output(), 'the ring was on').not.toMatch(/kernel ring: stopped/);
    expect(Date.now() - silencedAt).toBeLessThan(30000);
  } finally { run.child.kill('SIGKILL'); }
});

// The ring lock (flight-tracefs.js): a lock that stays held past its limit is a record and the job's failure, not a silent go-ahead.
test('a ring lock that is held past its limit leaves a record: the capture goes on, and the job fails by name', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  test.setTimeout(testInfo.timeout + 60000);
  const run = nested(testInfo, 'plain', { QUIRE_NESTED_SLEEP: '3000', QUIRE_NESTED_TIMEOUT: '60000', QUIRE_FLIGHT_MONITOR: 'off' });
  let holder = null;
  try {
    await run.until(/ring (\/sys\/kernel\/tracing\/instances\/quire-\d+) recording/);
    // another capture that never lets go: the lock's time is renewed every 200 ms, so it is never stale
    const lock = join(run.directory, 'flight-watchdog', 'ring-lock');
    holder = setInterval(() => { try { writeFileSync(lock, `${new Date().toISOString()} holder-in-the-test\n`); } catch (gone) { /* the run ended */ } }, 200);
    const { code } = await run.finished;
    expect(code, run.output()).toBe(1);
    expect(run.output(), 'the line the capture printed').toMatch(/\[ring lock\] .* did not get the ring lock in \d+ ms \(limit 5000 ms; the lock said: .*holder-in-the-test\)/);
    const records = readdirSync(join(run.directory, 'flight-watchdog')).filter((name) => name.startsWith('ring-lock-failed-'));
    expect(records.length, 'the record in the output directory').toBeGreaterThan(0);
    // the capture was still made (a capture without the lock is worth more than none)
    expect(attachmentsOf(run.report()).map((each) => each.name)).toEqual(expect.arrayContaining(['flight-kernel']));
    clearInterval(holder);
    const check = evidenceCheck(run);
    expect(check.code, check.text).toBe(1);
    expect(check.text).toMatch(/EVIDENCE MISSING: ring lock \(.*did not get the ring lock/);
  } finally { if (holder) clearInterval(holder); run.child.kill('SIGKILL'); }
});

// "A freeze is recorded with the stall watch off": the stall watch does nothing (QUIRE_NO_STALL_WATCH: no arming, no probe, no capture, no trace
// ring of its own), the page is frozen through a session of the case's own, the test runs into its timeout, and the watchdog (which needs no DevTools,
// no debugger and no worker) wrote the freeze out, with the kernel ring beside it.
test('a freeze with the stall watch off is recorded by the watchdog, and the check finds nothing missing', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  test.setTimeout(testInfo.timeout + 120000);
  const run = nested(testInfo, 'hang-unwatched', { QUIRE_NO_STALL_WATCH: '1', QUIRE_NESTED_TIMEOUT: '30000' });
  const { code } = await run.finished;
  expect(code, run.output()).toBe(1);
  expect(statusesOf(run.report())).toEqual(['timedOut']);
  const out = join(run.directory, 'flight-watchdog');
  const reports = readdirSync(out).filter((name) => /^watchdog-\d+-\d+-\d+\.json$/.test(name)).map((name) => JSON.parse(readFileSync(join(out, name), 'utf8')));
  expect(reports.length, `the watchdog wrote the freeze out: ${readdirSync(out)}`).toBeGreaterThan(0);
  expect(reports[0].reason).toMatch(/untimed wait \(futex\)/);
  expect(reports[0].futex.untimed).toBe(true);
  expect(reports[0].futex.memory.bytes).toMatch(/^[0-9a-f]{128}$/);
  expect(reports[0].kernelRing.file, JSON.stringify(reports[0].kernelRing)).toBeTruthy();
  // and the stall watch really was off: it captured nothing, and left no record of its own for the red
  const found = [];
  const walkDirectory = (directory) => { for (const name of readdirSync(directory)) { const path = join(directory, name); if (statSync(path).isDirectory()) walkDirectory(path); else found.push(name); } };
  walkDirectory(run.directory);
  expect(found.filter((name) => /^stall-capture-/.test(name)), 'the stall watch captured nothing').toEqual([]);
  expect(attachmentsOf(run.report()).map((each) => each.name), 'and attached no record of its own').not.toContain('flight-kernel');
  // the runner's reporter wrote the ring for the result, so the job-level check has it
  const check = evidenceCheck(run);
  expect(check.code, check.text).toBe(0);
});

test('a plain failed test, the browser alive, leaves both rings, and the job-level check finds them in the report Playwright wrote', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'plain');
  const { code } = await run.finished;
  expect(code, run.output()).toBe(1);
  const report = run.report();
  expect(statusesOf(report)).toEqual(['failed']);
  const attachments = attachmentsOf(report);
  const kernel = attachments.find((each) => each.name === 'flight-kernel');
  const trace = attachments.find((each) => each.name === 'flight-browser-trace');
  expect(kernel && existsSync(kernel.path), JSON.stringify(attachments.map((each) => each.name))).toBe(true);
  expect(await ringFirst(kernel.path, /sched_switch/), 'the ring holds the scheduler').not.toBeNull();
  expect(trace && statSync(trace.path).size).toBeGreaterThan(100);
  const check = evidenceCheck(run);
  expect(check.code, check.text).toBe(0);
});

test('a plain failed test whose ring is gone is EVIDENCE MISSING in the report Playwright wrote, and in the job-level check', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'plain', { QUIRE_FLIGHT_MONITOR: 'off', QUIRE_NESTED_SLEEP: '6000' });
  try {
    const ok = await run.until(/ring (\/sys\/kernel\/tracing\/instances\/quire-\d+) recording/);
    await removeInstance(ok[1]);
    const { code } = await run.finished;
    expect(code, run.output()).toBe(1);
    const text = JSON.stringify(run.report());
    expect(text).toMatch(/EVIDENCE MISSING: kernel ring/);
    const check = evidenceCheck(run);
    expect(check.code, check.text).toBe(1);
    expect(check.text).toMatch(/EVIDENCE MISSING: kernel ring/);
  } finally { run.child.kill('SIGKILL'); }
});

test('a real timeout (a renderer frozen in a futex wait) whose ring is gone is EVIDENCE MISSING, named in the report and by the check', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'hang', { QUIRE_FLIGHT_MONITOR: 'off', QUIRE_NESTED_TIMEOUT: '25000' });
  try {
    const ok = await run.until(/ring (\/sys\/kernel\/tracing\/instances\/quire-\d+) recording/);
    await removeInstance(ok[1]);
    const { code } = await run.finished;
    expect(code, run.output()).toBe(1);
    expect(statusesOf(run.report())).toEqual(['timedOut']);
    expect(JSON.stringify(run.report())).toMatch(/EVIDENCE MISSING: [^"]*kernel ring/);
    const check = evidenceCheck(run);
    expect(check.code, check.text).toBe(1);
    expect(check.text).toMatch(/EVIDENCE MISSING: .*kernel ring/);
  } finally { run.child.kill('SIGKILL'); }
});

test('a real timeout with the apparatus whole: the record is complete and nothing is missing', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  test.setTimeout(testInfo.timeout + 120000);
  const run = nested(testInfo, 'hang', { QUIRE_NESTED_TIMEOUT: '30000' });
  const { code } = await run.finished;
  expect(code, run.output()).toBe(1);
  expect(statusesOf(run.report())).toEqual(['timedOut']);
  const names = attachmentsOf(run.report()).map((each) => each.name);
  expect(names).toEqual(expect.arrayContaining(['flight-kernel', 'flight-browser-trace']));
  expect(run.output(), 'the freeze is read from the record').toMatch(/futex: renderer \d+ main thread waits on 0x[0-9a-f]+ \(op 0x189, NO timeout\)/);
  const check = evidenceCheck(run);
  expect(check.code, check.text).toBe(0);
});

test('a runner that is killed leaves no report, and the job-level check fails instead of saying nothing is missing', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'quiet', { QUIRE_NESTED_SLEEP: '90000', QUIRE_NESTED_TIMEOUT: '120000' });
  try {
    await run.until(/watchdog (\d+) beating/);
    run.child.kill('SIGKILL');
    await run.finished;
    expect(run.report(), 'no report was written').toBeNull();
    const check = evidenceCheck(run);
    expect(check.code, check.text).toBe(1);
    expect(check.text).toMatch(/EVIDENCE MISSING: report \(no Playwright JSON report/);
  } finally { run.child.kill('SIGKILL'); }
});

test('a worker that is killed leaves no teardown, and the runner writes the ring for the test', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'quiet', { QUIRE_NESTED_SLEEP: '90000', QUIRE_NESTED_TIMEOUT: '120000', QUIRE_FLIGHT_MONITOR: 'off' });
  try {
    await run.until(/watchdog (\d+) beating/);
    // the worker is the parent of the browser it launched
    let worker = null;
    for (let tries = 0; tries < 100 && !worker; tries += 1) {
      const table = processTable();
      const mine = tree(table, run.child.pid);
      const browser = [...table].find(([pid, entry]) => mine.has(pid) && /chrome-headless-shell|chrome\b/.test(entry.cmdline) && /--remote-debugging-pipe/.test(entry.cmdline) && !/--type=/.test(entry.cmdline));
      worker = browser ? browser[1].ppid : null;
      if (!worker) await new Promise((resolve) => setTimeout(resolve, 200));
    }
    expect(worker, 'the nested worker was found by its browser').toBeTruthy();
    process.kill(worker, 'SIGKILL');
    const { code } = await run.finished;
    expect(code, run.output()).toBe(1);
    expect(statusesOf(run.report())).toEqual(['failed']);
    const sidecar = readdirSync(join(run.directory, 'test-results', 'runner-evidence')).filter((name) => /^runner-evidence-\d+\.json$/.test(name));
    expect(sidecar.length).toBeGreaterThan(0);
    const records = JSON.parse(readFileSync(join(run.directory, 'test-results', 'runner-evidence', sidecar[0]), 'utf8'));
    expect(records[0]).toMatchObject({ source: 'the runner' });
    expect(await ringFirst(records[0].file, /sched_switch/), 'the ring holds the scheduler').not.toBeNull();
    const check = evidenceCheck(run);
    expect(check.code, check.text).toBe(0);
  } finally { run.child.kill('SIGKILL'); }
});

test('a browser that cannot be started (the zygote, the sandbox, a missing executable): the failure is before the stall watch, and the runner still writes the ring', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'launch', { QUIRE_NESTED_EXECUTABLE: '/bin/false' });
  const { code } = await run.finished;
  expect(code, run.output()).toBe(1);
  expect(JSON.stringify(run.report())).toMatch(/browserType\.launch|Target page, context or browser has been closed/);
  const records = JSON.parse(readFileSync(join(run.directory, 'test-results', 'runner-evidence', readdirSync(join(run.directory, 'test-results', 'runner-evidence')).find((name) => /^runner-evidence-\d+\.json$/.test(name))), 'utf8'));
  expect(await ringFirst(records[0].file, /sched_process_exit: comm=false /), 'the exit is in the ring').not.toBeNull();
  const check = evidenceCheck(run);
  expect(check.code, check.text).toBe(0);
});

test('a browser that dies of SIGSEGV as it starts (quire#599): the signal is in the ring, the launch error in the report, and the environ guard is still in the config', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const executable = testInfo.outputPath('segv-browser');
  writeFileSync(executable, '#!/bin/sh\nkill -SEGV $$\n');
  chmodSync(executable, 0o755);
  const run = nested(testInfo, 'launch', { QUIRE_NESTED_EXECUTABLE: executable });
  const { code } = await run.finished;
  expect(code, run.output()).toBe(1);
  const records = JSON.parse(readFileSync(join(run.directory, 'test-results', 'runner-evidence', readdirSync(join(run.directory, 'test-results', 'runner-evidence')).find((name) => /^runner-evidence-\d+\.json$/.test(name))), 'utf8'));
  expect(await ringFirst(records[0].file, /signal_generate: sig=11 /), 'the signal is in the ring').not.toBeNull();
  expect(JSON.stringify(run.report())).toMatch(/launch|closed/);
  // the cause of #599 (setenv racing getenv in Chromium 145) is guarded by the value already set in the browser's environment
  expect(readFileSync(join(here, '..', 'playwright.config.js'), 'utf8')).toMatch(/FC_FONTATIONS: '1'/);
});

test('DevTools lost while the browser lives (quire#591: "Target page, context or browser has been closed"): both rings are kept and the browser trace is there', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'devtools');
  const { code } = await run.finished;
  expect(code, run.output()).toBe(1);
  expect(JSON.stringify(run.report())).toMatch(/closed|Target/);
  const attachments = attachmentsOf(run.report());
  const trace = attachments.find((each) => each.name === 'flight-browser-trace');
  expect(trace, JSON.stringify(attachments.map((each) => each.name))).toBeTruthy();
  expect(attachments.some((each) => each.name === 'flight-kernel')).toBe(true);
  const check = evidenceCheck(run);
  expect(check.code, check.text).toBe(0);
});

test('two reds and a third in one run (a crash, a freeze, a plain failure): each ring holds its own red, and the ring reaches the last one', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  test.setTimeout(testInfo.timeout + 180000);
  const run = nested(testInfo, 'twice');
  const { code } = await run.finished;
  expect(code, run.output()).toBe(1);
  const results = resultsOf(run.report());
  expect(results.map((each) => each.status), run.output()).toEqual(['failed', 'timedOut', 'failed']);
  expect(run.output(), 'nothing was missing, in the worker or in the monitor').not.toMatch(/EVIDENCE MISSING/);
  for (const each of results) {
    expect(Object.keys(each.attachments), each.title).toEqual(expect.arrayContaining(['flight-kernel', 'flight-kernel-reach', 'flight-browser-trace']));
    const reach = JSON.parse(readFileSync(each.attachments['flight-kernel-reach'], 'utf8'));
    expect(reach.reaches, `${each.title}: ${JSON.stringify(reach)}`).toBe(true);
    // not explained by another capture: the reds are seconds apart, so a ring left paused would have ended before this one (the freeze's ring may
    // overlap the watchdog's own report of it, which holds the ring too)
    if (!/second/.test(each.title)) expect(reach.others, each.title).toEqual([]);
    expect(reach.lastAt, each.title).toBeGreaterThanOrEqual(reach.redAt - 0.5);
  }
  // the second red is the freeze: its own futex wait is in its ring, after the first red's capture
  const [first, second, third] = results;
  const reaches = results.map((each) => JSON.parse(readFileSync(each.attachments['flight-kernel-reach'], 'utf8')));
  expect(reaches[1].lastAt, 'the second ring ends after the first red').toBeGreaterThan(reaches[0].lastAt + 1);
  expect(reaches[2].lastAt, 'the third ring ends after the second red').toBeGreaterThan(reaches[1].lastAt + 1);
  expect((await ringSeen(second.attachments['flight-kernel'], { wait: /sys_futex\(uaddr: (0x)?[0-9a-f]+, op: (0x)?189, val: \S+, utime: (0x)?0,/ })).wait, 'the freeze, in the second ring').not.toBeNull();
  // the third red's own event, a signal only that test sends, is in the third ring
  const event = JSON.parse(readFileSync(join(run.directory, 'third-event.json'), 'utf8'));
  expect((await ringSeen(third.attachments['flight-kernel'], { signal: new RegExp(`signal_generate: sig=${event.signal} .*pid=${event.pid} `) })).signal, 'the third red\'s signal is in the third ring').not.toBeNull();
  expect((await ringSeen(first.attachments['flight-kernel'], { signal: new RegExp(`signal_generate: sig=${event.signal} .*pid=${event.pid} `) })).signal, 'and not in the first, which ended before it').toBeNull();
  // no capture still holds the ring, the monitor ran and said so, and the job-level check passes
  expect(readdirSync(join(run.directory, 'flight-watchdog')).filter((name) => name.startsWith('ring-kept-'))).toEqual([]);
  expect(run.output()).toMatch(/\[monitor\] started/);
  expect(run.output()).toMatch(/\[monitor\] stopped: \d+ checks/);
  const check = evidenceCheck(run);
  expect(check.code, check.text).toBe(0);
});

test('a hold that nobody releases (a capture that died holding the ring) ends the run at that moment, and the job-level check names it', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'quiet', { QUIRE_NESTED_SLEEP: '90000', QUIRE_NESTED_TIMEOUT: '120000' });
  try {
    const ok = await run.until(/ring (\/sys\/kernel\/tracing\/instances\/quire-\d+) recording/);
    await run.until(/\[monitor\] started/);
    // a capture five minutes ago paused the ring and never came back
    writeFileSync(join(run.directory, 'flight-watchdog', 'ring-kept-dead-capture'), `${new Date(Date.now() - 300000).toISOString()} dead-capture\n`);
    await pauseInstance(ok[1]);
    const stoppedAt = Date.now();
    const { code } = await run.finished;
    expect(code, run.output()).not.toBe(0);
    expect(run.output()).toMatch(/EVIDENCE MISSING: kernel ring: held paused by dead-capture for \d+ s/);
    expect(Date.now() - stoppedAt).toBeLessThan(30000);
    expect(run.output(), 'the monitor says what it saw when it ended the run').toMatch(/\[monitor\] ended the run: \d+ checks/);
    expect(evidenceCheck(run).text).toMatch(/EVIDENCE MISSING: .*held paused by dead-capture/);
  } finally { run.child.kill('SIGKILL'); }
});

test('a red in a test tagged @serial, alone in the serial run, has the preflight, the monitor and both rings like any other', async ({}, testInfo) => {
  desktopOnly(testInfo);
  needRecorder();
  const run = nested(testInfo, 'serial', { QUIRE_NO_COST: '' }, ['--grep', '@serial']);
  const { code } = await run.finished;
  expect(code, run.output()).toBe(1);
  expect(run.output()).toMatch(/\[preflight\] ok \(the @serial run\): .*ring \/sys\/kernel\/tracing\/instances\/quire-\d+ recording.*watchdog \d+ beating/);
  expect(run.output(), 'the cost and the capabilities are in every run\'s log').toMatch(/\[cost\] 8 page cycles \(the @serial run\): \d+ ms with the rings off, \d+ ms with both on/);
  expect(run.output()).toMatch(/\[capabilities\] perf cycles available: (true|false)/);
  expect(run.output()).toMatch(/\[monitor\] started \(the @serial run\)/);
  expect(run.output()).toMatch(/\[monitor\] stopped: \d+ checks/);
  const results = resultsOf(run.report());
  expect(results.map((each) => each.status)).toEqual(['failed']);
  expect(Object.keys(results[0].attachments)).toEqual(expect.arrayContaining(['flight-kernel', 'flight-kernel-reach', 'flight-browser-trace']));
  expect((await ringSeen(results[0].attachments['flight-kernel'], { switched: /sched_switch/ })).switched).not.toBeNull();
  const check = evidenceCheck(run);
  expect(check.code, check.text).toBe(0);
});
