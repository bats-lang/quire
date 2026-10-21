/**
 * A Playwright reporter, in the runner process (#575): the net under the net. A test that did not end as expected and left no
 * kernel ring in its attachments (the worker died, the browser failed to launch before the stall watch existed, a fixture threw) has
 * the ring written here, by the runner, which no worker's death can take. Named in the report as `runner-evidence-<pid>.json`;
 * `evidence-check.js` reads it. If even that fails the reporter fails the run with `EVIDENCE MISSING`. Keyword: runner evidence.
 * Used as `--reporter=list,html,json,./e2e/evidence-reporter.js` (check.yml).
 */

import { existsSync, mkdirSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { keepKernel, track, wanted } from './flight-recorder.js';

const HOLDS = (attachment) => attachment.name === 'flight-kernel' && attachment.path && existsSync(attachment.path) && statSync(attachment.path).size > 0;

export default class EvidenceReporter {
  constructor() {
    this.directory = process.env.QUIRE_RUNNER_EVIDENCE || join(process.cwd(), 'test-results', 'runner-evidence');
    this.work = Promise.resolve();
    this.records = [];
    this.count = 0;
  }

  printsToStdio() { return false; }

  onTestEnd(test, result) {
    if (!wanted()) return;
    if (['passed', 'skipped'].includes(result.status) || result.status === test.expectedStatus) return;
    if (result.attachments.some(HOLDS)) { this.records.push({ test: test.titlePath().join(' > '), status: result.status, source: 'the worker' }); return; }
    // the worker left nothing: the runner writes the ring now, one at a time (each takes seconds and the ring is shared)
    this.count += 1;
    const number = this.count;
    this.work = track(this.work.then(async () => {
      mkdirSync(this.directory, { recursive: true });
      const file = join(this.directory, `runner-flight-${process.pid}-${number}-kernel.txt.gz`);
      const kept = await keepKernel(file, process.env, true);
      this.records.push({ test: test.titlePath().join(' > '), status: result.status, source: 'the runner', file: kept.file || null, problem: kept.file ? null : (kept.unavailable || kept.error || 'not written'), error: result.error ? String(result.error.message).split('\n')[0].slice(0, 200) : null });
    }));
  }

  async onEnd() {
    await this.work;
    const failed = this.records.filter((record) => record.source === 'the runner' && record.problem);
    if (this.records.length) {
      mkdirSync(this.directory, { recursive: true });
      writeFileSync(join(this.directory, `runner-evidence-${process.pid}.json`), JSON.stringify(this.records, null, 2));
    }
    for (const record of failed) console.error(`::error title=EVIDENCE MISSING::EVIDENCE MISSING: kernel ring of "${record.test}" (${record.problem})`);
    if (failed.length) return { status: 'failed' };
    return undefined;
  }
}
