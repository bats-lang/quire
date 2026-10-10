// Throwaway survey for quire#419 (the Media Overlays section): for each
// mol-* test, imports the EPUB, goes to a chapter with narration, presses
// Read aloud and records for a few seconds what the narration does: the
// phrases marked, the audio element's state, the error banner.
//
//   node scripts/w3c-epub-tests-narration.mjs <dir of .epub> <out file> [base url] [id ...]
import { chromium } from '@playwright/test';
import { readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [dir, out, base = 'http://localhost:3748', ...only] = process.argv.slice(2);
const ids = readdirSync(dir).filter(f => /^mol-.*\.epub$/.test(f)).map(f => f.slice(0, -5))
  .filter(id => only.length === 0 || only.includes(id)).sort();
const browser = await chromium.launch({ args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage', '--autoplay-policy=no-user-gesture-required'] });
const results = {};
for (const id of ids) {
  const r = results[id] = { states: [] };
  const ctx = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  const page = await ctx.newPage();
  try {
    await page.goto(base + '/');
    await page.getByLabel('Import EPUB').setInputFiles(join(dir, id + '.epub'));
    const card = page.getByRole('region', { name: /^(Continue reading|Books)$/ }).getByRole('group');
    await card.first().waitFor({ timeout: 20000 });
    await card.first().click();
    await page.getByRole('document', { name: 'Page' }).waitFor({ timeout: 15000 });
    await page.waitForTimeout(1500);
    // the chapter that has narration: the one where Previous phrase is offered
    for (let n = 0; n < 4; n++) {
      const offered = await page.evaluate(() => [...document.querySelectorAll('button')].some(b => b.getAttribute('aria-label') === 'Previous phrase' && b.offsetParent !== null));
      if (offered) { r.narrated = true; break; }
      const moved = await page.evaluate(() => {
        const b = [...document.querySelectorAll('button')].find(b => /^Next chapter/.test(b.textContent.trim()));
        if (!b || b.disabled) return false;
        b.click(); return true;
      });
      if (!moved) break;
      await page.waitForTimeout(1500);
    }
    r.heading = await page.getByRole('navigation', { name: 'Book' }).getByRole('heading').textContent({ timeout: 1000 }).catch(() => '');
    r.pageText = await page.getByRole('document', { name: 'Page' }).innerText();
    await page.evaluate(() => {
      window.__seen = [];
      setInterval(() => {
        const h = CSS.highlights.get('bats-mark-5');
        const t = h ? [...h].map(x => x.toString().replace(/\s+/g, ' ')).join('|') : '';
        if (t && window.__seen[window.__seen.length - 1] !== t) window.__seen.push(t);
      }, 50);
    });
    // the bars come up at a tap below the text (a tap on text a clip reads would move the narration)
    const previous = page.getByRole('toolbar', { name: 'Page controls' }).getByRole('button', { name: 'Previous page' });
    for (let k = 0; k < 3 && !(await previous.isVisible()); k++) { await page.mouse.click(512, 700); await page.waitForTimeout(600); }
    await page.getByRole('toolbar', { name: 'Page controls' }).getByRole('button', { name: 'Read aloud', exact: true }).click({ timeout: 5000 });
    for (let k = 0; k < 6; k++) {
      await page.waitForTimeout(1000);
      r.states.push(await page.evaluate(() => {
        const a = document.getElementById('narration');
        const alert = [...document.querySelectorAll('[role=alert]')].filter(e => e.offsetParent !== null).map(e => e.innerText.trim()).filter(Boolean);
        return a ? { paused: a.paused, time: +a.currentTime.toFixed(2), src: a.src.slice(0, 20), error: a.error && a.error.code, alert,
          pressed: [...document.querySelectorAll('button[aria-pressed]')].filter(b => b.getAttribute('aria-label') === 'Read aloud').map(b => b.getAttribute('aria-pressed')) } : null;
      }));
    }
    r.seen = await page.evaluate(() => window.__seen);
    r.screenshot = `${id}-narration.png`;
    await page.screenshot({ path: join(out.replace(/\.json$/, ''), r.screenshot) }).catch(() => {});
  } catch (e) { r.error = e.message.slice(0, 300); }
  await ctx.close();
  console.log(id, r.narrated, JSON.stringify(r.seen), r.error || '');
}
writeFileSync(out, JSON.stringify(results, null, 1));
await browser.close();
