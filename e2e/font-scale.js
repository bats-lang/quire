// Android's system font scale, played in Chromium (#412, #1029): shared by the
// specs that run a screen at a scale (font-scale.spec.js, library-grouping.spec.js,
// touch-selection.spec.js). Keyword: font-scale.
//
// `text-size-adjust` takes effect in a mobile viewport only, so a spec that
// scales text runs in a project with `isMobile` (the android project) or
// sets `test.use({ isMobile: true })`.

/** The script that makes every text size of the page scale percent of
    itself, before the app starts */
export function scaledBy(percent) {
  // (a constructable style sheet: the app's content security policy
  // refuses a <style> element made by a script, not the CSSOM)
  return `(() => { const sheet = new CSSStyleSheet(); sheet.replaceSync('html { text-size-adjust: ${percent}%; -webkit-text-size-adjust: ${percent}%; }'); document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet]; })();`;
}
