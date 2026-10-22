// Renders a page in Chromium and writes its text, for pages a plain fetch cannot read (script-rendered, or blocking bots).
// usage: node get.mjs <out-name> <url> [wait-ms]  -> writes <out-name>.txt (rendered innerText) and prints status/length
import { chromium } from 'playwright';
import { writeFileSync } from 'node:fs';
const [name, url, wait = '4000'] = process.argv.slice(2);
// the browser the locked Playwright expects, unless QUIRE_BROWSER_EXECUTABLE names another (#776: no path pinned by hand)
const browserPath = process.env.QUIRE_BROWSER_EXECUTABLE ? { executablePath: process.env.QUIRE_BROWSER_EXECUTABLE } : {};
const browser = await chromium.launch({ ...browserPath, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36', viewport: { width: 1280, height: 900 } });
const page = await ctx.newPage();
let status = 0;
try {
  const r = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
  status = r ? r.status() : 0;
  await page.waitForTimeout(Number(wait));
  const text = await page.evaluate(() => document.body.innerText);
  writeFileSync(`${name}.txt`, `URL: ${url}\nSTATUS: ${status}\n\n${text}`);
  console.log(name, status, text.length);
} catch (e) { console.log(name, 'ERR', String(e.message).split('\n')[0]); }
await browser.close();
