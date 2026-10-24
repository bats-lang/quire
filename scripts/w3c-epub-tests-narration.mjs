// Throwaway survey for quire#419 (the Media Overlays section): for each
// mol-* test, imports the EPUB, goes to a chapter with narration, presses
// Read aloud and records for a few seconds what the narration does: the
// phrases marked, the audio element's state, the error banner.
//
//   node scripts/w3c-epub-tests-narration.mjs <desktop|android> <dir of .epub> <out file> [base url] [id ...]
import { projectOf, launch, newPage, pageDoc, cards, settled, domClickMoves, showBars } from './w3c-epub-tests-project.mjs';
import { readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [projectName, dir, out, base = 'http://localhost:3748', ...only] = process.argv.slice(2);
const project = projectOf(projectName);
const ids = readdirSync(dir).filter(f => /^mol-.*\.epub$/.test(f)).map(f => f.slice(0, -5))
  .filter(id => only.length === 0 || only.includes(id)).sort();
const browser = await launch(['--autoplay-policy=no-user-gesture-required']);
const results = {};
for (const id of ids) {
  const r = results[id] = { project, states: [] };
  const { context: ctx, page } = await newPage(browser, project);
  try {
    await page.goto(base + '/');
    await page.locator('#import-file').setInputFiles(join(dir, id + '.epub'));
    const card = cards(page);
    await card.first().waitFor({ timeout: 20000 });
    await card.first().click();
    await pageDoc(page).waitFor({ timeout: 15000 });
    await settled(page);
    // the chapter that has narration: the one where Previous phrase is offered
    for (let n = 0; n < 4; n++) {
      const offered = await page.evaluate(() => [...document.querySelectorAll('button')].some(b => b.getAttribute('aria-label') === 'Previous phrase' && b.offsetParent !== null));
      if (offered) { r.narrated = true; break; }
      if (!(await domClickMoves(page, 'Next chapter'))) break;
    }
    r.heading = await page.getByRole('navigation', { name: 'Book' }).getByRole('heading').textContent({ timeout: 1000 }).catch(() => '');
    r.pageText = await pageDoc(page).innerText();
    await page.evaluate(() => {
      window.__seen = [];
      setInterval(() => {
        const h = CSS.highlights.get('bats-mark-5');
        const t = h ? [...h].map(x => x.toString().replace(/\s+/g, ' ')).join('|') : '';
        if (t && window.__seen[window.__seen.length - 1] !== t) window.__seen.push(t);
      }, 50);
    });
    // the bars come up at a tap below the text
    const controls = page.getByRole('toolbar', { name: 'Page controls' });
    await showBars(page, controls.getByRole('button', { name: 'Previous page' }));
    await controls.getByRole('button', { name: 'Read aloud', exact: true }).click({ timeout: 5000 });
    // the narration is followed until it has played to its end, failed, or shown a banner (or 20 s have passed)
    const state = () => {
      const a = document.getElementById('narration');
      const alert = [...document.querySelectorAll('[role=alert]')].filter(e => e.offsetParent !== null).map(e => e.innerText.trim()).filter(Boolean);
      return a ? { paused: a.paused, time: +a.currentTime.toFixed(2), src: a.src.slice(0, 20), error: a.error && a.error.code, alert, ended: a.ended,
        pressed: [...document.querySelectorAll('button[aria-pressed]')].filter(b => b.getAttribute('aria-label') === 'Read aloud').map(b => b.getAttribute('aria-pressed')) } : null;
    };
    // two samples: the audio is playing (its time is past 0), and it has moved a second of its own time on (or ended, failed, or a banner showed)
    let started = 0;
    for (const until of ['playing', 'advanced']) {
      await page.waitForFunction(([source, until, started]) => {
        const s = (0, eval)(source)();
        if (!s) return false;
        if (s.error || s.alert.length || s.ended) return true;
        return until === 'playing' ? s.time > 0 : s.time >= started + 1;
      }, [state.toString(), until, started], { timeout: 20000 }).catch(() => {});
      const sample = await page.evaluate(state);
      r.states.push(sample);
      started = sample ? sample.time : 0;
    }
    r.seen = await page.evaluate(() => window.__seen);
    r.screenshot = `${id}-narration.png`;
    await page.screenshot({ path: join(out.replace(/\.json$/, ''), r.screenshot) }).catch(() => {});
  } catch (e) { r.error = e.message.slice(0, 300); }
  await ctx.close();
  console.log(project, id, r.narrated, JSON.stringify(r.seen), r.error || '');
}
writeFileSync(out, JSON.stringify(results, null, 1));
await browser.close();
