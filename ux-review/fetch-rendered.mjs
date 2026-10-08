// Renders a page in Chromium and writes its text, for pages a plain fetch cannot read (script-rendered, or blocking bots).
// usage: node get.mjs <out-name> <url> [wait-ms]  -> writes <out-name>.txt (rendered innerText) and prints status/length
import { chromium } from 'playwright';
import { writeFileSync } from 'node:fs';
const [name, url, wait = '4000'] = process.argv.slice(2);
const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
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
