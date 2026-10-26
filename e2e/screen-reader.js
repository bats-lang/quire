// Guidepup's Virtual Screen Reader inside the page under test (#925, #692). It is a
// simulation: the log is the library's rendering of the accessibility tree, not what NVDA
// or VoiceOver say (keyword: screen-reader, .claude/rules/interface.md).

import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
// the package's browser build: one ES module, no imports (the package's "browser" export)
const bundle = readFileSync(require.resolve('@guidepup/virtual-screen-reader/package.json')
  .replace(/package\.json$/, 'lib/esm/index.browser.js'), 'utf8');

/** Loads the Virtual Screen Reader into page as a module from a blob URL (once per page load) */
export async function loadScreenReader(page) {
  await page.evaluate(async source => {
    if (window.__virtual) return;
    const url = URL.createObjectURL(new Blob([source], { type: 'text/javascript' }));
    window.__virtual = (await import(url)).virtual;
    URL.revokeObjectURL(url);
  }, bundle);
}

/** The phrases the screen reader speaks moving forward through the element `container` (a
    CSS selector), from the container's own phrase to its "end of" phrase. The walk is bounded
    (400 moves): a container that never ends throws, it does not hang */
export async function spoken(page, container) {
  await loadScreenReader(page);
  return page.evaluate(async container => {
    const virtual = window.__virtual;
    await virtual.start({ container: document.querySelector(container) });
    try {
      await virtual.next();
      const opening = (await virtual.spokenPhraseLog())[0];
      for (let k = 0; k < 400; k++) {
        if ((await virtual.lastSpokenPhrase()) === 'end of ' + opening) return await virtual.spokenPhraseLog();
        await virtual.next();
      }
      throw new Error('the screen reader did not reach the end of ' + container);
    } finally {
      await virtual.stop();
    }
  }, container);
}

/** The phrases that name a control or a structure (a button, slider, tab, heading or list item), without the "end of" phrases, the empty phrases of icon contents and the
    words that depend on the layout (page numbers, percentages) */
export const structure = log => log.filter(p => /^(button|slider|tab|heading|listitem|navigation|toolbar|dialog)\b/.test(p));
