---
paths:
  - e2e/**
  - playwright.config.js
---

# The e2e suite

## Nothing of one book shows in the next (#435)

`e2e/two-books.spec.js` opens a book that has every per-book feature (Alpha:
five chapters, a nested contents, a page list, a note, a ruby, a Media Overlays
narration, left to right, Japanese; bookmarks, a highlight, a search gone to, a
jump with the back button up, Columns Two, the narration playing) and then one
that has none (Beta: two chapters, no page list, no ruby, no narration, Hebrew
read right to left), and checks each of Beta's panels, rows, bars and records
is Beta's; a vertical book (Gamma) and a fixed-layout one (Delta) are opened
before Beta to check the writing mode and the page box are not carried. The
books are in `e2e/two-books-books.js` and checked by epubcheck. Beta is opened
from the library, from an OPDS catalogue's Get, and after a reload that kept the
view; Alpha is opened again after Beta; and the records kept for Beta after
Alpha equal those kept for Beta opened first in a profile of its own (the record
without its position in the library's order, the reader's settings, the same
file so the same id; the sync the android project makes as the app opens is
waited out by `reloadSettled`). It found one leak, fixed: the in-book search
field kept what was typed in the last book (`_library_shown` makes it afresh,
`app_book_search`).

By decision, the narration's clip table is not probed (no hook for a test in the
shipped build; Playwright's guidance is to test what a user sees): the table's
release is checked by what it is for, Beta offers no narration controls and the
audio element is paused and holds only a blob URL the app revoked (the page's
`URL.revokeObjectURL` is noted by the spec). The fixed-layout box and the
writing mode are checked in the page, not in the cells.

## A page that stops answering in e2e explains itself (#244)

Every spec takes `test` from `e2e/fixtures.js` (`e2e/global-setup.js`
refuses a spec that does not), whose auto fixture `stallWatch`
(`e2e/stall-capture.js`) arms each page as it is made: a DevTools
session of its own with the debugger enabled and breakpoints inactive,
since a page already stuck in a loop can no longer be attached to or
have its debugger enabled (only `Debugger.pause` and a few others
interrupt running script). It asks each page to evaluate `1` every 2 s;
a page that does not answer within 5 s, and every page of a test 15 s
before its timeout, is captured: the frames `Debugger.pause` stops in
(wasm ones by function and byte offset), a CPU profile when nothing
pauses, which commands the renderer still answers, and the renderers'
CPU time over 1 s, each renderer's threads by state and kernel wait
(`/proc`, #575: a renderer that answers nothing and burns nothing is
waiting outside script), the renderer's main thread's system call and open
channels, the same for the browser, GPU and utility processes (#591: a
renderer waiting on the browser process is told from one waiting for nothing by
what the browser is doing) and the machine's load, free memory and pressure
(`/proc/pressure`). The capture is `stall-capture-<n>.json` in the test's
output (CI's `e2e-stall-captures-<group>` artifact), attached to the test, and
summed up on stderr. `e2e/stall-capture.spec.js` checks it on pages that
loop forever in script and in wasm.

**The native stacks of a frozen renderer (#575, #591).** A renderer that
answers nothing at 0 CPU sits in an untimed futex wait (`0x189`, no timeout;
a healthy idle one in `0x89` with a timeout) and the JavaScript side cannot say
who it waits for. gdb stops the process it is attached to, so it is attached
**only when a page answers nothing AND no renderer of the browser used
`FROZEN_CPU_SECONDS` (0.1 s) of CPU or more over the capture's 1 s window.**
"Answers nothing" is the armed session's `Runtime.evaluate` for 2 s, or, for a
page that is not armed (no debugger, see below, or it stopped answering before
it was armed), an `evaluate` of its own: armed and unarmed pages are judged
alike, and so are the capture's two reasons (an unanswered probe, a test about
to time out). Which renderer is a page's own is not known (a DevTools target has no
process id, and `SystemInfo.getProcessInfo` has no target),
so the rule is about all of them: if any renderer used CPU, the page that
answers nothing is presumed to be that busy one (a loop or a heavy layout spends
about a second of CPU a second, 0.98 measured here) and **nothing is attached**
(`presumedBusy` says which renderer); only when every renderer is idle (a
SIGSTOPped or idle one 0 s, #575's and #591's frozen ones 0 and 0.02 s) is the
page presumed frozen, and every idle renderer is attached to, **the other pages'
too** (collateral, about 2 s of stop each, next to a page that is frozen, which is
a failing test anyway). The price of not knowing the pid: a frozen page next to
another that is busy is not attached to. A healthy job runs nothing: a page that
answers is never looked at.

The capture's `native` field has, for each such renderer (at most 6, side by
side): gdb's backtrace of every thread (`gdb -batch -p`, `thread apply all bt
40`, through `timeout -s KILL`, and sudo where the user is not root, since
Yama's ptrace_scope 1 allows only a descendant of the tracer; `ptraceScope` is
recorded), the kernel's stack, wait channel, system call and state of every
thread (the stack is root's, read by one `sudo tail`), and what resolves the raw
offsets later against the same download: the binary's path, its GNU build id
(`readelf -n`), the address it is loaded at (`exeBase`), every module's, the
executable anonymous regions (JIT code) and, for each frame, the module holding
its address and the offset in it (`frames[].module`, `.offset`; `pc - exeBase`
for the binary). It is taken before the pause and the profile, which change what
the renderer does, and written at once (`save`), so a teardown that does not wait
for the rest keeps it: `stop()` waits `TEARDOWN_MS` (10 s) for captures still
running, then **ends their commands**: SIGKILL to each command's process group (all a
user that is root can reach; sudo's group is root's, out of reach of one that is not)
and `pkill -KILL -f` of a token that gdb's command line carries (`-iex echo
QUIRE_STALL_<random>`), run as root through sudo, so `timeout` and gdb are killed
whoever started them, then SIGCONT to every pid gdb was attached to; none starts
after. **KILL, never TERM or INT**: a gdb ended by TERM or INT stays attached while
it waits for what it runs (reproduced: the renderer stays in state `t`, a page
evaluate hangs, SIGCONT does nothing), and only a killed gdb is detached by the
kernel and lets the renderer run (state S). A gdb killed in the middle of a call into
the renderer (the `madvise` calls) can leave it broken, not only stopped; that is a
renderer that was frozen. The real bound, if all of that failed, is `timeout -s KILL`
on gdb itself, about 30 s after it attached (backtraces and core). Tested with the real
gdb attached to a really hung renderer, ended by the teardown: nothing of the capture
is left, no renderer is stopped, and the page answers when the request is let go. Every external command runs in a process group of its own with a hard limit
(`timeout -s KILL` inside sudo, since a SIGKILL of sudo reaches nothing of root's, and
node's own limit and group kill behind it); the worst case is derived in code
(`NATIVE_MOST_MS`). **Nothing is installed by the capture**: gdb comes from the
e2e jobs' visible `Install gdb` step in `check.yml` (`apt-get update` and install,
retried, `continue-on-error`, so its failure never fails a job: a stopgap; pwa's e2e-setup action should install it
and keep the passwordless sudo, bats-lang/pwa#109); gdb is found as an absolute
path on this process's PATH (`QUIRE_STALL_GDB` names another, the spec's stand-in),
the path the command then runs under sudo, whose own PATH is not this one's, and without gdb or with ptrace refused the capture says
`gdb` is unavailable or `ok: false` with gdb's own words. **Without gdb, or with ptrace or sudo refused, the e2e run exactly as before and
nothing goes red or flakes for it**: the Install gdb step never fails a job, and
the capture records `native.unavailable` ("native capture unavailable: gdb is not
installed", or gdb cannot attach, with gdb's or sudo's own words) beside what it
could take (the kernel's view and the addresses), then carries on with the
JS/wasm capture. The spec's native-stack tests skip with that reason, on CI too
(no throw there); another failure of the capture, with gdb present and allowed, fails
them. The hosted runner's sudo and gdb take the stacks (below). The long tests (a 12 s busy page, a frozen renderer,
the teardown ones: about 2.5 minutes) run in the desktop project only and skip in
the others, saying why, since the renderer and the machine do not depend on the
project; the stall-capture group pays them once. A frozen renderer is made in the spec by SIGSTOP, armed and unarmed;
a loop and a 12 s busy page are asserted to be captured and NOT attached to.
**Seen on a hosted runner (PR #662, ubuntu-24.04 image, 4 cores, kernel 6.17 azure):**
the runner user is `runner` (uid 1001) with `(ALL) NOPASSWD: ALL`, `ptrace_scope` is 1 and
`core_pattern` pipes to systemd-coredump (unused: gdb writes the core itself). A page hung
by a synchronous XHR to a server that never answers (no SIGSTOP) showed what the real
freeze showed: the main thread in `futex(..., 0x189, 0, NULL, ...)` (an untimed wait),
state S, 0 s of CPU, no answer to any DevTools command. The capture, as the runner
user through `sudo -n`: gdb attached and stopped the renderer 0.66 s, wrote a 758 MB core
(15.2 MB gzipped, gzip 3.0 s), named libc's frames (libc6-dbg installed by the Install gdb
step, 6 to 7 s of the job), left nothing of gdb, timeout, prlimit, sudo or pkill behind,
and the core opened in gdb with the build id's binary. The teardown of a real gdb attached
to a really hung renderer (the `pkill -KILL` path through sudo) left no renderer stopped and
the page answered once the request was let go. The Chrome for Testing 145.0.7632.6 binary
there is stripped, as measured (`?? ()` and offsets from `exeBase`). Still not seen: a
renderer that sleeps in an untimed futex for a reason other than this request (the real
freeze's waiter), and the real thing at all (about 1 in 27,000 early loads).

**A core of the frozen renderer, and symbols (#575, #591).** The same gdb attach,
after the backtraces (stack first, then core, so a renderer is stopped once),
writes a core file of up to `CORE_MOST` (2) of the renderers attached to, gzips it
(`gzip -1`, after gdb let go) and uploads it as the artifact `e2e-stall-cores-<group>`
(7 days) only when one was kept, so a run with no freeze uploads nothing; the
screenshots artifact leaves cores out. Measured, on the Chrome for Testing
145.0.7632.6 headless shell (the binary Playwright 1.58.2 downloads for CI): a renderer's address
space is 1.4 TB, nearly all of it PROT_NONE reservations of V8 and PartitionAlloc
with nothing resident (64 MB resident), and gdb's `generate-core-file` read every page of
them: 52 s of system time and no core in 60 s, then 5 GB where it did finish. So gdb
first calls `madvise(range, MADV_DONTDUMP)` in the stopped process for each
mapping with no resident page and 16 MiB or more (`quietRanges`, from smaps),
which a process blocked in a futex wait can run (with `scheduler-locking on`, so the other threads do not run during them), and then the dump is the resident
memory: 686 MB raw, 14.9 MB gzipped, gdb stopped the renderer 0.6 s, gzip 2.8 s
(4 cores here; the 1194 Chromium build of this machine: 806 MB, 90 MB, 2.5 s, 6 s; on the
4-core hosted runner: 741 to 758 MB, 15.1 to 15.2 MB, gdb stopped the renderer 0.6 s, gzip 2.9 to 3.0 s). Limits: the file gdb writes is bounded by
`prlimit --fsize` (`CORE_MAX_BYTES`, 1 GiB), the gzip by `CORE_GZ_MAX_BYTES` (200
MB), over either it is removed and the capture says why; gdb's whole time (backtraces
and core) by `timeout`; a core is never asked of a process in a group stop (SIGSTOP:
no call can run in it, and the one that was tried left the renderer broken), and a gdb
ended during the core still gave the stacks (`coreEndedEarly`). A failed core never
fails a test or a capture (`core.reason`). Disk: at most 2 raw cores of 1 GiB at a
time on the runner, then the gzips. A core holds the renderer's memory: here the e2e
fixtures' own pages, books and the app, never a user's data (the runners hold no
other); it is uploaded to a public repository's artifacts only for a freeze, and
expires in 7 days. `e2e/stall-capture.spec.js` writes the core of an idle renderer,
checks the caps, and opens it with gdb and the binary it names: the main thread's
pc is the live backtrace's. The perturbation, stated: the `madvise` calls run in the main
thread of the frozen renderer after the stacks are taken, so the core is of the process after
the stacks, not at the same instant; `MADV_DONTDUMP` persists on a renderer that survives, and
up to 200 mappings no longer merge with their neighbours. A real freeze is a failing test.

Symbols: the capture records the binary (`binary`: path, `--version`, size, whether
it has `.symtab`, `.debug_info`, a `.gnu_debuglink`), its GNU build id, `exeBase`,
every module's base, the system libraries' build ids (libc, the loader, libstdc++,
libm) and the OS and libc6 and libc6-dbg versions. **The browser has no symbols to be
had:** Playwright's Chrome for Testing 145.0.7632.6 headless shell is stripped (no
`.symtab`; `.gnu_debuglink` names `headless_shell.debug`), Chrome for Testing's
manifest lists no symbol download for it, Google's per-version debug-info zip
(`https://edgedl.me.gvt1.com/chrome/linux/symbols/google-chrome-debug-info-linux64-<version>.zip`,
documented in Chromium's debugging_minidump.md) exists for releases such as
145.0.7632.67 and 145.0.7632.109 and answers 404 for 145.0.7632.6, and a different
build's symbols do not fit its addresses. So its frames are `?? ()` with an
offset (`frames[].offset`, from `exeBase`); what can be done later: disassemble
the same download at that offset, read its imports and call sites (what #599's
stacks were resolved by), or inspect the core's memory and the other threads with
the binary and build id. The Playwright-built Chromium of this machine (1194) is not
stripped (830,000 symbols, C++ names). The system libraries are named: exported
functions by the dynamic symbols alone, the internal ones (`__futex_abstimed_wait_common64`)
by libc6-dbg, which the Install gdb step adds where it can (7 MB download); debuginfod
is not used (a download while the process is stopped has no bound, and Ubuntu's server
was not reachable from here). The spec asserts it on a hung stand-in process
(`sleep`, through the same sudo and gdb path: `nanosleep` in libc named) and on a real
renderer (some libc or loader frame of some thread named), and on the browser: named
if it has `.symtab`, else an offset for every frame.

**`QUIRE_NO_STALL_ARM=1` (anything but empty or 0) skips arming** (`arm` in
`e2e/stall-capture.js`, read at each arming): the debugger is never enabled,
and the capture says `armed: false` with that reason. It is for comparing the
stall rate with and without the arming (every frozen renderer of #575 and #591
had it, a suspect and not evidence; at one stall in about 900 jobs, 2,700 jobs
without it show no stall with 95 % power if arming is the cause). Without
arming the watch still probes with `page.evaluate` and takes the native stacks
under the same rule as an armed page (no answer AND no CPU), and loses the
pause, the profile and the interrupt/task answers; the specs that need the
debugger (`stall-capture.spec.js`'s loops) fail with it on, as they should.
The default stays armed and nothing sets it: a scheduled run that does is a
change of its own.
