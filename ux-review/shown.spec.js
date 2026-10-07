// Runs the e2e walk (every screen, sheet and tab the layout spec opens)
// and measures each with shown-measures.js; writes shots/measures-<project>-<theme>.json.
// A report, not an assertion: it shows what such checks would find on main.

import { test } from '../e2e/fixtures.js';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { walkEveryScreen, appPlayed } from '../e2e/walk.js';
import { textContrastShort, stateCueShort, rowsCutByScroller, rowsCovered, panelShare } from './shown-measures.js';

const THEME = process.env.THEME || 'light';

test('measure every screen', async ({ page }, info) => {
  await page.clock.setFixedTime(new Date(THEME === 'dark' ? '2026-10-07T23:00:00' : '2026-10-07T12:00:00'));
  await page.addInitScript(appPlayed);
  const found = {};
  await walkEveryScreen(page, {
    look: async screen => {
      found[screen] = {
        text: await textContrastShort(page),
        state: await stateCueShort(page),
        cut: [...await rowsCutByScroller(page), ...await rowsCovered(page)],
        panels: await panelShare(page),
      };
    },
    back: () => page.keyboard.press('Escape'),
  });
  mkdirSync('shots', { recursive: true });
  writeFileSync(join('shots', `measures-${info.project.name}-${THEME}.json`), JSON.stringify(found, null, 1));
});
