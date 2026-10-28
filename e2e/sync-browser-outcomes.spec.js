// Google Drive in a browser (google_token_get_answer, keyword: google-token-answer):
// each outcome of the sign-in is said as its own, where the reader is. Google
// Identity Services is played (identityServicesPlayed): the reader closes its
// window, Google answers an error and no token, an answer whose token cannot be
// read, a token client that throws, a script that does not load.

import { test, expect, clientsServed } from './fixtures.js';
import { dialog, librarySettings, settingsButton, libraryShown } from './helpers.js';
import { drive, CLIENT, identityServicesPlayed } from './sync-stores.js';

const panel = page => dialog(page, 'Sync');
const status = page => panel(page).getByRole('status');
const banner = page => page.getByRole('alert');
const googleDrive = page => panel(page).getByRole('button', { name: 'Google Drive' });
const clipboard = page => page.evaluate(() => navigator.clipboard.readText());

async function browserDevice(browser, { script = true } = {}) {
  const context = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  if (script) await identityServicesPlayed(context);
  else await context.route('https://accounts.google.com/**', route => route.abort());
  await context.route('https://www.googleapis.com/**', drive().handle);
  await clientsServed(context, { googleWebClient: CLIENT });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  await page.goto('/');
  await expect(libraryShown(page)).toBeVisible();
  await librarySettings(page);
  await settingsButton(page, 'Sync').click();
  await expect(panel(page)).toBeVisible();
  await googleDrive(page).click();
  await expect(panel(page)).toContainText('Google signs you in for an hour at a time');
  return { context, page, errors };
}

const OUTCOMES = [
  ['TokenRefused', 'refused', "Google did not give a token. Try again; if it fails again, copy the details and post them in a report.", /Answer, as text: .*invalid_request/],
  ['TokenThrown', 'throws', "The request to Google failed. Try again; if it fails again, copy the details and post them in a report.", /Answer, as text: .*initTokenClient threw/],
  ['TokenAnswerUnread', 'unreadable', "Google's answer could not be read. Try again; if it fails again, copy the details and post them in a report.", /Answer, as text: .*the answer cannot be read/],
];

for (const [code, flag, said, answer] of OUTCOMES) {
  test(`in a browser, Google's ${code} is said as its own, with its details`, async ({ browser }) => {
    const web = await browserDevice(browser);
    await web.page.evaluate(name => { window.__gis[name] = true; }, flag);
    await googleDrive(web.page).click();
    const text = `${said} Details: ${code}`;
    await expect(banner(web.page)).toHaveText(new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
    await expect(status(web.page)).toHaveText(text);
    await banner(web.page).getByRole('button', { name: 'Copy details' }).click();
    await expect.poll(() => clipboard(web.page)).toContain(`Platform: web browser\nWhile: signing in to Google\nCall: google_token_get_answer\nCode: ${code}`);
    expect(await clipboard(web.page)).toMatch(answer);
    await web.context.close();
  });
}

test('in a browser, Google\'s script not loading is said as its own, with its details', async ({ browser }) => {
  const web = await browserDevice(browser, { script: false });
  await googleDrive(web.page).click();
  const said = "Google's sign-in page did not load. Check the connection, then try again; if it fails again, copy the details and post them in a report.";
  await expect(banner(web.page)).toHaveText(new RegExp('^' + said.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ' Details: TokenLoadFailed'));
  await banner(web.page).getByRole('button', { name: 'Copy details' }).click();
  await expect.poll(() => clipboard(web.page)).toContain('Call: google_token_get_answer\nCode: TokenLoadFailed');
  await web.context.close();
});

test('in a browser, the reader closing Google\'s window is a cancel, said quietly', async ({ browser }) => {
  const web = await browserDevice(browser);
  await web.page.evaluate(() => { window.__gis.closed = true; });
  await googleDrive(web.page).click();
  await expect(status(web.page)).toHaveText('Google sign-in was canceled.');
  await expect(banner(web.page)).toBeHidden();
  await web.context.close();
});
