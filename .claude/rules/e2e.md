---
paths:
  - e2e/**
  - playwright.config.js
---

# The e2e suite

## Projects and groups

Each group runs every project of `playwright.config.js`: `desktop` and
`mobile-portrait` every spec, `narrow` (320 px, WCAG's reflow width),
`mobile-landscape`, `tablet` and `wide` the specs their `testMatch` names, and
`android` every spec (#295): a Pixel-class phone, its bars as the safe area's
insets, and the app's Capacitor played in the page (`androidApp` in
`e2e/fixtures.js`), so bridge takes its Android branch. `scripts/ci-groups.py`
fails the run when the `android` project is missing or narrowed (a testMatch,
testIgnore or grep in it or over the configuration, or a --project or --grep on
CI's run); a spec that cannot apply on Android skips itself, saying why
(`test.skip`). `e2e/icons.spec.js` draws every icon character on a canvas, so
it does not hang on the machine's fonts.

## No flaky waits

* **Time-measuring tests are `@serial`** (the describes of `pathological.spec.js`
  and `page-turn.spec.js` with a budget): `gen-pwa test` runs them alone on one
  worker, then the rest on half the cores (#499). They stay the `perf` group
  alone and no spec that loads the machine joins it (`stall-capture.spec.js`
  spins a page on purpose), since the serial part would lengthen any group it
  joined. A budget keeps headroom over what a loaded runner has given, and
  still fails a turn that costs twice as much; a flaky budget is not relaxed
  until it catches nothing.
* **A bar's control is clicked with `clickControl`**, which shows the bars and
  clicks together until the click lands (the bars' 5 s timeout can hide them
  on a loaded machine).
* **Every raw pointer event goes through `rawMouse` (`e2e/helpers.js`)**, which
  calls `releaseClick` first before a click, double click or move made with no
  button held (quire#630: a timed-out locator click can leave Playwright's
  interceptor, which swallows the next raw event). `refuseRawMouse`
  (`e2e/fixtures.js`) replaces each test page's own `mouse` with an object
  whose methods throw, so a raw call fails the test however it is written;
  pages a spec makes itself are not guarded. `releaseClick` is a trial hover
  that moves the pointer to the viewport's centre, so never call it between a
  move and the press, wheel or release that depend on the pointer's place.
* **A test never waits in real time for a moment of the app's own** (#657: the
  bars' 5 s, the back button's 10 s, a toast's 2 s, the Nextcloud poll). It
  installs the fake clock before the page opens (`page.clock.install()`) and
  runs it to the moment: `expectMoment` (`e2e/helpers.js`) asserts the thing is
  there 1.5 s before the moment's end and gone 1.5 s after, `runUntil` runs the
  clock on in steps until an answer that comes in real time has come, and
  `settled` and `rested` (`e2e/relaunch.js`) do it for the relaunch and
  stability specs. Real time stays for the `@serial` budgets, the stall watch,
  media playback and anything that waits for a font or the network.
* Playwright 1.58 or later is required (its fake clock can set the time back
  after a `page.clock.fastForward`; 1.58 ignores a
  target in the past, so before it a spec that counts minutes lost one now and
  then). A machine whose Chromium is older than 1.58 expects runs 1.58.2 with
  `PLAYWRIGHT_BROWSERS_PATH` at a directory whose
  `chromium_headless_shell-1208/chrome-headless-shell-linux64/chrome-headless-shell`
  links to the installed `headless_shell`; it does not downgrade Playwright.

## Nothing of one book shows in the next (#435)

`e2e/two-books.spec.js` opens a book that has every per-book feature (Alpha:
nested contents, page list, note, ruby, narration, Japanese; bookmarks, a
highlight, a search, a jump, Columns Two) and then one that has none (Beta,
Hebrew), and checks each of Beta's panels, rows, bars and records is Beta's; a
vertical (Gamma) and a fixed-layout (Delta) book are opened before Beta for the
writing mode and the page box. Beta is opened from the library, from a
catalogue's Get and after a reload; Alpha again after Beta; the records kept
for Beta after Alpha equal those of Beta opened first in a profile of its own
(`reloadSettled` waits out the sync the android project makes as the app
opens). The books are in `e2e/two-books-books.js`, checked by epubcheck. A new
per-book feature is added to Alpha and checked absent in Beta.

By decision the narration's clip table is not probed (no test hook in the
shipped build): Beta offers no narration controls and the audio element is
paused and holds only a blob URL the app revoked.

## A page that stops answering in e2e explains itself (#244, #575, #591)

Every spec takes `test` from `e2e/fixtures.js` (`e2e/global-setup.js` refuses a
spec that does not). Its auto fixture `stallWatch` (`e2e/stall-capture.js`)
arms each page with a DevTools session of its own (debugger enabled,
breakpoints inactive: a page already stuck in a loop can no longer be attached
to), asks each page to evaluate `1` every 2 s, and captures a page that does
not answer within 5 s, and every page of a test 15 s before its timeout:
the frames `Debugger.pause` stops in, a CPU profile, the renderers' CPU time,
threads and `/proc` state, the machine's load and pressure, and the native
stacks and a core below. The capture is `stall-capture-<n>.json` in the
test's output (CI's `e2e-stall-captures-<group>` artifact), attached to the
test. `e2e/stall-capture.spec.js` checks it; its long tests run in the desktop
project only.

**Native stacks (gdb).** A frozen renderer sits in an untimed futex wait and
JS cannot say who it waits for. gdb stops the process it attaches to, so it is
attached **only when a page answers nothing AND no renderer used
`FROZEN_CPU_SECONDS` of CPU over the capture's 1 s window**. A DevTools target
has no process id, so the rule is about all renderers: if any used CPU, the
page is presumed busy (`presumedBusy`) and nothing is attached; if every one is
idle, every idle renderer is attached to, the other pages' too. A healthy job
runs nothing.

* The `native` field has, per renderer (at most 6): gdb's backtrace of every
  thread, the kernel's stack, wait channel and state of each thread, and what
  resolves offsets later (binary path, build id, `exeBase`, per-frame module
  and offset). It is taken before the pause and the profile, which change what
  the renderer does, and written at once, so a teardown keeps it.
* `stop()` waits `TEARDOWN_MS` for captures running, then **ends their
  commands with KILL, never TERM or INT**: a gdb ended by TERM or INT stays
  attached and the renderer stays stopped; only a killed gdb is detached by the
  kernel. Every external command runs in its own process group under
  `timeout -s KILL` inside sudo (worst case `NATIVE_MOST_MS`).
* **Nothing is installed by the capture.** gdb comes from the e2e jobs'
  `Install gdb` step in `check.yml` (a stopgap that never fails a job; pwa's
  e2e-setup action should install it, bats-lang/pwa#109); `QUIRE_STALL_GDB`
  names another. **Without gdb, or with ptrace or sudo refused, the e2e run
  exactly as before and nothing goes red for it**: the capture records
  `native.unavailable` with the reason and carries on with the JS/wasm
  capture, and the spec's native tests skip with that reason, on CI too.
* **A core** of up to `CORE_MOST` renderers, gzipped, is uploaded as
  `e2e-stall-cores-<group>` (7 days) only when one was kept. gdb first calls
  `madvise(MADV_DONTDUMP)` on the mappings with no resident page (`quietRanges`),
  or `generate-core-file` reads 1.4 TB of reservations and never finishes.
  Caps: `CORE_MAX_BYTES` (`prlimit --fsize`) and `CORE_GZ_MAX_BYTES`, over
  either the core is removed and the capture says why. A core is never asked
  of a process in a group stop (SIGSTOP). A failed core never fails a test or a
  capture (`core.reason`). A core holds only the fixtures' pages, books and the
  app, never a user's data.
* The Playwright-built headless shell is stripped and Google publishes no
  symbols for it, so its frames are `?? ()` with an offset from `exeBase`;
  system libraries are named by libc6-dbg, which the Install gdb step adds
  where it can. debuginfod is not used (a download with the process stopped has
  no bound).

**`QUIRE_NO_STALL_ARM=1`** skips arming (`arm` in `e2e/stall-capture.js`): the
debugger is never enabled and the capture says `armed: false`; it still probes
with `page.evaluate` and takes native stacks under the same rule, and loses the
pause and the profile. It exists to compare the stall rate with and without
arming. The default stays armed and nothing sets it: a scheduled run that does
is a change of its own.
