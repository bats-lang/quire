#!/usr/bin/env node
/**
 * The last step of an e2e job (#575): a red whose evidence is missing is its own named failure, the one to fix first.
 * Reads the Playwright JSON reports (arguments: report files or directories) and the files the run left:
 *   --results <dir>    the test results (default test-results), and with them flight-watchdog/ for a FATAL note
 *   --require-report   no report at all fails (the step was killed, a worker died, the harness never started)
 *   --sanitizer <dir>  any report a sanitizer wrote there fails, with the report
 * For each test that did not end as expected: its report must name a kernel ring (attachment `flight-kernel`, a file with content)
 * or the runner's reporter (evidence-reporter.js) must have written one for it; the test's own `EVIDENCE MISSING` or
 * `PREFLIGHT FAILED` is repeated by name; a `FATAL.txt` of the run's monitor is shown. Prints `::error::EVIDENCE MISSING: <field>`
 * for each and exits 1; exits 0 only when there is something to read and nothing is missing. No file time is read.
 */

import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { sanitizerReports } from './evidence.js';
import { LOCK_FAILED_PREFIX, lockFailuresIn } from './flight-tracefs.js';

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

/** What a kept ring's reach record says ({ reaches, why }), or why there is none: a ring that ends before the red (one a fault stopped) is not a record of it. */
function reachOf(file) {
  try { return JSON.parse(readFileSync(file, 'utf8')); } catch (error) { return null; }
}
const reachProblem = (reach) => (reach ? (reach.reaches ? null : `does not reach the red: ${reach.why || 'its last event is before it'}`) : 'has no reach record (when its last event was, against the red)');

/**
 * The missing fields of the runs in `reports` (parsed JSON). `sidecar` is the records of the runner's reporter
 * ([{ test, source, file, problem }]); `requireReport`: no report is itself missing.
 */
export function missingFields(reports, sidecar = [], { requireReport = false, fatal = [], unlocked = [] } = {}) {
  const missing = [...fatal, ...(unlocked || [])];
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
        const named = (result.attachments || []).some((attachment) => attachment.name === 'flight-kernel' && attachment.path && holds(attachment.path));
        const rescue = sidecar.find((record) => record.source === 'the runner' && record.file && holds(record.file) && String(record.test).endsWith(title));
        if (!named && !rescue) { missing.push(`kernel ring (test "${title}" ended ${result.status} and left no record: the worker wrote none and the runner's reporter wrote none)`); continue; }
        // the ring has to reach the red: a ring that ends before it has content and no evidence
        const attached = (result.attachments || []).find((attachment) => attachment.name === 'flight-kernel-reach' && attachment.path);
        const problem = reachProblem(named ? (attached && reachOf(attached.path)) : rescue.reach);
        if (problem) missing.push(`kernel ring (test "${title}": ${problem})`);
      }
    }
  }
  return missing;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  const take = (flag) => { const at = args.indexOf(flag); return at >= 0 ? args.splice(at, 2)[1] : null; };
  const sanitizer = take('--sanitizer');
  const results = take('--results') || 'test-results';
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
  // a capture that went on without the ring lock (flight-tracefs.js, ring lock): it may have swapped the snapshot while another capture read it
  const unlocked = lockFailuresIn('flight-watchdog').map((each) => `ring lock (${each.text}; files ${LOCK_FAILED_PREFIX}*)`);
  const missing = missingFields(reports, sidecar, { requireReport, fatal, unlocked });
  for (const field of missing) console.log(`::error title=EVIDENCE MISSING::EVIDENCE MISSING: ${field}`);
  if (missing.length) process.exit(1);
  console.log(`evidence: nothing missing in ${reports.length} report(s)`);
}
