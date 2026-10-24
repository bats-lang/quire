// Throwaway survey for quire#827 (piece 1 of quire#419): what the three
// survey scripts share. A project is one of playwright.config.js's
// (`desktop`, `android`), played the way the e2e suite plays it
// (e2e/fixtures.js: Android's user agent, touch, a Pixel's viewport, its
// safe-area insets and the app's Capacitor), so the survey sees the
// reader as the suite's specs do.
//
// Nothing here waits for a time: a wait is for a condition of the page
// (an element, a changed key, a frame in which the page is as it was).
import { chromium } from '@playwright/test';
import { androidApp, androidInsets } from '../e2e/fixtures.js';

const ANDROID_USER_AGENT = 'Mozilla/5.0 (Linux; Android 15; Pixel 8 Build/AP4A.250105.002; wv) '
  + 'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/140.0.7339.207 Mobile Safari/537.36';

export const projects = {
  desktop: { viewport: { width: 1024, height: 768 } },
  android: {
    viewport: { width: 412, height: 915 }, deviceScaleFactor: 2.625, isMobile: true, hasTouch: true,
    userAgent: ANDROID_USER_AGENT,
  },
};

export function projectOf(name) {
  if (!projects[name]) throw new Error(`project ${name}: one of ${Object.keys(projects).join(', ')}`);
  return name;
}

export const launch = (extraArgs = []) => chromium.launch({
  args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage', ...extraArgs],
  env: { ...process.env, FC_FONTATIONS: '1' },
});

/** A context and page of the project; the page in android has its insets and the app's Capacitor */
export async function newPage(browser, project) {
  const context = await browser.newContext(projects[project]);
  await context.route('https://accounts.google.com/**', route => route.fulfill({
    status: 200, headers: { 'content-type': 'text/javascript' }, body: '',
  }));
  if (project === 'android') await context.addInitScript(androidApp);
  const page = await context.newPage();
  if (project === 'android') await androidInsets(page);
  return { context, page };
}

export const pageDoc = page => page.getByRole('document', { name: 'Page' });
export const cards = page => page.getByRole('region', { name: /^(Continue reading|Books)$/ }).getByRole('group');

/** Resolves in a frame in which the page is as it was for five frames running (fonts loaded, the text and the number of elements unchanged) */
export const settled = page => page.evaluate(async () => {
  await document.fonts.ready;
  const frame = () => new Promise(resolve => requestAnimationFrame(() => resolve()));
  let last = '';
  for (let stable = 0, frames = 0; stable < 5 && frames < 600; frames++) {
    await frame();
    const now = document.body.innerText.length + ':' + document.querySelectorAll('*').length;
    if (now === last) stable++; else { stable = 0; last = now; }
  }
});

/** What the reader shows of where it is: the page's text and its status */
export const pageKey = () => {
  const doc = document.querySelector('[role=document]');
  const status = document.querySelector('[role=status]');
  return (doc ? doc.textContent.slice(0, 200) : '') + '|' + (status ? status.textContent : '');
};

/** A click on the button by its label (or text), as a DOM event: the bars may be down */
export const domClick = (page, label) => page.evaluate(label => {
  const b = [...document.querySelectorAll('button')].find(b => (b.getAttribute('aria-label') || b.textContent).trim().startsWith(label));
  if (!b || b.disabled) return false;
  b.click();
  return true;
}, label);

/** Clicks the button and waits until the reader shows another place, or `moved` is false when there is no such button */
export async function domClickMoves(page, label) {
  const before = await page.evaluate(pageKey);
  if (!(await domClick(page, label))) return false;
  await page.waitForFunction(([source, key]) => (0, eval)(source)() !== key, [pageKey.toString(), before], { timeout: 5000 }).catch(() => {});
  await settled(page);
  return true;
}

/** Imports the books into a fresh library, one after the other, each waited for as a card */
export async function importBooks(page, base, files) {
  await page.goto(base + '/');
  await page.locator('#import-file').waitFor({ state: 'attached', timeout: 15000 });
  for (const [k, file] of files.entries()) {
    await page.locator('#import-file').setInputFiles(file);
    await page.waitForFunction(n => document.querySelectorAll('[role=region] [role=group]').length >= n, k + 1, { timeout: 20000 }).catch(() => {});
  }
  await settled(page);
}

/** Opens the first book of the library */
export async function openFirst(page) {
  await cards(page).first().click();
  await pageDoc(page).waitFor({ timeout: 15000 });
  await settled(page);
}

/** A tap on the page below its text, where the bars come up (a tap on text a clip reads would move the narration) */
export async function showBars(page, bar) {
  for (let k = 0; k < 3 && !(await bar.isVisible()); k++) {
    const box = await pageDoc(page).boundingBox();
    await pageDoc(page).click({ position: { x: box.width / 2, y: box.height * 0.92 } });
    await bar.waitFor({ timeout: 2000 }).catch(() => {});
  }
}
