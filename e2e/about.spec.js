// The About screen, opened from Settings: the app's name and links out
// of the app to its home page, privacy policy, terms and source. The
// pages are published beside the app (homepage/), and the app's service
// worker leaves them to the network: it neither answers them nor keeps
// them (bridge's produce_service_worker answers only the app's own
// files, directly in its scope).

import { test, expect } from './fixtures.js';
import { start, dialog, librarySettings, settingsScreen, settingsButton, libraryMenu, menuItem, librarySearch } from './helpers.js';

const about = page => dialog(page, 'About Quire');
// each link's href, and the address it leads to from the app at
// baseURL: the pages beside the app relative to it, the source on GitHub
const links = {
  'Home page': ['./homepage/', '/homepage/'],
  'Privacy policy': ['./homepage/privacy.html', '/homepage/privacy.html'],
  'Terms of service': ['./homepage/terms.html', '/homepage/terms.html'],
  'Source code': ['https://github.com/bats-lang/quire', 'https://github.com/bats-lang/quire'],
};

test('Settings opens About, which shows the app and links out of it', async ({ page, baseURL }) => {
  const errors = await start(page);
  await librarySettings(page);
  await settingsButton(page, 'About Quire ›').click();
  await expect(about(page)).toBeVisible();
  await expect(about(page)).toContainText('Quire, an EPUB reader');
  // the version: the commit's UTC date, as packages are versioned, and its short SHA (#219)
  const version = about(page).getByText(/^\d{4}\.\d{1,2}\.\d{1,2}\.\d+ \([0-9a-f]{7,}\)$/);
  await expect(version).toBeVisible();
  await expect(about(page)).toContainText('Version');
  const group = about(page).getByRole('group', { name: 'Links' });
  for (const [name, [href, address]] of Object.entries(links)) {
    const link = group.getByRole('link', { name, exact: true });
    await expect(link).toBeVisible();
    await expect(link).toHaveAttribute('href', href);
    expect(await link.evaluate(a => a.href)).toBe(new URL(address, baseURL).href);
    // a new tab on the web (the system's browser on Android), told
    // nothing of the app
    await expect(link).toHaveAttribute('target', '_blank');
    await expect(link).toHaveAttribute('rel', /noopener/);
  }
  await expect(about(page).getByRole('button', { name: 'Done' })).toBeFocused();
  // Done goes back to Settings, at its About row
  await about(page).getByRole('button', { name: 'Done' }).click();
  await expect(about(page)).toBeHidden();
  await expect(settingsScreen(page)).toBeVisible();
  await expect(settingsButton(page, 'About Quire ›')).toBeFocused();
  // Escape closes About, then Settings
  await settingsButton(page, 'About Quire ›').click();
  await expect(about(page)).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(about(page)).toBeHidden();
  await expect(settingsScreen(page)).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(settingsScreen(page)).toBeHidden();
  expect(errors).toEqual([]);
});

test('the library menu opens About, next to Settings, and Escape goes back to the library', async ({ page, baseURL }) => {
  const errors = await start(page);
  await libraryMenu(page);
  const items = await page.getByRole('menu').getByRole('menuitem').allTextContents();
  expect(items.indexOf('About Quire')).toBe(items.indexOf('Settings') + 1);
  await menuItem(page, 'About Quire').click();
  await expect(about(page)).toBeVisible();
  await expect(page.getByRole('menu')).toBeHidden();
  await expect(settingsScreen(page)).toBeHidden();
  // its first link is the home page, beside the app
  const first = about(page).getByRole('group', { name: 'Links' }).getByRole('link').first();
  await expect(first).toHaveAccessibleName('Home page');
  await expect(first).toHaveAttribute('href', './homepage/');
  expect(await first.evaluate(a => a.href)).toBe(new URL('/homepage/', baseURL).href);
  await page.keyboard.press('Escape');
  await expect(about(page)).toBeHidden();
  await expect(librarySearch(page)).toBeVisible();
  // and Done, back at the library menu's button
  await libraryMenu(page);
  await menuItem(page, 'About Quire').click();
  await about(page).getByRole('button', { name: 'Done' }).click();
  await expect(about(page)).toBeHidden();
  await expect(page.getByRole('button', { name: 'Library menu' })).toBeFocused();
  expect(errors).toEqual([]);
});

test('the home page goes to the network, not the service worker', async ({ page }) => {
  await start(page);
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.reload();
  await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller)).toBe(true);
  // a request for the home page from the app: the worker does not answer it
  const fetched = [];
  page.on('response', r => { if (r.url().includes('/homepage/')) fetched.push(r.fromServiceWorker()); });
  const status = await page.evaluate(async () => (await fetch('homepage/')).status);
  expect(status).toBe(200);
  await expect.poll(() => fetched.length).toBeGreaterThan(0);
  expect(fetched.every(fromWorker => !fromWorker)).toBe(true);
  // nor a visit, though the pages are under the worker's scope
  for (const path of ['/homepage/', '/homepage/privacy.html', '/homepage/terms.html']) {
    const response = await page.goto(path);
    expect(response.status()).toBe(200);
    expect(response.fromServiceWorker()).toBe(false);
    await expect(page.getByRole('main')).toBeVisible();
  }
  // the home page leads back to the app beside it
  await page.goto('/homepage/');
  await page.getByRole('link', { name: 'Open Quire in your browser' }).click();
  await expect(page.getByRole('searchbox', { name: 'Search the library' })).toBeVisible();
  // and nothing of them is kept, while the app's files are
  await page.goto('/');
  const kept = await page.evaluate(async () => {
    const urls = [];
    for (const name of await caches.keys()) {
      for (const request of await (await caches.open(name)).keys()) urls.push(new URL(request.url).pathname);
    }
    return urls;
  });
  expect(kept).toContain('/manifest.json');
  expect(kept.filter(path => path.startsWith('/homepage'))).toEqual([]);
});
