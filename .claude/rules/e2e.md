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
  clicks together until the click lands (a turn or a jump takes the bars down; no timer does, #560).
* **Every raw pointer event goes through `rawMouse` (`e2e/helpers.js`)**, which
  calls `releaseClick` first before a click, double click or move made with no
  button held (quire#630: a timed-out locator click can leave Playwright's
  interceptor, which swallows the next raw event). `refuseRawMouse`
  (`e2e/fixtures.js`) replaces each test page's own `mouse` with an object
  whose methods throw, so a raw call fails the test however it is written;
  pages a spec makes itself are not guarded. `releaseClick` is a trial hover
  that moves the pointer to the viewport's centre, so never call it between a
  move and the press, wheel or release that depend on the pointer's place.
* **The fake clock** (#657: the back button's 10 s, a toast's 2 s, the Nextcloud
  poll; the rule that a test never waits in real time for a moment of the app's own
  is pitboss's `engineering.md`). A test
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

## A worker's machine matches CI (#713)

What CI has, and the one command each takes here (the rule that a missing tool is
never a reason to skip a spec is pitboss's `rules.md`, "Briefs and workers"):

* **Speech voices: CI has none, and neither does a worker's machine, and the
  Read aloud tab is built either way.** #713 started from the belief that the
  tab is built only where Chromium reports voices. It is not: `aloud_offer`
  and `reader.bats` show it when `speech_available()` is true, which is
  bridge's `speechSynthesis && SpeechSynthesisUtterance` exist
  (`batsJsSpeechAvailable`), not `getVoices().length`; Chromium 149's headless
  shell has both objects with an empty voice list, here and on CI. Checked:
  the Ubuntu 24.04 runner image lists no speech-dispatcher, espeak or
  festival; CI's failing log of #705 (job 117771445057) shows the tab built
  and walked; `e2e/font-scale.spec.js` without its `voicesPlayed` stub
  passes here (android project, 7 of 7, Playwright 1.61.0, Chromium 149),
  its walk clicking the Read aloud tab. That failure was the CSS (`.ssel` capped
  at 12em, fixed in 8cb9f58), not the machine. `voicesPlayed` stays so the
  walk also has options in the Voice select. A spec that needs voices stubs
  them (`speechSynthesis` is defined by `addInitScript`, as `reader.spec.js`
  and others do): CI has no voices to count on. For a look at real ones,
  `apt-get install speech-dispatcher espeak-ng` and launch Chromium with
  `--enable-speech-dispatcher` (without the flag the headless shell asks
  speech-dispatcher for nothing, daemon or no daemon; with it, and espeak-ng's
  modules, `getVoices()` lists some 13,000 espeak variants): that is not what
  CI runs, so no spec is to depend on it.
* **epubcheck 5.2.1, by hand** (no spec runs it; #733): a book suspected of being
  invalid is written out and checked with the jar. Needs `java`. Fetch and
  verify the pinned archive (its SHA-256 is the one in `check.yml`'s history):
  `curl -fsSL -o /tmp/epubcheck.zip https://github.com/w3c/epubcheck/releases/download/v5.2.1/epubcheck-5.2.1.zip && echo "0532f6291faa2bb729dd253f958868a2a57dbd2c32f881a97c7c980c5940309e  /tmp/epubcheck.zip" | sha256sum -c - && unzip -q /tmp/epubcheck.zip -d ~`.
  Write the book out from the repository root, e.g. `tocLevelBooks.fourLevels`
  (any entry of an `e2e/*-books.js` registry): `node --input-type=module -e "import { writeFileSync } from 'node:fs'; import { createEpub } from './e2e/create-epub.js'; import { tocLevelBooks } from './e2e/toc-levels-books.js'; const e = tocLevelBooks.fourLevels; writeFileSync('/tmp/book.epub', e.bytes ? e.bytes() : createEpub(e.opts));"`,
  then `java -jar ~/epubcheck-5.2.1/epubcheck.jar /tmp/book.epub`. Checked: that
  book gives "No errors or warnings detected."
* **A CJK font** (`fonts-noto-cjk`, `check.yml`): `two-books.spec.js` and
  `vertical.spec.js` skip or fail without one. `fc-list | grep -i cjk` must
  list Noto Sans CJK.
* **gdb and elfutils** (`apt-get install gdb elfutils pstack`): the stall watch
  (`stall-capture.spec.js`) takes native stacks, and skips with a reason when
  it cannot (`eu-stack -p <pid>` and `pstack <pid>` are the fallbacks #712
  names).
* **Chromium 149 headless shell, Playwright 1.61.0**: see the pin above;
  `PLAYWRIGHT_BROWSERS_PATH` holds `chromium_headless_shell-1228`.

The skips of `e2e/` that depend on the machine and not on the project are
`two-books.spec.js` (the CJK font) and
`stall-capture.spec.js` (gdb); every other `test.skip` is on the project
(Android or a browser, touch or mouse), so it skips the same on CI.

## The android project syncs as the app opens (#515, #782)

Keyword: sync as the app opens. In the android project the app has the Android store
(`Filesystem`, played by `androidApp`) and runs a sync round as it opens: it writes the sync
file and reads every book's annotations record (`annot_sync_json`, `_annotations_take` in
`src/sync.bats`) and stores each again (`annot_sync_store`, `src/annot.bats`), then writes
`sync-state`. A spec that changes the store (`put`, `forgetRecords`, `storeAsQA1`) while that round
is under way can have its change overwritten by a store of what the round read before it (a
record rewritten as "QA1", with no print pages, stored again as "QA3" with its labels). Such a spec reloads with `reloadSettled`
(`e2e/legacy-library.js`), which removes `sync-state` and waits for the round to write it, before
it changes the store and before it opens the book it changed. The other projects do not sync.

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
opens). The books are in `e2e/two-books-books.js`. A new
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
the machine's load and pressure, native stacks and a core, each renderer's cgroup and the kernel's log, and the page's recent events. The capture is
`stall-capture-<n>.json` in the test's output (CI's `e2e-stall-captures-<group>` artifact).
`e2e/stall-capture.spec.js` checks it; its long tests run in the desktop project only.
`QUIRE_NO_STALL_ARM=1` skips arming (to compare stall rates); nothing sets it.

* **A capture reads only what a value can hold** (quire#751, row 8). A log, ring or trace
  read into one string is read in pieces, or its size is bounded below the largest string
  the engine allows (V8's is about 512 MiB); a capture that throws on its own size turns the
  test red with no record. A class a capture says it covers (a red in an `@serial` test, a
  renderer the kernel killed) has a spec that makes the class occur and checks the capture
  holds it; a class with no such spec is not named as covered.

* **Native stacks (gdb)** are taken **only when a page answers nothing AND no renderer used
  `FROZEN_CPU_SECONDS` of CPU over the capture's 1 s window** (a DevTools target has no
  process id, so any renderer's CPU means the page is presumed busy, `presumedBusy`). Every
  idle renderer is then attached to (at most 6): gdb's backtrace of every thread, the kernel's
  stack and wait channel, and what resolves offsets later (binary path, build id, `exeBase`).
  It is taken before the pause and the profile, which change what the renderer does.
* **gdb is ended with KILL, never TERM or INT** (`stop()` after `TEARDOWN_MS`): a gdb ended by
  TERM or INT stays attached and the renderer stays stopped. Every external command runs in
  its own process group under `timeout -s KILL` inside sudo.
* **The teardown test's gdb stays without writing a core (#807).** Its stand-in
  (`stall-capture.spec.js`, 'teardown ends a gdb attached to a hung renderer') drops the capture's
  `madvise` calls and `generate-core-file` before it appends its `shell sleep`: a CI renderer's core took
  until `timeout -s KILL` ended gdb (run 39716613681: 748 MB, 32 s), before the stay, so there was no gdb
  for the test to find. Cores are checked by the other tests of the spec.
* **Nothing is installed by the capture.** gdb comes from pwa's e2e-setup action, which the e2e jobs of
  `check.yml` call with `stall-tools: "true"` (every apt call bounded, a failure never fails
  the job; bats-lang/pwa#178, quire#820); `QUIRE_STALL_GDB` names another. Without gdb, or with ptrace or sudo
  refused, the e2e run as before and nothing goes red: the capture records `native.unavailable`
  and the spec's native tests skip with that reason, on CI too.
* **When gdb gives no stacks** (not installed, or the kernel refuses its attach) the capture asks
  `eu-stack` (the job installs `elfutils` beside gdb) and then `pstack` for the renderer's
  user-space stacks, and each renderer's `userSpaceStacks` says which answered (`gdb`, `eu-stack`,
  `pstack`) or `not available: <why for each tool>` (`fallbackStacks.tried` has each tool's text,
  exit code and note). The kernel's view of the other browser processes (the browser's, the GPU's)
  is `native.browserProcesses`: their threads, wait channels and syscalls, and, with a frozen renderer,
  their user-space stacks by the fallback tools (below). gdb is never attached to them. eu-stack and
  pstack are: each attaches to the process with ptrace and stops its threads while it reads their stacks,
  at most `FALLBACK_MS` each; this runs only when a renderer is frozen, the one case native stacks are taken.
  What the real tools print: eu-stack "#0  0x... function - module" per thread, exit 1 when it could not unwind
  one (V8's code is in memory no file maps); pstack "0x...: ????" for the main thread only, no "#0" (so such a
  line counts as a stack, whatever it says), and it cannot unwind a Chromium renderer. The frames decide, not the exit code.
  `ptraceScope`, `root`, the maps, the build id and the kernel stack of every thread are always
  recorded. Pure fallback: a step that fails is a note in the capture, never a red test.
* **The browser's and the GPU's user-space stacks** (`native.browserProcesses[].userSpaceStacks`)
  are asked of the fallback tools only, eu-stack then pstack, never gdb. They are taken only when a
  renderer is frozen, after the renderers' stacks, each tool bounded by `FALLBACK_MS`. A process of
  another type (a utility, the network service) is not asked.
* **Kernel evidence** (`kernel`): for each renderer, its cgroup v2 path from `/proc/<pid>/cgroup` and
  the files of that cgroup named by `CGROUP_FILES` (each read to at most `READ_MOST` bytes; a file
  that cannot be read is `unavailable: <code>`), and the last `KERNEL_LOG_LINES` lines of `dmesg` that
  match `KERNEL_LOG_PATTERN` (as root or through sudo; `unavailable: <why>` where denied or missing).
  Read-only, and read before the native stacks and saved, so a teardown that cuts the native step keeps it.
* **Page history** (`history`, `e2e/page-history.js`): per watched page, the last 100 console messages,
  uncaught errors, requests, finished requests and failed requests, each with its time and URL (and
  its status, or its failure text), texts cut to 300 characters, no body read and nothing awaited;
  and the requests in flight with their age. It is kept from `arm()`, except under `QUIRE_NO_STALL_ARM=1`
  (no listener on the page then, so a comparison of stall rates differs only by the debugger). A kept text is a
  copy, not a slice (V8 keeps a slice's whole parent alive: 100 slices of 10 MB messages held 1000 MB on node
  22.22, 100 copies held 0).
* **The browser's own stderr is not captured.** Playwright 1.61's `logger` launch option receives
  only `api` messages, not the browser's process lines; a `Browser` has no `process()`; Chromium's
  `--log-file` writes no file in the headless shell; `DEBUG=pw:browser` prints the lines to the
  worker's stderr, from which no spec can read them (what was tried is in the pull request that
  added the history).
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

## The flight recorder and the evidence of a red (#575)

Keyword: flight recorder. The freeze of #575 (a fresh job's renderer, main thread in an untimed futex wait, about
1 in 900 fresh jobs) is not waited for: the history is recorded in rings during every CI e2e job and written out
only for a red. The design, with the research and what each means cannot find, is on quire#575.

* **Kernel ring** (`e2e/flight-tracefs.js`, `e2e/flight-recorder.js`): `globalSetup` makes an ftrace instance of its
  own (`/sys/kernel/tracing/instances/quire-<pid>`, root: in-process as root, else `sudo -n node`), scoped to the run's process
  tree by `set_event_pid` and `event-fork`, 64 MB a CPU, overwriting its oldest events, `trace_clock` mono (the clock of Chrome's
  trace events, so the two line up). Events: `sys_enter_futex`/`sys_exit_futex` (the address and result of the
  untimed wait and of the wake that did not come), `sched_switch`/`sched_wakeup` (who woke whom), fork, exit, exec,
  signals, and read, write, sendmsg, recvmsg, epoll_pwait, poll, ppoll, eventfd2 (the Mojo pipes). Measured on Chrome 149: about 44,000
  events a second, no slowdown beyond noise (3.9 s against 3.7 s for 30 page cycles). A frozen renderer's capture first pauses the ring
  and writes its last 1.5 million lines gzipped (`flight-<n>-kernel.txt.gz`). The teardown removes the instance.
* **Chrome's ring** (`startBrowserTrace`, `keepBrowserTrace`): the browser's DevTools `Tracing` domain, `recordContinuously`, categories
  toplevel, ipc, mojom and sync (`TRACE_CATEGORIES`), 32 MB. Measured over 8 rounds of 30 page cycles (a loop of nothing but IPC) with the kernel ring: 3.88 s with no recorder, 4.09 s with this set (+5%), 4.25 s with nine categories (+10%), so the light set is the default. Ended and read only for
  a frozen renderer (`flight-<n>-browser-trace.json.gz`). Measured with one thread of a renderer stopped: `Tracing.end` answers in 79 ms
  and the trace holds the renderer's events up to the freeze, so a frozen main thread does not take the renderer's trace with it.
  A renderer with every thread stopped (SIGSTOP) answers nothing more: the browser's, GPU's and network's events are what is then in it.
* **When it records**: CI, or `QUIRE_FLIGHT=1`, on Linux, in every run, the `@serial` run too (its budgets keep headroom over a loaded runner and fail a turn that costs twice as much; the recorder costs about 6 to 8%, `[cost]`; a red there had no record when it was exempt). `QUIRE_NO_RECORDER=1` turns it off. Without
  tracefs or sudo a red says `EVIDENCE MISSING` (below); a local run without the variable records nothing and owes nothing.
* **Every red has its record.** A test that fails with nothing frozen writes both rings too (`flight-failed-*`), and they go on for the tests after it. A renderer that
  crashes or a browser that goes away writes `crash-<n>.json` (the reason, both rings, dmesg, the disk, a sanitizer's reports); the kernel ring holds the signal and the exit.
* **The watchdog** (`e2e/flight-watchdog.js`, started as root by global setup, outside every worker and browser): every second it looks at the renderers of the run; one whose
  main thread has been in an untimed futex wait with no CPU used for 10 s is written out to `flight-watchdog/` (the threads, the word and its neighbours, the ring's view of the word,
  stacks), whatever the stall watch does (off, unarmed, dead or stuck). Its output and the ring's holds go to SUDO_UID and SUDO_GID when sudo set them (`ownerOf`, `ownTree`, quire#767), so a root run leaves nothing a non-root run cannot rewrite. It also keeps every tick of its own that came late by 300 ms or more, with the steal time that passed
  (`host-stalls-*.json`): a stall of the machine shows as a gap of everything at once.
  **What the machine was doing over a stall (host-stall, quire#909)**: the watchdog reads `activityOf` at every tick (the steal time, `total=` microseconds of `some` and `full` of `/proc/pressure/{memory,io,cpu}`, and `pswpin`, `pswpout`, `pgmajfault` and `allocstall_*` of `/proc/vmstat`), so a stall's entry holds the change since the tick before it: `stealMsDuring`, `pressureDuringUs.{memory,io,cpu}.{some,full}`, `vmstatDuring`, and `reading` (`memory reclaim: ...` when the memory `some` time is more than half of the gap, else the numbers). Run 40232296271 (7965 ms, steal 0) could not say why; PSI is the kernel's own accounting of time lost to waiting for memory, io or cpu (docs.kernel.org, accounting/psi), `allocstall_*` counts direct reclaims (a task freeing memory itself) and `pswpin/pswpout/pgmajfault` the swap and disk reads, which is what memory reclaim is made of. `some` is used for the rule because on a machine where one task reclaims and the rest wait, `full` is a subset of it and a 2-core runner rarely has every task stalled. A kernel without PSI (no `CONFIG_PSI`, or `psi=0`) or with no `full` line for cpu (before 5.13) is written as `not available: <code>` or `null`, never an exception. `runnerLoad().summary.reading` (`e2e/runner-load.js`) says `memory reclaim` for a worker sample whose timer was 300 ms late or more (`summary.stalls`) when the memory pressure in its interval covers more than half of the lateness (`memoryReclaim`, the same rule); the sampler's interval is 2 s, so that is a coarser reading than the watchdog's 100 ms ticks. Tested on a /proc of its own (`a stall of the machine names the memory, io and cpu pressure ...`, `the reading of the runner load says memory reclaim ...`, `evidence.spec.js`).
* **The apparatus fails closed; `EVIDENCE MISSING` is the last net (`e2e/preflight.js`).** Before any test, global setup
  proves every part works, or the job is red with `PREFLIGHT FAILED: <part>: <why>`: `sudo -n` usable; the output directory
  written and read back; the kernel ring made with every required event (futex, sched, signals, read/write/sendmsg/recvmsg/epoll;
  exec, poll, eventfd, block and oom events are optional and skipped by name), on, and taking events from the runner process
  (`stats` before and after an action of the traced process); the watchdog's child alive and its first heartbeat read; each
  browser's trace ring started (`traceReady`, in the `stallWatch` fixture). While the run goes on, a monitor in the runner
  process reads, every 2 s, the watchdog's child and its heartbeat (the file's content, never its time) and the ring's reading in
  that heartbeat, and ends the run with `::error::EVIDENCE MISSING: <part>` when the watchdog died or went quiet for 6 s, the
  ring was stopped with no capture holding it (a capture's hold is a file `ring-kept-<holder>` in `flight-watchdog/`, its time as content, written before the
  pause and taken down after; a stopped reading counts only when a heartbeat made after the holds were missing still shows it), a hold is older than 120 s (a capture
  that died holding the ring), or the ring took no events for 60 s. A reporter in the runner (`e2e/evidence-reporter.js`) writes the ring for an unexpected result no worker kept a
  record for (a killed worker, a runner killed mid-test), and the job's `Evidence check` (`--require-report`) fails with no report
  or a result without a kernel ring. A snapshot pauses the ring while it is read (a ring read as it records never reaches its
  end) and **releases it on every outcome** (a freeze, a crash, a failure, a pass, a snapshot that failed, a watchdog report): the holder's file goes down and the last holder out starts the ring again. A ring left paused hid every later red (the four `EVIDENCE MISSING` of the reading-tools job), so a kept ring carries `reach` (the red's time and the last event's time, CLOCK_MONOTONIC; the `flight-kernel-reach` attachment); a file that ends before the red with no other capture holding the ring is `EVIDENCE MISSING: kernel ring (does not reach the red ...)`, and the job's check fails a hold still down at the end. Tested by `evidence-real.spec.js` (three reds in one run, a hold nobody releases, a red in the `@serial` run) and `evidence.spec.js` (the hold rules, on a ring of its own).

  **Ring readers** (`snapshot` in `flight-tracefs.js`): `tail`, `gzip` and the file's stream are ended on every outcome. A capture whose file cannot be written (the `lost` step of `a capture leaves the ring recording`, job 119151454126 of 3797c21) returned its error at once but left `tail` and `gzip` blocked on pipes nobody read (the ring is larger than the pipes carry); they held the root call's stderr, so `execFile` of `asRoot` waited for its whole `ROOT_MS` (60 s, the ring shows the worker's next `sudo` 60.0 s after the previous one) and the test ran out of its 90 s. Locally the ring was small, so the readers finished by themselves. Shown by `a capture whose file cannot be written ends at once` (`evidence.spec.js`, a stand-in ring of 60000 lines): without the fix 20 of 20 runs (10 alone, 10 beside four busy loops) end at the test's 20 s limit, with it 20 of 20 pass in under a second.

  **Ring lock** (`withRingLock`, `holdAndPause` and `release` in `flight-tracefs.js`): a hold (the file, then the pause) and a release (the file down, who is left, then the resume) are each one step to the other captures, under a lock file `ring-lock` in the same directory (made with `wx`, its time as content, taken over after 2 s, given up after 5 s). **Unreadable lock** (ring lock, #844): a lock whose content is not a time (empty, from a write that hit ENOSPC, or text) is a dead holder's: it is taken over once it has been seen as the same unreadable lock (same identity: inode, birth time in nanoseconds and content; the birth is compared for equality and never against the clock, so no age is read from a file time) for `LOCK_UNREADABLE_MS` (500 ms), where it used to give `NaN`, never stale, and every later run failed with `EVIDENCE MISSING: ring lock` until the file was removed by hand. The timer belongs to one observed lock: a read that fails because the lock is gone, a valid time, or another identity starts it again, and the lock is looked at once more just before it is unlinked, so a live holder's lock (made with `wx` and read empty before its content is written) that replaced a dead one while the timer ran is never the one taken down. **The window is measured, not assumed.** A live holder's lock is empty from its `wx` create until its write; on this machine (4 cores, `writeFileSync` with `wx` then `unlink`, 100000 rounds, a reader spinning on the file, idle and beside 4 and 8 busy loops, several runs of each) the longest time a reader saw the file empty was under 60 ms in every run (a few ms idle, 24 to 52 ms beside busy loops, once 47 ms on an idle machine: a writer descheduled between its create and its write); the commands and complete outputs of one run of each are in the pull request of #844. 500 ms is more than eight times the longest empty time measured, and costs a dead unreadable lock half a second inside the 5 s limit. What comparable code does: `proper-lockfile` makes its lock with `mkdir` (a directory has no half-written state) and judges it by `mtime`; npm's `lockfile` makes it with `wx`, ignores the content, judges by `ctime`, and when the stat finds the lock gone starts over; SQLite treats a rollback journal that is empty or whose header is not well-formed as not hot, so it never acts on a half-written file but also never reads its content as a holder. **Why the identity has the birth time (#870).** An inode number is reused at once by tmpfs and ext4 (20000 of 20000 remove-and-create rounds on this machine's ext4 gave the removed lock's inode again, 19999 compared), so a stale unreadable lock removed by another process and a new holder's `wx` create that got the same inode read the same as the timed lock while the new one was still empty, and the timer ran out inside a live holder's empty phase, which unlinked a live lock. The new file's birth differs (0 of 19999 rounds repeated a birth in nanoseconds), so the re-created lock is another lock and its timer starts again. Chosen over: the inode alone or with the content (what #844 had, repeats), the modification or change time (a write moves them, and they are the clock's reading that `proper-lockfile` and `lockfile` compare against the clock, which this lock does not do), and a lock made whole by `link` from a private file (no empty phase at all, but a lock written by anything else still has one, and the timer must hold for that). A filesystem that gives no birth time reports zero for it and the identity is then the one of #844. Tested by `a ring lock re-created with the same inode and still unreadable when the first one's window ends is not taken` (`evidence.spec.js`: another process removes the lock and makes it again with the same inode and content, and the test fails on the code of #844 with the waiter taking the lock at the end of the first window). None of them acts on a half-written lock at once; this lock reads its content (a time and a process), so the unreadable state exists and is waited out for longer than a write takes. Tested by `a ring lock that is empty, is not a time, or is older than the stale limit is taken` (which also refuses a live lock) and `a ring lock that is unreadable only briefly, or that another holder replaced while its timer ran, is not taken` (`evidence.spec.js`, another process plays the holder with a lock that is empty for 40 ms, and with one swapped in at one instant for the first while the first's timer is almost at the window). A lock not had in the 5 s is not failed open silently: the action still runs (a capture is worth more than none) and a record is left, `ring-lock-failed-*` in `flight-watchdog/` and a `[ring lock]` line, which the monitor ends the run on (`EVIDENCE MISSING: ring lock`) and the job's check repeats. Tested by `a ring lock that cannot be had in its limit` (`evidence.spec.js`, limits injected) and `a ring lock that is held past its limit` (`evidence-real.spec.js`, a holder that keeps renewing the lock through a real failed test). Without it a capture that wrote its hold and paused between another's look at the directory and its resume had its ring switched back on while `tail` read it. Found by review of 1054fda and shown by `four captures at once on one ring` (`evidence.spec.js`): four workers, 3000 holds each on a stand-in ring, each looking at the ring while it holds it: 2 to 5 captures a worker found it recording with the lock off, 0 with it on.

  **Capture before close** (`settle` in `stall-capture.js`, called by the `context` fixture of `fixtures.js` before the context closes): the page fixture closes its context before the stall watch's own teardown, and a closed context takes its renderers with it, so a capture still in its ring read (seconds, longer under load) found `/proc/<pid>` gone and the red said `EVIDENCE MISSING: kernel view of renderer <pid>` (or `futex word memory of renderer <pid> (ENOENT)`). That was the watchdog test's red in a loaded run: its deliberate freeze is also seen by the stall watch, whose capture starts about 5 s into the hang and runs while the test, which waits only for the watchdog's report, ends. Now the captures running are waited for (10 s, then their commands are ended) while the renderers are still there. Tested by `a page closed while the stall watch is still capturing its frozen renderer` (`evidence.spec.js`).
  That is not enough alone: `settle` ends the commands after 10 s, and on a runner the rings and the native step (gdb, a 700 MB core, its gzip) outlast the test by more than that, so the context still closed under the capture, which then read the threads, the main thread's syscall, the open files and the futex word's memory from `/proc/<pid>` after the native step and got ENOENT (quire#749 job 119124736500: `futex word memory of renderer 6009 (ENOENT)`; its log shows every renderer read ENOENT, after gdb had run). So a frozen capture reads everything `/proc` holds of the processes (`threads`, `mainThread`, `channels`, the kernel view `kernelTasks` and the futex word `futexWordMemory`) first, before the rings and the native step, and `nativeStacks` takes the kernel view and the word from that read (`before`). Reading changes nothing in a renderer. Tested deterministically by `a renderer gone when the capture has finished its rings` (`evidence.spec.js`): the rings step is replaced by one that kills every renderer, so the capture's later steps always find `/proc` empty; 10 of 10 fail without the read-first change and 10 of 10 pass with it, alone and with four busy loops.
  Every job logs `[preflight]`, `[capabilities]` and `[cost]` (the loop of page cycles with the rings off and on, at the start of each run), and the monitor logs `[monitor] started` and `[monitor] stopped: <checks, heartbeats read, ring events>`. Every capture keeps `capabilities.json` (perf counters, symbol files) and logs a `::notice` when it changes.
  `e2e/evidence-real.spec.js` induces each part's failure in a nested Playwright run on the real path: for the preflight, `sudo -n` (a command that asks for a password, `QUIRE_FLIGHT_SUDO`), the output directory (a file where it has to be), a required event the kernel lacks (`QUIRE_FLIGHT_REQUIRE_EVENT`), a ring on that takes no event of the run (scoped to another process, `QUIRE_FLIGHT_TRACE_PID`), a watchdog alive that never beats (`QUIRE_FLIGHT_WATCHDOG_SCRIPT`, `QUIRE_FLIGHT_FIRST_BEAT_MS`), the browser's trace ring (a browser whose Tracing is already taken); for the monitor, a watchdog stopped with SIGSTOP and a ring whose events are all switched off (`QUIRE_FLIGHT_BEAT_STALE_MS`, `QUIRE_FLIGHT_RING_QUIET_MS` shorten the real limits; the condition and the code that ends the run are the real ones). Those variables are set by no job, only by those tests. A failed preflight stops the ring and the watchdog it had started.
  **The watchdog counts the main thread's CPU, not the process's** (`mainThreadTicks`): a frozen renderer's other threads tick now and then (1 tick in 3 s measured on Chrome 149), and a process-wide count started the clock again at each one, so a freeze could go unreported. Tested deterministically on a /proc of its own (`the watchdog counts the CPU of the main thread`); `QUIRE_NO_STALL_WATCH=1` (set by no job) makes the stall watch do nothing at all, and `a freeze with the stall watch off` shows the watchdog writes the freeze and the check passes with the watch off.
  **The rr proof is read each job from rr itself** (`capabilities`): `perf stat -e cycles` and `rr --version` and `rr record true` (e2e-setup's `stall-tools` input installs rr; not installed is logged as such), with the answer in `capabilities.json` and the `[capabilities]` line, and a `::notice` when rr works.
  **`cutOnPurpose`** (a test of the capture's own teardown) says what it cuts: `'whole capture'` owes nothing of the capture, `'native step'` owes both rings and not the native step's fields (`missingEvidence`).
* **A red without its record is its own failure.** A test that timed out, or whose renderer froze or crashed, and has no kernel ring (written and with events) or no
  browser trace (unless the browser itself is gone) fails its teardown with `EVIDENCE MISSING: <field>`; `e2e/evidence-check.js` (the job's `Evidence check` step) turns that into the
  job's named error and also fails a job whose tests timed out with no flight file at all; the stall artifact's upload fails when a test failed and there is nothing to upload.
  That failure is the bug to fix, ahead of the test's own.
* **What identifies each class, and the test that induces it** (`e2e/evidence.spec.js`, and `sanitizer.spec.js`): an untimed futex wait in a renderer's main thread (sync XHR to a
  server that never answers): the word's address and 64 bytes around it, the waker candidates (the process's other threads), the ring's waits and wakes on the word and who woke the waiter
  last, the browser trace with the renderer's events, the symbols' state; a script spin: the paused frame's function; a renderer crash and a killed browser: the signal and the exit in the ring,
  the trace or why there is none; a frozen compositor (GPU process stopped): the page answers but `frames.answered` is false and the process is `T`; a service worker that never answers a
  fetch: its state in the capture and the request in the trace (`pendingRequests`, since it reaches no network layer and no page request event shows it); a full disk: `disk` and the
  block requests in the ring; a missing symbol file: `symbols.state` and the module and offset of each frame; a recorder that does not start and a red with no record:
  `EVIDENCE MISSING`; a sanitizer's report: in the crash capture; a stall of the machine: the watchdog's late ticks with the steal time.
  The classes added by the review, each with the field and the test (`evidence.spec.js` unless named): a main thread in an untimed
  call that is not a futex (read on an empty pipe, write to a full one; `blocked`, `target`, `peers` of the watchdog's report; "a main
  thread blocked in a call that is not a futex", on real named pipes, and the `parseBlocked` table); an OOM kill (the kernel log and the
  `oom` events in the ring; "a renderer killed by the kernel for want of memory", in a memory cgroup); a jump of the wall clock
  (`clock-jumps-*.json`, against the monotonic clock; the test sets the clock); a sandbox or zygote failure at launch and a lost DevTools
  session (quire#591, quire#599: `evidence-real.spec.js`, a browser that is `/bin/false`, one that dies of SIGSEGV, a target closed); a
  network stall (`history.inFlight` with its age, and `pendingRequests` of Chrome's trace); a slow page (quire#600: long tasks, attempts and
  the runner's load in the capture, the task in Chrome's trace); a banner over a control (quire#556: `page-state`, the box of each overlay
  and what Playwright says intercepted the click); two screens that differ by a pixel (quire#546: `pixel-diff`, where, both colours and the
  elements there); the cost (the rings' price measured in every job, `[cost]` in the log).
* **Not seen by the record, and the means that sees it** (decided): (1) A bug that vanishes under any recording: the kernel ring is outside every process and cost no
  measurable time, and the watchdog works with the stall watch off, so a freeze leaves a record without the debugger enabled, the DevTools probe or the page's session. (2) Memory
  corruption in Chromium: the `sanitizer` step of the `reading-tools` job runs the app's first screen on Chromium's public AddressSanitizer build (position 1625077,
  Chromium 149.0.7827.0, the branch of the suite's headless shell 149.0.7827.55; file and SHA-256 pinned), and any report fails it; two more
  tests there make a renderer exhaust memory (`chrome://memory-exhaust`), sandboxed and not, and require the report in `log_path`, so
  "no report" means something; Chrome for Testing has no sanitizer build, and building one is hours. (3) The ordering of a race that rr would replay: impossible on a hosted runner (measured on
  ubuntu-24.04, image 20261018.339.1: no PMU, `perf stat -e cycles` fails as root, rr 5.7.0 dies on the CPU model; `rr.soft` needs Ubuntu 24.10 and does not instrument V8's
  JIT); every job probes this again (`capabilities.json`: whether `perf stat -e cycles` works, and whether the symbol files exist) and notes a change, so the proof is not one old run; the substitute is the ring, which orders every futex wait and wake, wakeup and switch with CLOCK_MONOTONIC timestamps. (4) The hypervisor's own reasons for a stall:
  invisible from the guest by nature; the observable part is the gap in all tasks and the steal time. (5) Symbols: Chrome for Testing 149's headless shell is stripped and no public
  symbol file exists for it (every name tried in its bucket is a 404; Playwright 1.61 downloads the same build); the substitute is the thread names, the Mojo interfaces and tasks of
  Chrome's trace, and the module and offset of each frame to resolve against a build that has symbols if one appears (`QUIRE_SYMBOLS_DIR`).
* **A stopgap**: the recorder, the watchdog, the evidence check, the sanitizer step and the gdb install are what a second Playwright app would copy; they belong in pwa's
  `e2e-setup` and `gen-pwa test` (bats-lang/pwa#132 for the evidence, #109 for the tools), and this is quire's until they move.
