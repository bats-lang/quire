import { test, expect } from './fixtures.js';
import { start, importInput, importFiles, openBook, bookPage, cards, visibleText, openReadingSettings, readingSettings } from './helpers.js';
import { readFileSync } from 'node:fs';

const ids = (process.env.PROBE || '').split(',').filter(Boolean);
for (const id of ids) {
  test(`probe ${id}`, async ({ page }) => {
    await start(page);
    const file = { name: id + '.epub', mimeType: 'application/epub+zip', buffer: readFileSync(`/tmp/w3c-epubs/${id}.epub`) };
    await importInput(page).setInputFiles(file);
    await page.waitForTimeout(2500);
    console.log(id, 'cards', await cards(page).count(), 'banner', await page.getByRole('alert').allInnerTexts());
    if (await cards(page).count()) {
      await cards(page).first().click();
      await page.waitForTimeout(3000);
      console.log(id, 'TEXT', JSON.stringify((await bookPage(page).innerText().catch(() => 'none')).slice(0, 400)));
      if (id === 'pss-support') { await bookPage(page).getByText('this link').click(); await page.waitForTimeout(800); console.log('POPUP', JSON.stringify(await page.getByRole('dialog').allInnerTexts())); }
      if (id.startsWith('cnt-css-fonts')) {
        await openReadingSettings(page, 'Look');
        await readingSettings(page).getByRole('button', { name: 'Book', exact: true }).click();
        await page.waitForTimeout(1500);
        await page.keyboard.press('Escape');
        console.log('FONT', await bookPage(page).locator('li').first().evaluate(e => getComputedStyle(e).fontFamily), await page.evaluate(() => [...document.fonts].map(f => f.family + ':' + f.status).join('|')));
      }
      await page.screenshot({ path: `/tmp/probe-${id}.png` });
    }
  });
}
