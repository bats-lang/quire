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
import { OUT_VARIABLE, INSTANCE_VARIABLE, pauseInstance, removeInstance, ringSeen, wanted } from './flight-recorder.js';
import { processTable, tree } from './flight-watchdog.js';

test.describe.configure({ mode: 'parallel' });

const here = dirname(fileURLToPath(import.meta.url));
const cli = createRequire(import.meta.url).resolve('@playwright/test/cli');
const isRoot = typeof process.getuid === 'function' && process.getuid() === 0;

function desktopOnly(testInfo) {
  test.skip(testInfo.project.name !== 'desktop', 'the machine does not depend on the project: once, in desktop, is enough');
}

/** A Playwright run of one case, in a directory of its own. */
function nested(testInfo, name, environment = {}) {
  const directory = testInfo.outputPath(`nested-${name}`);
  mkdirSync(directory, { recursive: true });
  const env = { ...process.env, CI: 'true', PLAYWRIGHT_JSON_OUTPUT_NAME: join(directory, 'report.json'), ...environment };
  // what the outer worker carries must not reach the run: its own worker numbers, its ring, its output directory
  for (const key of Object.keys(env)) if (/^(PW_TEST|PWTEST|TEST_WORKER_INDEX|TEST_PARALLEL_INDEX)/.test(key)) delete env[key];
  delete env[INSTANCE_VARIABLE];
  delete env[OUT_VARIABLE];
  delete env.QUIRE_RUNNER_EVIDENCE;
  const child = spawn(process.execPath, [cli, 'test', '--config', join(here, 'nested', 'playwright.nested.config.js'), `${name}.case.js`], { cwd: directory, env, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  const listeners = [];
  const take = (chunk) => { output += chunk.toString(); for (const listener of listeners) listener(); };
  child.stdout.on('data', take);
  child.stderr.on('data', take);
  const finished = new Promise((resolve) => child.on('close', (code, signal) => resolve({ code, signal })));
  return {
    directory, child, finished,
    output: () => output,
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
