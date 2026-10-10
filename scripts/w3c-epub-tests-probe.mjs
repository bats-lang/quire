// Throwaway survey for quire#419, second pass: the tests whose question
// is not answered by reading the first chapter's text (the contents
// panel, a link followed, two books in one library, the reading
// direction, a link out). Each probe records what it saw; the verdicts
// are in reports/.
//
//   node scripts/w3c-epub-tests-probe.mjs <dir of .epub> <out file> [base url] [id ...]
import { chromium } from '@playwright/test';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [dir, out, base = 'http://localhost:3748', ...only] = process.argv.slice(2);
const browser = await chromium.launch({ args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'] });

const domClick = (page, label) => page.evaluate(label => {
  const b = [...document.querySelectorAll('button')].find(b => (b.getAttribute('aria-label') || b.textContent).trim() === label || (b.getAttribute('aria-label') || b.textContent).trim().startsWith(label));
  if (!b) return false; b.click(); return true;
}, label);
const pageDoc = page => page.getByRole('document', { name: 'Page' });
const cards = page => page.getByRole('region', { name: /^(Continue reading|Books)$/ }).getByRole('group');

async function open(page, ids) {
  await page.goto(base + '/');
  await page.getByRole('searchbox', { name: 'Search the library' }).waitFor({ timeout: 15000 });
  for (const [k, id] of ids.entries()) {
    await page.getByLabel('Import EPUB').setInputFiles(join(dir, id + '.epub'));
    await page.waitForFunction(n => document.querySelectorAll('[role=region] [role=group]').length >= n, k + 1, { timeout: 20000 }).catch(() => {});
    await page.waitForTimeout(500);
  }
}
async function openFirst(page) {
  await cards(page).first().click();
  await pageDoc(page).waitFor({ timeout: 15000 });
  await page.waitForTimeout(1500);
}
const text = page => pageDoc(page).innerText();
const indicator = page => page.getByRole('status', { name: 'Page', includeHidden: true }).textContent();
async function contentsEntries(page) {
  await domClick(page, 'Contents');
  await page.waitForTimeout(700);
  const dlg = page.getByRole('dialog', { name: 'Contents' });
  const rows = await dlg.getByRole('tabpanel', { name: 'Contents' }).getByRole('button').allInnerTexts().catch(() => []);
  return rows.map(r => r.trim());
}
async function viaContents(page, k) {
  await domClick(page, 'Contents');
  await page.waitForTimeout(700);
  const dlg = page.getByRole('dialog', { name: 'Contents' });
  await dlg.getByRole('tabpanel', { name: 'Contents' }).getByRole('button').nth(k).click();
  await page.waitForTimeout(1500);
  return text(page);
}
// Next chapter until the percentage stops changing: the places visited
async function walk(page) {
  const seen = [];
  for (let n = 0; n < 8; n++) {
    seen.push({ ind: (await indicator(page)).trim().slice(-60), text: (await text(page)).slice(0, 60) });
    if (!(await domClick(page, 'Next chapter'))) break;
    await page.waitForTimeout(1200);
  }
  return seen;
}

const probes = {
  async nav(page, id, r) {
    await open(page, [id]); await openFirst(page);
    r.entries = await contentsEntries(page);
    await page.keyboard.press('Escape');
    for (let k = 0; k < r.entries.length; k++) { (r.reached ||= []).push((await viaContents(page, k)).slice(0, 80)); }
  },
  async duplicate(page, id, r) {
    await open(page, [id]); await openFirst(page);
    r.entries = await contentsEntries(page); await page.keyboard.press('Escape');
    r.walk = await walk(page);
  },
  async link(page, id, r) {
    await open(page, [id]); await openFirst(page);
    r.before = (await text(page)).slice(0, 80);
    r.links = await pageDoc(page).evaluate(d => [...d.querySelectorAll('a')].map(a => a.textContent.trim().slice(0, 40)));
    if (r.links.length) { await pageDoc(page).locator('a').first().click(); await page.waitForTimeout(1500); r.after = (await text(page)).slice(0, 120); r.dialog = await page.evaluate(() => [...document.querySelectorAll('[role=dialog],[role=alertdialog]')].filter(d => d.offsetParent !== null).map(d => d.innerText.slice(0, 200))); }
    r.next = [];
  },
  async uniqueId(page, id, r) {
    await open(page, ['pkg-unique-id', 'pkg-unique-id_duplicate']);
    r.cards = await cards(page).allInnerTexts();
  },
  async direction(page, id, r) {
    await open(page, [id]);
    r.cardHtml = await cards(page).first().evaluate(c => c.innerHTML.slice(0, 600));
    r.cardDirs = await cards(page).first().evaluate(c => [...c.querySelectorAll('*')].map(e => [e.tagName, e.getAttribute('dir'), getComputedStyle(e).direction, e.textContent.trim().slice(0, 30)]).filter(x => x[3]));
    await openFirst(page);
    r.page = await pageDoc(page).evaluate(d => ({ cls: d.className, dir: getComputedStyle(d).direction, lang: d.getAttribute('lang'), htmlLang: document.documentElement.lang, ul: (e => e ? getComputedStyle(e).direction + ' ' + getComputedStyle(e).textAlign + ' ' + Math.round(e.getBoundingClientRect().left) : null)(d.querySelector('ul,li,q')) , quotes: (q => q ? getComputedStyle(q).quotes : null)(d.querySelector('q')) }));
    r.title = await page.getByRole('navigation', { name: 'Book' }).getByRole('heading').evaluate(h => [h.textContent, getComputedStyle(h).direction, h.getAttribute('dir')]).catch(() => null);
  },
  async bar(page, id, r) {
    await open(page, [id]); await openFirst(page);
    await page.mouse.click(512, 300); await page.waitForTimeout(600);
    const box = async s => { const b = await page.locator(s).boundingBox().catch(() => null); return b && Math.round(b.x + b.width / 2); };
    r.bar = { thumb: await box('#scrubber-thumb'), track: await box('#scrubber-track'), previous: await box('#previous-page'), next: await box('#next-page') };
    r.page = await pageDoc(page).evaluate(d => ({ cls: d.className, dir: getComputedStyle(d).direction, mode: getComputedStyle(d).writingMode }));
    r.text = (await text(page)).slice(0, 100);
    r.walk = await walk(page);
  },
};
const plan = {
  nav: ['nav-access', 'nav-activation', 'nav-non-text_img', 'nav-non-text_img_title', 'nav-spine_in-spine', 'nav-spine_in-spine-hidden-toc-css', 'nav-spine_in-spine-hidden-toc-html', 'nav-spine_in-spine-no-list-style', 'nav-spine_not-in-spine'],
  duplicate: ['pkg-spine-duplicate-item-hyperlink', 'pkg-spine-duplicate-item-rendering', 'pkg-spine-duplicate-item-ui'],
  link: ['pkg-spine-nonlinear-activation', 'pkg-spine-duplicate-item-hyperlink', 'pub-external-links', 'pub-external-links_consent', 'pss-support', 'pss-support_ignore-title'],
  uniqueId: ['pkg-unique-id'],
  direction: ['pkg-dir-auto_root-rtl', 'pkg-dir-auto_root-unset', 'pkg-dir_but_not_content', 'pkg-dir_creator-rtl', 'pkg-dir_rtl-root-ltr', 'pkg-dir_rtl-root-unset', 'pkg-dir_unset-root-rtl', 'pkg-dir_unset-root-unset', 'pkg-lang_but_not_content'],
  bar: ['pkg-spine-progression-default', 'pkg-spine-progression-pre-paginated', 'pkg-spine-progression_ltr', 'pkg-spine-progression_rtl'],
};
const results = {};
for (const [kind, ids] of Object.entries(plan)) {
  for (const id of ids) {
    if (only.length && !only.includes(id)) continue;
    const r = results[kind + ':' + id] = {};
    const ctx = await browser.newContext({ viewport: { width: 1024, height: 768 } });
    const page = await ctx.newPage();
    try { await probes[kind](page, id, r); } catch (e) { r.error = e.message.slice(0, 300); }
    await page.screenshot({ path: join(out.replace(/\.json$/, ''), `${kind}-${id}.png`) }).catch(() => {});
    await ctx.close();
    console.log(kind, id, r.error || 'ok');
  }
}
writeFileSync(out, JSON.stringify(results, null, 1));
await browser.close();
