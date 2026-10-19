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
* Playwright 1.58 or later is required (the fake clock; the reason and the check are pwa's:
  `gen-pwa test` and its `e2e-setup` action, bats-lang/pwa's CLAUDE.md). That floor is the
  fake clock's and stays 1.58 (`playwright-minimum`); the version quire is pinned to is
  **1.61.0** (#599), the oldest with the headless shell of Chromium 149.0.7827.55 (revision
  1228), which has upstream's fix of the launch crash (a `setenv` of `FC_FONTATIONS` racing a
  `getenv` on another thread, fixed in 149.0.7798.0, commit 970a6d5; 1.58.2 to 1.60.0 ship 145,
  147 and 148, which still have it). A machine whose Chromium is older than the one the pin
  expects points `PLAYWRIGHT_BROWSERS_PATH` at a directory whose
  `chromium_headless_shell-1228/chrome-headless-shell-linux64/chrome-headless-shell` links to
  the installed `headless_shell`; it does not downgrade Playwright.

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

Every spec takes `test` from `e2e/fixtures.js` (`e2e/global-setup.js` refuses one that does
not). Its auto fixture `stallWatch` (`e2e/stall-capture.js`) arms each page with a DevTools
session of its own (debugger enabled, breakpoints inactive: a page already stuck in a loop
can no longer be attached to), asks it to evaluate `1` every 2 s, and captures a page that
does not answer within 5 s, and every page of a test 15 s before its timeout: the frames
`Debugger.pause` stops in, a CPU profile, the renderers' CPU time, threads and `/proc` state,
the machine's load and pressure, and native stacks and a core. The capture is
`stall-capture-<n>.json` in the test's output (CI's `e2e-stall-captures-<group>` artifact).
`e2e/stall-capture.spec.js` checks it; its long tests run in the desktop project only.
`QUIRE_NO_STALL_ARM=1` skips arming (to compare stall rates); nothing sets it.

* **Native stacks (gdb)** are taken **only when a page answers nothing AND no renderer used
  `FROZEN_CPU_SECONDS` of CPU over the capture's 1 s window** (a DevTools target has no
  process id, so any renderer's CPU means the page is presumed busy, `presumedBusy`). Every
  idle renderer is then attached to (at most 6): gdb's backtrace of every thread, the kernel's
  stack and wait channel, and what resolves offsets later (binary path, build id, `exeBase`).
  It is taken before the pause and the profile, which change what the renderer does.
* **gdb is ended with KILL, never TERM or INT** (`stop()` after `TEARDOWN_MS`): a gdb ended by
  TERM or INT stays attached and the renderer stays stopped. Every external command runs in
  its own process group under `timeout -s KILL` inside sudo.
* **Nothing is installed by the capture.** gdb comes from the e2e jobs' `Install gdb` step in
  `check.yml` (a stopgap that never fails a job; pwa's e2e-setup action should install it,
  bats-lang/pwa#109); `QUIRE_STALL_GDB` names another. Without gdb, or with ptrace or sudo
  refused, the e2e run as before and nothing goes red: the capture records `native.unavailable`
  and the spec's native tests skip with that reason, on CI too.
* **When gdb gives no stacks** (not installed, or the kernel refuses its attach) the capture asks
  `eu-stack` (the job installs `elfutils` beside gdb) and then `pstack` for the renderer's
  user-space stacks, and each renderer's `userSpaceStacks` says which answered (`gdb`, `eu-stack`,
  `pstack`) or `not available: <why for each tool>` (`fallbackStacks.tried` has each tool's text,
  exit code and note). The kernel's view of the other browser processes (the browser's, the GPU's)
  is `native.browserProcesses`: their threads, wait channels and syscalls, never attached to.
  `ptraceScope`, `root`, the maps, the build id and the kernel stack of every thread are always
  recorded. Pure fallback: a step that fails is a note in the capture, never a red test.
* **A core** of up to `CORE_MOST` renderers, gzipped, is uploaded as `e2e-stall-cores-<group>`
  only when one was kept. gdb first calls `madvise(MADV_DONTDUMP)` on the mappings with no
  resident page (`quietRanges`), or `generate-core-file` never finishes. Over `CORE_MAX_BYTES`
  or `CORE_GZ_MAX_BYTES` the core is removed and the capture says why; a core is never asked of
  a process in a group stop; a failed core never fails a test (`core.reason`).
* The Playwright headless shell has no symbols (frames are `?? ()` with an offset from
  `exeBase`); system libraries are named by libc6-dbg. debuginfod is not used (a download with
  the process stopped has no bound).

* **A page that was slow, not frozen, says whether the runner or the page was slow (#600).** The
  captures above are for a page that answers nothing; a test can also fail on a page that answered
  late (`giant-text-highlights.spec.js`, 2026-10-14: the runner looked about twice as slow, and no
  capture covered the click). Three records, all of them notes, none able to fail or hang a test (a
  source that cannot be read is written as `not available: <why>`; every DevTools read has a limit,
  `METRICS_MS`, `HARVEST_MS`):
  * `e2e/runner-load.js` samples the worker every 2 s and keeps 45 samples: `/proc/pressure/{cpu,io,memory}`
    (`some` and `full` averages, and the time stalled in the interval from the totals' difference),
    `/proc/loadavg`, `/proc/stat`'s share of the interval in user, system, iowait, steal and idle (a
    difference of the counters), the CPU seconds of each process under the worker (the browsers, with
    their `--type`) and of the four busiest other processes, and how late the worker's own timer fired.
    No threshold is applied: the kernel's PSI documentation and LWN give no value of `avg10` that
    separates contention from none, and none was found for steal, so the summary (`runnerLoad().summary`,
    with a `reading` sentence) states peaks, means and the cores' worth of CPU the browsers used, and the
    reader judges. The sampler runs for the worker's life, so its buffer (45 samples, 90 s) holds the tests
    before the current one (each sample names its `test`): the load before a test is the evidence for "the
    runner was slow" (#715; Chrome's tracing has a ring buffer, `recordContinuously`, for the same reason,
    Playwright's documentation says it records a `trace.zip` for each test; that it is per test because it is a reproduction, not a history, is this project's inference, not documented). Every capture holds
    `runnerLoad` (the last minute), and a test that did not end as expected (failed, timed out) attaches
    `runner-load.json`, captured or not; both it and `page-timing.json` are in the `e2e-stall-captures-<group>`
    artifact (#715). A page that did not answer a DevTools read is not asked again for 5 s (`DEAF_MS`, Hystrix's sleep window; the probe's next answer, within 2 s, ends it), so a
    frozen page costs an attempt one wait, not one before and one after each.
  * `e2e/attempt-log.js`: the helpers that try again (`toLibrary`, `showChrome` per tap, `clickControl`,
    `releaseClick`) run each try through `attempted(page, step, attempt, work, detail)`, which notes
    its start, duration, outcome, the first line of why it failed (and, from the helper, why it tried
    again: `noted`), and what the main thread did meanwhile from `Performance.getMetrics` before and
    after (`devtools`: task, script, layout and style milliseconds, and the CPU the thread and process got,
    so a main thread that ran tasks but got little CPU is a runner that did not give it, and one that got
    what it used is a slow page). A page with no log bound (not armed by the watch) runs the work as before.
    `getMetrics` is answered by a busy page (measured with a script loop); when it is not, the entry says so.
  * Long tasks: `arm` installs a `PerformanceObserver` for `longtask` and `long-animation-frame` in the
    page (`__quireStall`, not enumerable; entries with epoch `at`, duration, blocking time, where style
    and layout began, and the scripts), which the 2 s probe and a failed attempt take. They are kept in
    node, since a failed test's pages are closed before its fixtures end. Work started from DevTools
    (`Runtime.evaluate`) is not a task of the frame and is not seen; the page's own timers are.
  A failed test attaches `page-timing.json` (each page's `attempts` and `longTasks`), and a capture has
  `pageTiming`. The JSON of a capture only gained fields. `e2e/stall-capture.spec.js` checks the fields,
  the attempt log, and that a stuck page or an unarmed one gives a note and no failure.
