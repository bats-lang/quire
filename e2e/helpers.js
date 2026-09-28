// Shared steps for the e2e tests: books made on the fly, imported
// through the file input, opened from their cards, and the reader's
// place read back from the page.

import { expect } from '@playwright/test';
import { createEpub } from './create-epub.js';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const dir = mkdtempSync(join(tmpdir(), 'quire-e2e-'));
let count = 0;

/** An EPUB made from opts (see create-epub.js), written to a file */
export function epubFile(opts = {}) {
  const path = join(dir, `book-${process.pid}-${count++}.epub`);
  writeFileSync(path, createEpub({ storeChapters: true, ...opts }));
  return path;
}

/** Any bytes, written to a file named name */
export function rawFile(name, data) {
  const path = join(dir, `${count++}-${name}`);
  writeFileSync(path, data);
  return path;
}

/** Chapter i's body: a heading and n paragraphs long enough to fill
    several pages, each starting with a findable tag */
export function chapterBody(i, n = 20, tag = 'Para') {
  let body = `<h1>Part ${i}</h1>`;
  for (let k = 0; k < n; k++) {
    body += `<p>${tag} ${i}.${k} ` + 'lorem ipsum dolor sit amet '.repeat(12) + '</p>';
  }
  return body;
}

/** Chapters 1..n made by chapterBody */
export function chapters(n, paras = 20, tag = 'Para') {
  return Array.from({ length: n }, (_, k) => ({ body: chapterBody(k + 1, paras, tag) }));
}

/** Opens the app on an empty library; returns the page's errors (a
    list that fills as they happen) */
export async function start(page) {
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  await page.goto('/');
  await expect(page.locator('#qibn')).toBeVisible();
  return errors;
}

/** Imports the files through the import button's input, and waits
    until the library shows total cards */
export async function importFiles(page, files, total) {
  await page.locator('#qfin').setInputFiles(files);
  await expect(page.locator('#qlst .card')).toHaveCount(total, { timeout: 30000 });
}

/** The card of the book whose title has text */
export function card(page, text) {
  return page.locator('#qlst .card', { hasText: text });
}

/** Opens the book whose card has text, and waits for its first page */
export async function openBook(page, text) {
  await card(page, text).click();
  await expect(page.locator('#qrvw')).toBeVisible();
  await expect(page.locator('#qpgi')).toContainText('p.');
}

/** Imports one book made from opts and opens it */
export async function readBook(page, opts) {
  const n = await page.locator('#qlst .card').count();
  await importFiles(page, [epubFile(opts)], n + 1);
  await openBook(page, opts.title);
}

/** The page indicator as numbers: chapter, page and pages */
export async function place(page) {
  const t = await page.locator('#qpgi').innerText();
  const m = /Ch (\d+) · p\. (\d+)\/(\d+)/.exec(t);
  expect(m, `page indicator "${t}"`).not.toBeNull();
  return { ch: +m[1], p: +m[2], t: +m[3] };
}

/** Waits until the page indicator changes from before */
export async function placeChanged(page, before) {
  await expect.poll(async () => JSON.stringify(await place(page))).not.toBe(JSON.stringify(before));
  return place(page);
}

/** The ids of the content elements that start on the page shown */
export async function startsOnPage(page) {
  return page.evaluate(() => {
    const c = document.getElementById('qcnt').getBoundingClientRect();
    return [...document.querySelectorAll('#qcnt [id^=c]')]
      .filter(e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.left >= c.left - 1 && r.left < c.right; })
      .map(e => e.id);
  });
}

/** The text shown on the page (the content area's visible part) */
export async function visibleText(page) {
  return page.evaluate(() => {
    const c = document.getElementById('qcnt').getBoundingClientRect();
    return [...document.querySelectorAll('#qcnt p, #qcnt h1, #qcnt h2')]
      .filter(e => { const r = e.getBoundingClientRect(); return r.right > c.left && r.left < c.right; })
      .map(e => e.textContent).join('\n');
  });
}

/** Selects characters [from, to) of the first text of element sel */
export async function selectText(page, sel, from, to) {
  await page.evaluate(([sel, from, to]) => {
    const el = document.querySelector(sel);
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    const t = walker.nextNode();
    const r = document.createRange();
    r.setStart(t, from);
    r.setEnd(t, to);
    const s = getSelection();
    s.removeAllRanges();
    s.addRange(r);
  }, [sel, from, to]);
}

/** How many ranges the CSS highlight of kind k (1 highlights, 2 search)
    holds, and the text of the first */
export async function marks(page, k) {
  return page.evaluate(k => {
    const h = CSS.highlights.get('bats-mark-' + k);
    if (!h) return { size: 0, text: '' };
    let text = '';
    for (const r of h) { text = r.toString(); break; }
    return { size: h.size, text };
  }, k);
}

/** Leaves the reader for the library, through its back arrow */
export async function toLibrary(page) {
  await showChrome(page);
  await page.locator('#qbbk').click();
  await expect(page.locator('#qllc')).toBeVisible();
}

/** Opens the reader's bars when they are hidden */
export async function showChrome(page) {
  if (!(await page.locator('#qprv').isVisible())) {
    const box = await page.locator('#qcnt').boundingBox();
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  }
  await expect(page.locator('#qprv')).toBeVisible();
}
