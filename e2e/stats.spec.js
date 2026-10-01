// Reading statistics: the minutes read each day, the week's, the days
// read in a row, the books finished this year and a daily goal; each
// book's time and speed in Book info; all of it kept in a backup.

import { test, expect } from '@playwright/test';
import { readFileSync, writeFileSync } from 'node:fs';
import {
  start, readBook, place, placeChanged, toLibrary, chapters, dialog, menuItem, libraryMenu, bookMenu,
  oneColumn, reload, openBook, cards,
  librarySettings, settingsButton, restoreInput,
} from './helpers.js';

const book = (title, n = 3, paras = 60) => ({ title, author: 'Stats Tests', rawChapters: chapters(n, paras) });
const statsPanel = page => dialog(page, 'Reading statistics');
const stat = (page, id) => page.locator(`#${id}`);

async function openStats(page) {
  await libraryMenu(page);
  await menuItem(page, 'Reading statistics').click();
  await expect(statsPanel(page)).toBeVisible();
}

// Turns n pages, a minute apart
async function readMinutes(page, n) {
  for (let k = 0; k < n; k++) {
    const before = await place(page);
    await page.clock.fastForward('01:00');
    await page.keyboard.press('ArrowRight');
    await placeChanged(page, before);
  }
}

test('the statistics count the minutes read today, this week and the days in a row, against a daily goal', async ({ page }) => {
  await page.clock.install({ time: new Date('2026-06-01T10:00:00Z') });
  const errors = await start(page);
  await openStats(page);
  await expect(stat(page, 'stats-today')).toHaveText('0 min');
  await expect(stat(page, 'stats-streak')).toHaveText('0 days');
  await expect(stat(page, 'stats-finished')).toHaveText('0 books');
  await expect(statsPanel(page).getByRole('button', { name: 'Off' })).toHaveAttribute('aria-pressed', 'true');
  await statsPanel(page).getByRole('button', { name: 'Done' }).click();
  await expect(statsPanel(page)).toBeHidden();

  await readBook(page, book('Counted'));
  await oneColumn(page);
  await readMinutes(page, 5);
  await toLibrary(page);
  await openStats(page);
  await expect(stat(page, 'stats-today')).toHaveText('5 min');
  await expect(stat(page, 'stats-week')).toHaveText('5 min');
  await expect(stat(page, 'stats-streak')).toHaveText('1 day');
  // a goal: today's minutes are shown against it
  await statsPanel(page).getByRole('button', { name: '20 min' }).click();
  await expect(statsPanel(page).getByRole('button', { name: '20 min' })).toHaveAttribute('aria-pressed', 'true');
  await expect(statsPanel(page).getByRole('button', { name: 'Off' })).toHaveAttribute('aria-pressed', 'false');
  await expect(stat(page, 'stats-today')).toHaveText('5 min of 20 min');
  await page.keyboard.press('Escape');
  await expect(statsPanel(page)).toBeHidden();

  // kept across a reload
  await reload(page);
  await expect(cards(page)).toHaveCount(1);
  await openStats(page);
  await expect(stat(page, 'stats-today')).toHaveText('5 min of 20 min');
  await expect(statsPanel(page).getByRole('button', { name: '20 min' })).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');

  // the next day: a new day's minutes, the week's sum, two days in a row
  await page.clock.fastForward('24:00:00');
  await openBook(page, 'Counted');
  await readMinutes(page, 3);
  await toLibrary(page);
  await openStats(page);
  await expect(stat(page, 'stats-today')).toHaveText('3 min of 20 min');
  await expect(stat(page, 'stats-week')).toHaveText('8 min');
  await expect(stat(page, 'stats-streak')).toHaveText('2 days');
  await page.keyboard.press('Escape');

  // a day missed: the streak is over
  await page.clock.fastForward('48:00:00');
  await openStats(page);
  await expect(stat(page, 'stats-today')).toHaveText('0 min of 20 min');
  await expect(stat(page, 'stats-streak')).toHaveText('0 days');
  expect(errors).toEqual([]);
});

test('a long pause is not reading time, and a finished book counts for its year', async ({ page }) => {
  await page.clock.install({ time: new Date('2026-06-01T10:00:00Z') });
  await start(page);
  await readBook(page, book('Short', 1, 30));
  await oneColumn(page);
  await readMinutes(page, 2);
  // half an hour away from the book
  const before = await place(page);
  await page.clock.fastForward('30:00');
  await page.keyboard.press('ArrowRight');
  await placeChanged(page, before);
  // to its last page
  for (let k = 0; k < 40; k++) {
    const at = await place(page);
    if (at.p >= at.t) break;
    await page.keyboard.press('ArrowRight');
    await placeChanged(page, at);
  }
  await toLibrary(page);
  await openStats(page);
  await expect(stat(page, 'stats-today')).toHaveText('2 min');
  await expect(stat(page, 'stats-finished')).toHaveText('1 book');
});

test('Book info shows the time a book has been read and its pages an hour', async ({ page }) => {
  await page.clock.install({ time: new Date('2026-06-01T10:00:00Z') });
  await start(page);
  await readBook(page, book('Timed'));
  await toLibrary(page);
  await bookMenu(page, 'Timed');
  await menuItem(page, 'Book info').click();
  const info = dialog(page, 'Book info');
  await expect(info.locator('#info-time')).toHaveText('Not yet');
  await expect(info.locator('#info-speed-row')).toBeHidden();
  await info.getByRole('button', { name: '← Library' }).click();

  await openBook(page, 'Timed');
  await oneColumn(page);
  await readMinutes(page, 4);
  await toLibrary(page);
  await bookMenu(page, 'Timed');
  await menuItem(page, 'Book info').click();
  await expect(info.locator('#info-time')).toHaveText('4 min');
  await expect(info.locator('#info-speed')).toHaveText('60 pages an hour');
});

test('a backup keeps the reading log, the goal and each book\'s time, and a restore puts them back', async ({ page }, testInfo) => {
  await page.clock.install({ time: new Date('2026-06-01T10:00:00Z') });
  await start(page);
  await readBook(page, book('Logged'));
  await oneColumn(page);
  await readMinutes(page, 6);
  await toLibrary(page);
  await openStats(page);
  await statsPanel(page).getByRole('button', { name: '30 min' }).click();
  await page.keyboard.press('Escape');

  await librarySettings(page);
  const download = page.waitForEvent('download');
  await settingsButton(page, 'Export backup').click();
  const json = readFileSync(await (await download).path(), 'utf8');
  await settingsButton(page, 'Done').click();
  const b = JSON.parse(json);
  expect(b.settings.dailyGoal).toBe(30);
  const today = Math.floor(Date.parse('2026-06-01T10:00:00Z') / 86400000);
  expect(b.readingLog).toEqual([[today, 6]]);
  expect(b.books[0]).toMatchObject({ readMinutes: 6, readPages: 6, finished: 0 });

  // another device's log: an earlier day, and more of today
  b.readingLog = [[today, 9], [today - 1, 15]];
  b.settings.dailyGoal = 10;
  const path = testInfo.outputPath('stats-backup.json');
  writeFileSync(path, JSON.stringify(b));
  await librarySettings(page);
  await restoreInput(page).setInputFiles([path]);
  await expect(dialog(page, 'Backup restored')).toBeVisible();
  await dialog(page, 'Backup restored').getByRole('button').first().click();
  await openStats(page);
  await expect(stat(page, 'stats-today')).toHaveText('9 min of 10 min');
  await expect(stat(page, 'stats-week')).toHaveText('24 min');
  await expect(stat(page, 'stats-streak')).toHaveText('2 days');
});

test.describe('in Auckland (UTC+12 in June)', () => {
  test.use({ timezoneId: 'Pacific/Auckland' });

  test('the reading log counts the local day, not the UTC one', async ({ page }) => {
    // 20:00 UTC on 1 June is 08:00 on 2 June in Auckland
    await page.clock.install({ time: new Date('2026-06-01T20:00:00Z') });
    await start(page);
    await readBook(page, book('Local'));
    await oneColumn(page);
    await readMinutes(page, 3);
    await toLibrary(page);
    await openStats(page);
    await expect(stat(page, 'stats-today')).toHaveText('3 min');
    await page.keyboard.press('Escape');
    await librarySettings(page);
    const download = page.waitForEvent('download');
    await settingsButton(page, 'Export backup').click();
    const b = JSON.parse(readFileSync(await (await download).path(), 'utf8'));
    const localDay = Math.floor(Date.parse('2026-06-02T00:00:00Z') / 86400000);
    expect(b.readingLog).toEqual([[localDay, 3]]);
  });
});
