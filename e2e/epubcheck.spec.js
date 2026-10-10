// The fixture books the specs read are valid EPUBs, checked by epubcheck
// (the jar EPUBCHECK_JAR names; CI installs it), or invalid in the one
// way their entry says, so a spec's book is a book and not a fault of
// the generator.

import { test, expect } from './fixtures.js';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createEpub } from './create-epub.js';
import { landmarkBooks } from './landmark-books.js';
import { publisherBooks } from './publisher-books.js';
import { noteBooks } from './note-books.js';
import { syncBooks } from './sync-books.js';
import { mediaBooks } from './media-books.js';
import { pagelistBooks } from './pagelist-books.js';
import { epub2Books } from './epub2-books.js';
import { wideBooks } from './wide-books.js';
import { w3cBooks } from './w3c-books.js';

const jar = process.env.EPUBCHECK_JAR;
const registries = { landmarks: landmarkBooks, pagelist: pagelistBooks, epub2: epub2Books, wide: wideBooks, 'w3c epub-tests': w3cBooks, notes: noteBooks, sync: syncBooks, media: mediaBooks, publisher: publisherBooks };

test.skip(!jar && !process.env.CI, 'EPUBCHECK_JAR names the epubcheck jar');
// the books do not depend on the browser: checked once
test.beforeEach(async ({}, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'the books are the same in every project');
});

for (const [group, books] of Object.entries(registries)) {
  for (const [name, entry] of Object.entries(books)) {
    test(`${group}: ${name} is ${entry.valid ? 'a valid EPUB' : 'invalid only as intended'}`, async () => {
      expect(jar, 'CI installs epubcheck and sets EPUBCHECK_JAR').toBeTruthy();
      const dir = mkdtempSync(join(tmpdir(), 'quire-epubcheck-'));
      const epub = join(dir, `${name}.epub`);
      const report = join(dir, `${name}.json`);
      writeFileSync(epub, entry.bytes ? entry.bytes() : createEpub(entry.opts));
      try {
        execFileSync('java', ['-jar', jar, epub, '--json', report, '--quiet'], { stdio: 'pipe' });
      } catch (e) {
        // a nonzero exit is a report with errors: read it below
      }
      const messages = JSON.parse(readFileSync(report, 'utf8')).messages
        .filter(m => m.severity === 'ERROR' || m.severity === 'FATAL');
      const ids = [...new Set(messages.map(m => m.ID))];
      if (entry.valid) expect(messages, JSON.stringify(messages, null, 1)).toEqual([]);
      else {
        expect(ids.length).toBeGreaterThan(0);
        expect(ids.filter(id => !entry.errors.includes(id)), JSON.stringify(messages, null, 1)).toEqual([]);
      }
    });
  }
}
