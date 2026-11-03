#!/usr/bin/env node
/**
 * The last step of an e2e job (#575): a red whose evidence is missing is its own named failure, the one to fix first.
 * Reads the Playwright JSON reports (arguments: report files or directories) and the files the run left:
 *   --results <dir>    the test results (default test-results), and with them flight-watchdog/ for a FATAL note
 *   --require-report   no report at all fails (the step was killed, a worker died, the harness never started)
 *   --sanitizer <dir>  any report a sanitizer wrote there fails, with the report
 *   --require-capture  a test that FAILED must have left Playwright's trace and screenshot and the fixture's page-dom and
 *                      page-history (#1008, keyword: failure capture); a missing one is `EVIDENCE MISSING: failure capture (...)`
 *   --summary <artifacts>  write to $GITHUB_STEP_SUMMARY (else standard output) each failed test and the files of its capture,
 *                      named with the artifacts (comma separated) that hold them; --group <name> titles it
 * For each test that did not end as expected: its report must name a kernel ring (attachment `flight-kernel`, a file with content)
 * or the runner's reporter (evidence-reporter.js) must have written one for it; the test's own `EVIDENCE MISSING` or
 * `PREFLIGHT FAILED` is repeated by name; a `FATAL.txt` of the run's monitor is shown. Prints `::error::EVIDENCE MISSING: <field>`
 * for each and exits 1; exits 0 only when there is something to read and nothing is missing. No file time is read.
 */

import { appendFileSync, existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { pathToFileURL } from 'node:url';
import { sanitizerReports } from './evidence.js';
import { HOLD_PREFIX, LOCK_FAILED_PREFIX, holdersIn, lockFailuresIn } from './flight-tracefs.js';

function walk(directory, found = []) {
  let names = [];
  try { names = readdirSync(directory); } catch (error) { return found; }
  for (const name of names) {
    const path = join(directory, name);
    if (statSync(path).isDirectory()) walk(path, found); else found.push(path);
  }
  return found;
}

function testsOf(suite, out) {
  for (const spec of suite.specs || []) for (const test of spec.tests || []) out.push({ title: spec.title, file: spec.file, test });
  for (const child of suite.suites || []) testsOf(child, out);
}

const holds = (file) => { try { return statSync(file).size > 0; } catch (error) { return false; } };

/** What a failed test's capture is made of (#1008): Playwright's own (`trace`, `screenshot`: config `trace: 'on'`, `screenshot: 'on'`) and the page fixture's. */
export const CAPTURE_PARTS = ['trace', 'screenshot', 'page-dom', 'page-history'];

/** An attachment of a report is there when its file has content, or the report carries its body (the JSON reporter writes one or the other). */
const captured = (attachment) => Boolean(attachment && ((attachment.path && holds(attachment.path)) || (attachment.body && String(attachment.body).length > 0)));

/** What a kept ring's reach record says ({ reaches, why }), or why there is none: a ring that ends before the red is a paused ring, not a record of it. */
function reachOf(file) {
  try { return JSON.parse(readFileSync(file, 'utf8')); } catch (error) { return null; }
}
const reachProblem = (reach) => (reach ? (reach.reaches ? null : `does not reach the red: ${reach.why || 'its last event is before it'}`) : 'has no reach record (when its last event was, against the red)');

/**
 * The missing fields of the runs in `reports` (parsed JSON). `sidecar` is the records of the runner's reporter
 * ([{ test, source, file, problem }]); `requireReport`: no report is itself missing.
 */
export function missingFields(reports, sidecar = [], { requireReport = false, fatal = [], held = [], unlocked = [], requireCapture = false } = {}) {
  const missing = [...fatal, ...(held || []), ...(unlocked || [])];
  if (!reports.length && requireReport) missing.push('report (no Playwright JSON report: the run did not finish, or never started)');
  for (const report of reports) {
    for (const error of report.errors || []) {
      const found = /(EVIDENCE MISSING|PREFLIGHT FAILED): ([^\n]*)/.exec(String(error.message || ''));
      if (found) missing.push(`${found[2].trim()} (${found[1].toLowerCase()}, before any test)`);
    }
    const tests = [];
    for (const suite of report.suites || []) testsOf(suite, tests);
    for (const { title, test } of tests) {
      for (const result of test.results || []) {
        for (const error of result.errors || []) {
          const found = /(EVIDENCE MISSING|PREFLIGHT FAILED): ([^\n]*)/.exec(String(error.message || ''));
          if (found) missing.push(`${found[2].trim()} (test: ${title})`);
        }
        const unexpected = !['passed', 'skipped'].includes(result.status) && result.status !== test.expectedStatus;
        if (!unexpected) continue;
        // a plain failure (an assertion, the worker alive) has its whole capture, or the job says which part is missing (#1008)
        if (requireCapture && result.status === 'failed') {
          const absent = CAPTURE_PARTS.filter((part) => !captured((result.attachments || []).find((attachment) => attachment.name === part)));
          if (absent.length) missing.push(`failure capture (test "${title}" failed and left no ${absent.join(', no ')})`);
        }
        const named = (result.attachments || []).some((attachment) => attachment.name === 'flight-kernel' && attachment.path && holds(attachment.path));
        const rescue = sidecar.find((record) => record.source === 'the runner' && record.file && holds(record.file) && String(record.test).endsWith(title));
        if (!named && !rescue) { missing.push(`kernel ring (test "${title}" ended ${result.status} and left no record: the worker wrote none and the runner's reporter wrote none)`); continue; }
        // the ring has to reach the red: one left paused by an earlier capture has content and no evidence
        const attached = (result.attachments || []).find((attachment) => attachment.name === 'flight-kernel-reach' && attachment.path);
        const problem = reachProblem(named ? (attached && reachOf(attached.path)) : rescue.reach);
        if (problem) missing.push(`kernel ring (test "${title}": ${problem})`);
      }
    }
  }
  return missing;
}

/**
 * The failed tests of `reports` as the job's summary shows them (#1008): the spec and line, the project, the status, the error's first
 * line, and the files of the capture. Empty when nothing failed. `relativeTo` is the job's directory, so a path reads as it is inside
 * the artifact; `artifacts` names the artifacts that hold the files.
 */
export function captureSummary(reports, { artifacts = [], relativeTo = process.cwd(), group = '' } = {}) {
  const lines = [];
  for (const report of reports) {
    const walk = (suite) => {
      for (const spec of suite.specs || []) {
        for (const test of spec.tests || []) {
          for (const result of test.results || []) {
            const unexpected = !['passed', 'skipped'].includes(result.status) && result.status !== test.expectedStatus;
            if (!unexpected) continue;
            const first = String((result.errors && result.errors[0] && result.errors[0].message) || '').replace(/\u001b\[[0-9;]*m/g, '').split('\n')[0].slice(0, 200);
            lines.push(`* \`${spec.file}:${spec.line}\` ${spec.title} (project \`${test.projectName}\`, ${result.status}): ${first}`);
            for (const part of CAPTURE_PARTS) {
              const found = (result.attachments || []).find((attachment) => attachment.name === part);
              const where = found && found.path ? relative(relativeTo, found.path) : null;
              lines.push(`  * ${part}: ${captured(found) ? (where ? `\`${where}\`` : 'in the report') : '**missing**'}`);
            }
          }
        }
      }
      for (const child of suite.suites || []) walk(child);
    };
    for (const suite of report.suites || []) walk(suite);
  }
  if (!lines.length) return '';
  const names = artifacts.map((name) => `\`${name}\``).join(', ');
  return [`### e2e${group ? ` (${group})` : ''}: failed tests and what was kept of each`, '',
    `Artifacts of this run: ${names || 'none named'}. \`npx playwright show-trace <trace.zip>\` opens a trace (its DOM snapshots, console and network).`, '',
    ...lines, ''].join('\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  const take = (flag) => { const at = args.indexOf(flag); return at >= 0 ? args.splice(at, 2)[1] : null; };
  const sanitizer = take('--sanitizer');
  const results = take('--results') || 'test-results';
  const summary = take('--summary');
  const group = take('--group') || '';
  const captureIndex = args.indexOf('--require-capture');
  const requireCapture = captureIndex >= 0;
  if (requireCapture) args.splice(captureIndex, 1);
  const requireIndex = args.indexOf('--require-report');
  const requireReport = requireIndex >= 0;
  if (requireReport) args.splice(requireIndex, 1);
  if (sanitizer) {
    const found = sanitizerReports(sanitizer);
    for (const each of found) { console.log(`::error title=SANITIZER REPORT::SANITIZER REPORT: ${each.summary || each.file}`); console.log(each.head); }
    if (found.length) process.exit(1);
    console.log('sanitizer: no report');
    process.exit(0);
  }
  const files = args.flatMap((path) => (existsSync(path) && statSync(path).isDirectory() ? walk(path).filter((file) => file.endsWith('.json')) : [path]));
  const reports = files.flatMap((file) => { try { const parsed = JSON.parse(readFileSync(file, 'utf8')); return parsed.suites ? [parsed] : []; } catch (error) { return []; } });
  const sidecar = walk(join(results, 'runner-evidence')).filter((file) => /runner-evidence-\d+\.json$/.test(file)).flatMap((file) => { try { return JSON.parse(readFileSync(file, 'utf8')); } catch (error) { return []; } });
  const note = join('flight-watchdog', 'FATAL.txt');
  const fatal = existsSync(note) ? [readFileSync(note, 'utf8').trim().replace(/^EVIDENCE MISSING: /, '')] : [];
  // a hold of the ring still down at the end of the run: a capture never released it, so the ring was paused for what followed
  const held = holdersIn('flight-watchdog').map((each) => `kernel ring (still held paused by ${each.holder} at the end of the run: a capture did not release it; files ${HOLD_PREFIX}*)`);
  // a capture that went on without the ring lock (flight-tracefs.js, ring lock): it may have crossed another capture's pause and resume
  const unlocked = lockFailuresIn('flight-watchdog').map((each) => `ring lock (${each.text}; files ${LOCK_FAILED_PREFIX}*)`);
  const missing = missingFields(reports, sidecar, { requireReport, fatal, held, unlocked, requireCapture });
  // the failed tests and their capture, named in the job's summary (#1008)
  if (summary !== null) {
    const text = captureSummary(reports, { artifacts: summary.split(',').filter(Boolean), group });
    if (text) { if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${text}\n`); else console.log(text); }
  }
  for (const field of missing) console.log(`::error title=EVIDENCE MISSING::EVIDENCE MISSING: ${field}`);
  if (missing.length) process.exit(1);
  console.log(`evidence: nothing missing in ${reports.length} report(s)`);
}
