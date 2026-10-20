#!/usr/bin/env node
/**
 * The last step of an e2e job (#575): a red whose evidence is missing is its own named failure, the one to fix first.
 * Reads the Playwright JSON reports (arguments: report files or directories) and the test results (`--results <dir>`):
 *  - a test that failed with `EVIDENCE MISSING: <field>` (the stall watch's own check, e2e/stall-capture.js);
 *  - a test that timed out when no test left a kernel ring at all (the fixture never ran or its artifact is gone).
 * Prints `::error::EVIDENCE MISSING: <field>` for each and exits 1; exits 0 when there is nothing missing.
 */

import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { sanitizerReports } from './evidence.js';

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

/** The missing fields of the runs in `reports` (parsed JSON), given the files under the results directory. */
export function missingFields(reports, resultFiles) {
  const missing = [];
  let timedOut = 0;
  for (const report of reports) {
    const tests = [];
    for (const suite of report.suites || []) testsOf(suite, tests);
    for (const { title, test } of tests) {
      for (const result of test.results || []) {
        if (result.status === 'timedOut') timedOut += 1;
        for (const error of result.errors || []) {
          const found = /EVIDENCE MISSING: ([^\n]*)/.exec(String(error.message || ''));
          if (found) missing.push(`${found[1].trim()} (test: ${title})`);
        }
      }
    }
  }
  if (timedOut && !resultFiles.some((file) => /flight-[^/]*kernel\.txt\.gz$/.test(file) && statSync(file).size > 0)) {
    missing.push(`kernel ring (${timedOut} test(s) timed out and no test left a flight record: the recorder did not run or its files are gone)`);
  }
  return missing;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  // `--sanitizer <dir>`: any report a sanitizer wrote there fails the step, with the report
  const sanitizer = args.indexOf('--sanitizer');
  if (sanitizer >= 0) {
    const found = sanitizerReports(args[sanitizer + 1]);
    for (const each of found) { console.log(`::error title=SANITIZER REPORT::SANITIZER REPORT: ${each.summary || each.file}`); console.log(each.head); }
    if (found.length) process.exit(1);
    console.log('sanitizer: no report');
    process.exit(0);
  }
  const at = args.indexOf('--results');
  const results = at >= 0 ? args.splice(at, 2)[1] : 'test-results';
  const files = args.flatMap((path) => (existsSync(path) && statSync(path).isDirectory() ? walk(path).filter((file) => file.endsWith('.json')) : [path]));
  const reports = files.flatMap((file) => { try { return [JSON.parse(readFileSync(file, 'utf8'))]; } catch (error) { return []; } });
  const missing = missingFields(reports, walk(results));
  for (const field of missing) console.log(`::error title=EVIDENCE MISSING::EVIDENCE MISSING: ${field}`);
  if (missing.length) process.exit(1);
  console.log('evidence: nothing missing');
}
