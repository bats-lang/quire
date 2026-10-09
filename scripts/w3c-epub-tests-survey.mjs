// Throwaway survey for quire#419: imports each EPUB of the W3C EPUB 3
// test suite (w3c/epub-tests, built by tests/generateEpubs.sh's recipe)
// into Quire and records what the reader shows, so that each test's
// description can be judged against it. It decides nothing itself: the
// verdicts are in reports/quire.json and reports/quire-w3c-epub-tests.md.
//
//   node scripts/w3c-epub-tests-survey.mjs <dir of .epub> <out dir> [base url] [id ...]
//
// The app must be served (npx serve dist/pwa). One JSON file per test in
// <out dir>/<id>.json and a screenshot of each chapter's first page.
import { chromium } from '@playwright/test';
import { readdirSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const [dir, out, base = 'http://localhost:3748', ...only] = process.argv.slice(2);
mkdirSync(out, { recursive: true });
const ids = readdirSync(dir).filter(f => f.endsWith('.epub')).map(f => f.slice(0, -5))
  .filter(id => only.length === 0 || only.includes(id)).sort();

const launch = () => chromium.launch({ args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'] });
let browser = await launch();

async function survey(id) {
  const result = { id, errors: [], chapters: [] };
  const ctx = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  const page = await ctx.newPage();
  page.on('pageerror', e => result.errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') result.errors.push('console: ' + m.text()); });
  try {
    await page.goto(base + '/');
    await page.getByRole('searchbox', { name: 'Search the library' }).waitFor({ timeout: 15000 });
    await page.getByLabel('Import EPUB').setInputFiles(join(dir, id + '.epub'));
    const card = page.getByRole('region', { name: /^(Continue reading|Books)$/ }).getByRole('group');
    await Promise.race([
      card.first().waitFor({ timeout: 20000 }).catch(() => {}),
      page.waitForTimeout(20000),
    ]);
    result.cards = await card.allInnerTexts();
    result.banner = await page.evaluate(() => [...document.querySelectorAll('[role=alert]')]
      .map(e => e.innerText.trim()).filter(Boolean));
    if (result.cards.length === 0) { result.opened = false; await ctx.close(); return result; }
    await card.first().click();
    const doc = page.getByRole('document', { name: 'Page' });
    try { await doc.waitFor({ timeout: 15000 }); } catch { result.opened = false; result.banner = await page.evaluate(() => document.body.innerText.slice(0, 600)); await ctx.close(); return result; }
    result.opened = true;
    await page.waitForTimeout(1500);
    let last = '';
    for (let n = 0; n < 14; n++) {
      const ind = await page.getByRole('status', { name: 'Page', includeHidden: true }).textContent().catch(() => '');
      const heading = await page.getByRole('navigation', { name: 'Book' }).getByRole('heading').textContent({ timeout: 1000 }).catch(() => '');
      const snap = await doc.evaluate(d => ({
        text: d.innerText, textContent: d.textContent,
        cls: d.className,
        html: d.innerHTML.slice(0, 5000),
        imgs: [...d.querySelectorAll('img')].map(i => ({ src: (i.getAttribute('src') || '').slice(0, 60), w: i.naturalWidth, h: i.naturalHeight, shown: i.getBoundingClientRect().width })),
        links: [...d.querySelectorAll('a')].map(a => ({ href: a.getAttribute('href'), text: a.textContent.trim().slice(0, 40) })),
        mathml: d.querySelectorAll('math').length, svg: d.querySelectorAll('svg').length,
        scriptsRun: window.__scripted || null,
        view: (r => ({ x: r.x, y: r.y, w: r.width, h: r.height }))(d.getBoundingClientRect()),
        // each child of the page (a fixed page's boxes, side by side) and what is in it
        geom: [...d.children].map(c => { const r = c.getBoundingClientRect(); return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), text: c.textContent.trim().slice(0, 50), imgs: c.querySelectorAll('img').length }; }),
      }));
      result.chapters.push({ n, heading, indicator: ind, ...snap });
      await page.screenshot({ path: join(out, `${id}-${n}.png`) });
      const key = heading + '|' + snap.textContent.slice(0, 200);
      if (key === last) break;
      last = key;
      const moved = await page.evaluate(() => {
        const b = [...document.querySelectorAll('button')].find(b => /^Next chapter/.test(b.textContent.trim()));
        if (!b || b.disabled) return false;
        b.click(); return true;
      });
      if (!moved) break;
      await page.waitForTimeout(1200);
    }
    // the contents
    await page.evaluate(() => {
      const b = [...document.querySelectorAll('button')].find(b => b.getAttribute('aria-label') === 'Contents' || b.textContent.trim() === 'Contents');
      if (b) b.click();
    });
    await page.waitForTimeout(800);
    result.contents = await page.evaluate(() => [...document.querySelectorAll('[role=dialog]')]
      .filter(d => d.offsetParent !== null && /Contents/.test(d.getAttribute('aria-label') || d.innerText.slice(0, 30)))
      .map(d => d.innerText.trim()).join('\n---\n'));
    await page.screenshot({ path: join(out, `${id}-contents.png`) });
  } catch (e) { result.errors.push('survey: ' + e.message); }
  await ctx.close();
  return result;
}

for (const id of ids) {
  const file = join(out, id + '.json');
  if (existsSync(file) && only.length === 0) continue;
  // a page that stops answering (a loop in script or wasm) is a result too:
  // the test is recorded as hung and the browser started anew
  let timer;
  const hung = new Promise(resolve => { timer = setTimeout(() => resolve({ id, hung: true, errors: ['no answer in 90 s'], chapters: [] }), 90000); });
  const r = await Promise.race([survey(id), hung]);
  clearTimeout(timer);
  if (r.hung) { try { browser.process().kill('SIGKILL'); } catch {} browser = await launch(); }
  writeFileSync(file, JSON.stringify(r, null, 1));
  console.log(id, r.hung ? 'HUNG' : r.opened, r.chapters.length, r.errors.length);
}
await browser.close().catch(() => {});
