# ux-review (#293)

Screenshots and measurements of Quire's screens for the UX review on issue #293. Not part of the app or CI.

* `capture.spec.js`: the happy path in four flows (`first-run-library`, `reading`, `settings-sync`, `trash-errors`), one
  screenshot per step into `shots/<path>/<NN-name>/<viewport>-<theme>.png`. Run with
  `THEME=light|dark npx playwright test -c ux-review/playwright.config.js --project=android|narrow|desktop`
  from the repository root, with `dist/pwa` built (or taken from a `quire-android` CI artifact's `pwa/`).
  Light is 12:00 and dark 23:00 with the theme on Auto.
* `shown.spec.js` + `shown-measures.js`: walks every screen (e2e/walk.js) and measures it from the DOM: text and
  placeholder contrast, whether a chosen tab or an on switch is told apart by 3:1, rows an element covers in part, and the
  share of the window each panel takes. Writes `shots/measures-<project>-<theme>.json`.
* A CJK font must be installed for the vertical (Japanese) book: without one the kanji fall back to a font with no
  vertical metrics and overlap. (Noto Sans JP, as a file in `~/.fonts`, with fontconfig preferring it for `ja`.)

* `fetch-rendered.mjs <name> <url> [wait-ms]`: renders a script-built page in Chromium and writes its text to `<name>.txt` (used to read m3.material.io, Amazon and Kobo help).
