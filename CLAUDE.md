# quire

## Decisions are made by research, not left to the human

No task is ever "left to the human" unless an agent physically cannot do
it (a permission it was denied, access it does not have, a secret it
cannot see). Every other question, design choices included (which
layout, which wording, which default), is settled by research (what
other apps do, what their users and reviewers say, what studies and
guidelines say) and best judgement, written down where it is decided
(the issue or the PR), and then done. Judgement is what is left after
the research, never a substitute for it: a value or a design chosen
with no look at what comparable software does (the libraries,
frameworks and apps that face the same question, and what they chose
and why) is not decided. "The platform documents no value" is where
the research goes on, to what others do, not where it stops; if
nothing comparable can be found, say so where it is decided, with what
was searched. The quality rules below (the
proofs, the static tests, the e2e suite) still hold: when a choice
would break one, choose another that keeps it.

## A proof is a proof

When a requirement says proof, it means a static proof, checked by the
compiler from types and lemmas. It never means a test, a runtime check,
a read-back, an assertion or a witness that is only believed. A claim
that is only tested is said to be tested, and the proof is still owed:
where the proof system cannot reach (the array package had no model of
an array's contents), the tool is extended (a content-indexed array API
in the array package), not worked around at runtime. Trusted primitives
live in the one package that owns the platform, state what they assume,
and are tested there; nothing in quire uses `praxi`, `assume` or
`$UNSAFE` to skip a proof.

## Names are words

Element ids, numbered-id prefixes (up to 16 bytes), variables, static
indices and functions are named by what they are, in words:
`search-close`, `toc-row12`, `query`, `query_len`, not `qsrz`, `qe`,
`q`, `qn`. Nothing is short of bytes, and terse names collide: four
new ids once took existing ones, and a rename of the id `qn` also hit
a query length of the same name. A loop index (`i`, `j`) or a
conventional pair (`l` and `n` for an array's location and size) may
stay short within a few lines.

## Priorities

* **p0:** first, before anything else.
* **CI first:** CI issues, especially flaky tests, outrank feature work: a
  session fixes them first; a flake is a bug with a root cause.
* **Order:** CI issues (flakiness first), then correctness work, then
  feature work. Correctness work is anything where, assuming the code is
  already correct, the only difference is added tests or proofs (missing
  proofs, missing coverage).
* **p1:** next.
* **p2:** known issues the Android release is held for. Work sessions
  address them.
* **p3:** not held for. A session may file p3 issues but does not work
  on them.

## CI is pinned

Every input to CI is pinned in the source (#203), so a commit that
passes keeps passing: the packages by the committed `bats.lock`, the
compiler by its commit in `.github/bats-version`, and pwa's Android
workflow by its commit (`android.yml@<sha>` in `check.yml`). CI never
runs `bats lock`: `bats check` and `bats build` fetch exactly the locked
versions, and fail when a locked one is missing or the lock does not
match the project (a package used but not locked, or locked but not
used).

A quire PR that adopts new package versions runs `bats lock --repository
<dir>` and commits `bats.lock` with the change that needs them. Package
releases publish first; then the quire PR with the new lock. A publish
never turns main red: until a lock names it, quire does not use it. The
daily `relock.yml` (the shared `relock-pins.yml` of
bats-lang/repository-prototype, called by commit) relocks against the
newest, moves the compiler pin, pushes `relock/<date>`, opens a PR
listing the old and new versions and dispatches `check.yml` on it, so a
breaking publish shows as a red relock PR. GITHUB_TOKEN cannot change
workflow files, so without a `RELOCK_TOKEN` secret that PR lists pwa's
`android.yml` pin as not moved; move it in a PR of its own.

### The compiler's cache (#460)

`build` and the `static` jobs each compiled the whole app from nothing
(about 10 minutes of the same work four times). A pull request's jobs
now restore the `build/` directory of the newest earlier build under the
same toolchain (`.github/actions/build-cache`, `actions/cache` pinned by
commit), and save theirs once the job passed. What was found:

* What bats keeps (read from the compiler pinned in `.github/bats-version`,
  `src/build.dats` and `helpers.dats`, and a project's `build/`): per
  module a `.dats` and the SHA-256 of its source in `<module>.dats.src`
  (a module is emitted again exactly when the hash, or the target, differs;
  the compiler's comment says an mtime cannot tell, a relocked
  dependency's files keep their archive's), then its C (patsopt's output)
  and objects, which are fresh when newer than the `.dats` and than
  `build/.sats_changed`, a stamp touched whenever an emitted `.sats`
  changes. A build of another target or mode (`.bats_target`: native, wasm,
  and 2 more in check and test mode) is set aside in `build/.stash/<n>`
  with its mtimes. `check` and `build` therefore never share a cache (check
  is mode 2 and 3, build 0 and 1), so there are two caches, `build` and
  `static`. `.bats_cache_id` drops a cache when the compiler's semantics
  change.
* Staleness. Nothing in `build/` records the compiler, ATS2 or the C
  compiler, so the key names them: `.github/bats-version`, the ATS2 pin
  (`setup-bats/action.yml`), `bats.lock`, `bats.toml`, the runner image and
  architecture. The sources are the key's end, so an exact hit is the same
  sources, and a prefix hit is the incremental build the compiler does on a
  developer's machine: a changed module is re-emitted by its hash (its
  `.dats` is then newer than its C), a changed `.sats` rebuilds every
  module that staloads it. A cache is saved only by a job that passed
  (`actions/cache` saves on success only), so it holds no failed build, and a
  module that failed to emit has an empty `.src` and is never fresh. The
  residual risk is a bug of that incremental logic, so main never restores:
  a push to main (and the merge queue's run, and a dispatched relock) builds
  and checks from nothing, then saves for the pull requests (GitHub gives a
  pull request its base branch's caches, and a pull request's own are
  readable only by that pull request: same repository, no cross-fork
  writes). The required check on a pull request is incremental, main's is
  cold, so a stale hit would show on main at the latest.
* Paths. patsopt named C symbols by the absolute path of the files, so a
  cache was valid only at the path it was made at (bats now takes the
  checkout's path out of the C, bats-lang/bats#250). `build` is at the checkout,
  `/home/runner/work/quire/quire` in every job. The static jobs checked in
  `mktemp -d`, a different path each time; `tests/static/run.sh` now takes
  `QUIRE_STATIC_WORK`, a fixed directory (CI: `$RUNNER_TEMP/quire-static`),
  where the app is copied and checked and which is not removed.
* Sharing. Jobs of one run start together, so none sees what another saves:
  the gain is from the previous build (main's, or the pull request's earlier
  push), a few modules instead of 63, in all four jobs at once, and not from
  a job feeding another (a first job the others wait for would have made the
  run longer). Each static group saves the same key; the second to finish
  gets a warning, not a failure. Caches are immutable, 10 GB per repository,
  evicted by last access and after 7 days unused: a miss is today's cold
  build.
* What others do. Swatinem/rust-cache keys on the lockfile, the rustc version
  and the toolchain's environment, restores the newest older cache for a
  changed lockfile, caches dependencies only (the workspace's crates are not
  cached, "generally not effective"), deletes incremental artifacts and
  anything older than a week before saving, sets `CARGO_INCREMENTAL=0`,
  and suggests `save-if` main only. ccache and sccache key each result on a
  hash of the preprocessed source and the compiler and flags, never on a
  time, and Bazel's remote cache is content-addressed with the toolchain among
  the inputs: they are right where the key holds every input. bats's
  own rule for C is a time, which is why the toolchain is in the key, only
  passed builds are saved, and main is checked cold.
* `BATS_CACHE_DIR` (bats-lang/bats#250) is not used in CI, by measurement
  (#499). A pull request's job restores the `build/` of its base or its
  earlier push, and what it compiles again is what changed (a few modules;
  the adoption experiment's one comment changed, 106 s, a `#pub`
  added to one `.sats`, 325 s). A cache of patsopt's C instead still runs
  cc for every module and looks each one up (about 0.4 s a module,
  bats-lang/bats#253): a copy of a checked tree at another path, every
  module a hit, took 229 s against a cold 355 s here, so on a pull request
  it is slower than `build/`, and it would only speed up main, which is
  checked cold on purpose. Kept beside `build/`, it hits only a module
  whose every input was compiled before, which the restored `build/`
  already holds. Paths no longer matter (bats strips the checkout's path
  from the C), but the static jobs keep their fixed directory, which costs
  nothing.

### The merge queue (#586)

A pull request that enters the queue is tested as a *group*: GitHub builds a
commit of main plus that pull request (plus the entries ahead of it) and runs
`check.yml` on it (`merge_group`); the entry merges when the run passes, and
is **removed when the run has not finished within 60 minutes, even if it
passes a minute later** (`removed_from_merge_queue` in the pull request's
timeline; a passing run of a removed entry merges nothing). What a group
costs on an idle pool (measured, GMP, 2026-10-15): the `build` job 13 minutes
(the queue's run is cold on purpose, see the compiler's cache above), then the
e2e jobs 14 to 18, in parallel with the static jobs, of which `static
(accepts)` is the longest (33 fixtures, 27 minutes with the cache and 39
without; `accepts-data` 15 to 32, `app` 17 to 33): 40 minutes wall. A pull
request's own run restores the build cache (the `build` job 3 minutes) and
still takes 38, because `static (accepts)` is the long pole, not the build.

What happened on 2026-10-15, and the rules it gave:

* Five entries at once (#609, #611, #612, #613, #616) wanted more runners than
  the pool has, so groups finished after their 60 minutes, and each removal
  made GitHub rebuild the groups behind it and leave the earlier runs
  `queued`: six stale runs, each with a dozen jobs, kept the pool full, so the
  next entries timed out too. Nothing merged for 3.5 hours.
* **At most two entries in the queue at a time** (at the current settings);
  the next goes in when one has merged or been removed.
* **Superseded runs are cancelled**: a queue run that is not the newest of its
  pull request is stale (GitHub does not cancel it); `qsweep` cancels them
  (`CANCELLED STALE QUEUE RUN`). Read the pull request's timeline
  (`added_to_merge_queue`, `removed_from_merge_queue`) for where an entry is:
  `auto_merge` empty means enqueued or removed, not one or the other.
* A change that makes its own group longer than about 45 minutes does not
  wait in the queue's window: it is sharded first (the mutation check, #594:
  a change to the checker selects a smoke set, a change to the ATS2 pin all
  shards, none over about 25 minutes).
* Open (#586): the queue's own settings (how many groups build at once, the
  window) and balancing the static groups so that none is the long pole.

## Check locally before every push

A session sets up the compiler in its own environment and runs `bats
check` before it pushes, so a push that does not type-check never
reaches CI (#350's first push failed on a comparison and a free that
`bats check` rejects in a few minutes; CI took 15 to learn it). Setup is
what `.github/actions/setup-bats` does: ATS2 (`patsopt` from the
tarball it names: the gmp build, whose constraint solver computes in
infinite precision, with libgmp-dev; the -int build's solver computes in
C `int` and accepts false statements, #594, so a check made with it
proves less than CI's), `lld`, the compiler built from the commit in
`.github/bats-version` (its `bootstrap/c`, `make release/bats`), and a
clone of bats-lang/repository-prototype; then `bats check --repository
<the clone>`, or with `BATS_REPOSITORY=<the clone>` in the environment
and no flag (the flag wins). Nothing is written first: bats writes the
version's facts from HEAD (above). A check takes 10 to 15 minutes on a
cold build (6 to 10 with the -int build, before the solver moved): run it in the background and wait for it, never push on the
hope that it passes. Two bats in one checkout take turns (bats holds a
lock on `bats.toml` and says it waits). Two checkouts or worktrees take
turns by bats's machine-wide slots (bats-lang/bats#252), which are opt-in:
with `BATS_SLOTS=N` (1 to 64) in the environment, `check`, `build`,
`test` and `run`'s build each hold one of N slots, after the project's
lock, so a bats waiting for its project holds none. A slot is a file,
`<BATS_LOCK_DIR>/slot-<i>.lock` (`BATS_LOCK_DIR` defaults to
`~/.cache/bats`), locked by the kernel's `flock`: it is released however
bats ends, even killed, and no file is ever stale. Free slots are taken
without waiting; when all are busy bats says so and who last took slot 0
("waiting for another bats on this machine ... was last taken by bats
build in /path"). What bats starts runs in its slot (`BATS_SLOT_HELD`
names the file), so a nested bats takes none. These are the same files
`gen-pwa test` uses for `PWA_TEST_SLOTS` in `PWA_TEST_LOCK_DIR`, so
pointing `BATS_LOCK_DIR` and `PWA_TEST_LOCK_DIR` at one directory makes
builds and e2e runs one pool, and separate directories two (bats reads no
`PWA_TEST_*`). A machine shared by sessions sets, in the shell's profile,
`BATS_SLOTS=1`, `BATS_LOCK_DIR` and `PWA_TEST_LOCK_DIR` (one directory),
`PWA_TEST_SLOTS=1`, `BATS_CACHE_DIR` (below) and `BATS_REPOSITORY`, and
runs `bats check` and `gen-pwa test` with no wrapper of its own.

A shell that reads no profile (an agent's, a CI-like step) gets the same
from a machine-specific env file that is not in the repo (say
`~/quire.env`, holding those variables), through `scripts/with-env
<env-file> <command> [args...]`: it sources the file (every variable
exported) and `exec`s the command exactly as given, so its arguments and
exit status are the command's own: `scripts/with-env ~/quire.env bats
check`, `scripts/with-env ~/quire.env ./dist/debug/gen-pwa test --
<spec>`. `tests/with-env/run.sh` tests it (a step of check.yml, like
`tests/play-release/run.sh`; `tests/groups.json` holds only the e2e and
static groups).

`BATS_CACHE_DIR=<dir>` keeps patsopt's C in that directory, keyed by
what patsopt reads (the toolchain, its arguments and every file a
module's staloads reach, by SHA-256), and the C names no checkout's
path, so every checkout and worktree of the machine shares it, and a hit
is checked as a run is. Measured on 4 cores (#499): a cold check 355 s, a
copy of the checkout at another path 229 s (every module a hit; cc still
runs), no change in place 80 s. Set it in the shell's profile.

The e2e suite runs through the app's generator, `./dist/debug/gen-pwa
test [--timings <dir>] [-- <playwright args> <spec>...]` (pwa's
`test_run`, bats-lang/pwa#82), after `bats build`, `./dist/debug/gen-pwa`,
`scripts/sync-clients.sh dist/pwa` and `cp -R homepage dist/pwa/homepage`
(`e2e/about.spec.js` reads the home page): it serves `dist/pwa` at a port
the kernel picks, takes one of the machine's slots (`PWA_TEST_SLOTS`,
default 1, in `PWA_TEST_LOCK_DIR`), checks that `PLAYWRIGHT_BROWSERS_PATH`
holds the headless Chromium this Playwright expects (it never downloads
one), runs the `@serial` tests alone on one worker and then the others,
and stops Playwright's processes however it ends. A `--grep` or
`--workers` of the caller's makes it one run, as given. A bare `npx
playwright test` still serves the app itself (at `QUIRE_PORT`). A change
to a spec or a static fixture runs that group too where the machine can
(`tests/static/run.sh`, `gen-pwa test -- <spec>`), and what it cannot
run is left to CI and said in the PR. A fix pushed after a red CI is
checked the same way first.

The e2e suite needs Playwright 1.58 or later (`package.json` says so,
`package-lock.json` pins 1.58.2): before 1.58 its fake clock can set the
time back after a `page.clock.fastForward` (a `_runTo` already in flight
finishes after the jump and writes its old target over it; 1.58 ignores a
target in the past), so a spec that counts minutes, like "the minutes
read on each device are summed" (#352), loses one now and then (about one
run in five on 1.56.1; none in 40 on 1.58.2). A machine whose Chromium
build is older than 1.58 expects (`ls $PLAYWRIGHT_BROWSERS_PATH`) runs
1.58.2 on it by pointing `PLAYWRIGHT_BROWSERS_PATH` at a directory whose
`chromium_headless_shell-1208/chrome-headless-shell-linux64/chrome-headless-shell`
is a link to the installed `headless_shell`; it does not downgrade
Playwright.

## The version is the commit's

Quire's version is the date of the commit it is built from, never of the
build, so the same commit always gives the same version (#219): the
committer date in UTC as bats packages are versioned,
`YEAR.MONTH.DAY.SECONDS` (seconds since midnight), and the short SHA,
`2026.10.2.61373 (f95ce82)`. bats writes the commit's facts as a module
(`build/src/_bats_facts`, bats-lang/bats#250: its time, its date so
worded and its short SHA, from the commit `BATS_COMMIT` names, else
HEAD), and `src/version.bats` (tracked, #499) words them:
`quire_version` (the date), `quire_commit_short`, `quire_version_text`
(the two as one text, "VERSION (SHA)", in an array: a `string n` cannot
be joined at run time) and `quire_version_code`. The app and gen-pwa
compile them in: About shows the text, a backup records it
(`appVersion`), and gen-pwa appends it to the Android project's
`android-release.gradle` as `versionName`, with `versionCode` the same
time in minutes since 2025 (so it grows from release to release, and
pwa's run-number code is overridden). CI names a pull request's own
head (`BATS_COMMIT`, set by `setup-bats` for every later step: the
merge's second parent, hence `fetch-depth: 2`), and for a run of a merge
queue's group (`merge_group` in `check.yml`, should a queue be switched
on) the group's own commit (`github.sha`). Outside a git repository a
build fails and says so; `tests/static/run.sh`, which checks a copy of
the checkout, points git at the checkout's repository (`GIT_DIR`).
`tests/version/same.sh` checks that the facts are the same written in
other time zones, that they name the commit, and that the Android
project carries the version and its code.

## Main goes to Play's internal testing (#308)

Every push to main that passes the whole check is released to Google
Play's internal testing track by `check.yml`'s `play-internal` job
(`scripts/play-release.sh`, tested against a stub of Play by
`tests/play-release/run.sh` in the `plan` job): the run's own
`release-aab`, the commit's subject as its notes, committed with
`ERROR_IF_IN_REVIEW`. It signs in by Workload Identity Federation
(`scripts/play-release.env`, public names), whose provider admits only a
push to main of this repository, so no key exists and no other run can
release. Production is a promotion in the Play Console; ANDROID.md says
how.

## To do: book memory in a rolling window of page arenas

Partly done: the window exists (`src/pages.bats`), and the buffers a
chapter or image is parsed from come from the current page's arena. The
rest is the intended design.

Everything that belongs to a book's content (chapter text, pictures and
other images, per-page layout data) is allocated from arenas (array's
`arena_create` / `arena_alloc`), not with `alloc`. `alloc` is bounded at
1 MiB on purpose, to limit fragmentation (see array's CLAUDE.md), and a
page's content does not belong in scattered long-lived allocations.

* One arena per page, sized to hold a page with generous limits for
  images and the like.
* Five arenas live at a time: the current page, the 2 pages before it and
  the 2 after it.
* Turning forward one page releases the arena of the page that is now 3
  back and prepares the arena of the page that is now 2 ahead (turning
  back does the mirror image): a rolling window.
* Arenas are created and destroyed whole and never reused piecemeal, so
  they cannot fragment.

The point of doing this in ATS2 rather than Rust is that the arena
discipline is checked at compile time:

* a piece that does not fit its page's arena does not type-check;
* a page's pieces cannot be freed on their own, or given back to
  another page's arena;
* a page's arena cannot be released while any of its pieces is still in
  use (the arena's outstanding count must be 0), so nothing on screen
  can point into a released page.

The window itself should be in the types too: the reader state holds
exactly the five arenas, indexed by page number, so a page outside the
window has no arena to allocate from.

### The window today

`src/pages.bats` holds it. `page_arena(page, pages)` is the arena of
that page of a chapter of that many pages, with no piece out; it exists
only for `0 <= page < pages`. `window(page, pages)` holds exactly the
arenas of pages page - 2 to page + 2 (scrolled, a page is a screenful,
so the window counts those). `window_forward` turns it into
`window(page + 1, pages)` by releasing page - 2's arena and making
page + 3's (`window_back` is the mirror image), so keeping any other
arena does not type-check. Each arena is 4 MiB (`PAGE_BYTES`).

The reader's window lives in a `ref` taken out and put back with
`ref_exch_elt`, since it is linear. `_show_page` moves it to the page
shown: one page on rotates it, and any other move (a jump, a new
chapter, a new page count after a resize) releases it and makes it
anew. Going back to the library releases it (`window_close`).

A buffer a book's content is parsed from (`piece_new` in
`src/book.bats`: an entry's data, a decompressed OPF, chapter or image)
is a piece of the current page's arena when it fits there
(`page_lend`). The arena leaves the window while the piece is out (its
slot is `Lent`), so the arena in the window never has a piece out, and
`page_give_back` returns it to its slot, or releases it when the window
has moved on. When there is no window yet (the first chapter's load),
or the page has no room, the piece is the one piece of an arena of its
own, as before. `piece_owner` says which, so `piece_free` gives it back
to the right one.

### Where book content is allocated today

In arena pieces (`piece` in `src/book.bats`: a piece of the current
page's arena, or the one piece of an arena sized to it, so it has no
1 MiB bound):

* an entry's compressed data (the piece `index_read` returns): the
  container.xml, the OPF and each chapter;
* decompressed content (`take_content`): the container.xml, the OPF and
  each chapter's XHTML;
* the OPF's compressed data when a chapter is loaded (`opf_cbuf`);
* each image's bytes (`_show_image` in `src/reader.bats`);
* a book's annotations while a backup is written (`annot_json`), each
  book's part of the backup, and the whole file (`backup_export`);
* a backup file while it is restored (`backup_import`);
* a dictionary's .idx and .syn while it is imported, and its table
  (`_index_read`, `_table_store` in `src/dictionary.bats`); an article
  read from a .dict, or the dictzip chunks that hold it and their
  inflated bytes (`_article`, `_article_dz`);
* a page of an OPDS catalogue (at most 4 MiB, `FEED_MOST`) and its
  OpenSearch description while they are read, and a book's EPUB got
  from one until it is handed to the JS side as a file (`_claim` in
  `src/catalogue.bats`); the catalogues' part of the backup
  (`catalogue_backup_json` in `src/catalogues.bats`);
* the sync file: as it is read from the store, each chunk of the merge
  and the merge joined as it is written (`_out`, `_remote`, `_written`
  in `src/sync.bats`), refused over 16 MiB (`SYNC_MAX_BYTES`);
* a chapter's text read aloud (its `script`, `reader_script_load` in
  `src/reader.bats`), held while the chapter is read aloud; each
  block's copy while it is cut into sentences; and each sentence's copy
  while it is said (`script_text`);
* a narrated chapter's SMIL, its compressed data and its content, from
  when it is read until the chapter is rendered (`_overlay_load` in
  `src/reader.bats`), and a deflated audio entry's data and inflated
  bytes while a blob URL is made of them (`_source_then` in
  `src/narration.bats`).

The one long-lived arena piece is a narrated chapter's clip table
(`clip_table` in `src/overlay.bats`): the one piece of an arena of its
own (so it never holds a page's arena out of the window), at most 1 MiB,
kept until the next chapter is rendered.

Each piece lives only while it is parsed or written, except the
script read aloud, which outlives page turns (the arena it was lent from
is released when it is given back, if the window has moved on): pages
are CSS columns of the chapter's DOM.

With `alloc`:

* `src/book.bats` (`book_index_make`): the archive's tail and each
  entry's local header while the book is opened, and its central
  directory (at most 1 MiB), kept while the book is open for its
  entries' names.
* `src/book_cards.bats` (import): the OPF path (`opf_path_buf`, under
  65536 bytes as a zip name is) and a title buffer (`tbuf`).
* `src/reader.bats`: the OPF's name (for its directory), the chapter
  path (`ch_buf`), and title and text copies (`exact`, `tbuf`).
* The EPUB file itself never stays in wasm memory: bridge's file module
  keeps it on the JS side, it is read by ranges, and it is saved to and
  restored from IndexedDB there (`$BF.file_idb_put`, `$BF.file_idb_get`).
  Only a book got from a catalogue passes through, in an arena piece,
  since the bridge's fetch hands its bytes to wasm and `$BF.file_store`
  takes them back.
* Everything else (`src/bin/quire.bats`, the small buffers in
  `reader.bats`) is element ids, event names and storage keys: UI, not
  book content; it stays on `alloc`.

### Offline dictionaries

`src/dictionary.bats` keeps the StarDict dictionaries Look up reads
without a connection (`src/stardict.bats` reads their bytes: the
.ifo's keys, the headwords' order, an article as text). Like an EPUB,
a dictionary's files never enter wasm memory to stay: they are stored
from the JS side (bridge's `$BF.file_idb_put`) and read back by
ranges. Its import checks the .ifo and the .idx's size, every record
of the .idx and .syn, and a .dict.dz's chunk table, and stores a table ('X') of
every 64th headword of each with where its record is; a lookup
binary-searches it and reads one block of records. An article is
shown as text only (`article_text`): HTML and XDXF tags are dropped,
never put in the DOM. The list of dictionaries (`dicts`) is stored
under "dicts"; a removal moves the dictionary to the Trash (#396, as a
book is: `dict_state`, `Installed | InTrash`, stored in bit 4 of the
form's byte), offered back by the Undo toast, its files kept. It is out of
Look up, listed under the books while the Trash is the shelf shown
(`trash-dictionaries`, `dict_trash_render`) with a Restore, and only Empty
Trash deletes its files (`dict_trash_empty`, in quire.bats' `_harm_clicked`
after `lib_ask_harm` resolves Accepted; the dialog says dictionaries go
too). `tests/static/trash.py` fails any other call: that is a scan of the
source, not a type, and the proof that only an answered dialog deletes
them is owed (the dialog is in library.bats, which cannot staload
dictionary.sats while dictionary.bats uses library's `lib_key`). Drive and
Files by Google keep trashed items, which still use storage, until they
are emptied; the Trash shows counts, not sizes (a dictionary's files are
on the JS side). The backup lists the
dictionaries' names and languages, not their files.

### Sync

`src/sync.bats` keeps places, shelves, collections, annotations and
reading time the same on the reader's devices, through one file,
`quire-sync.json`, in the backup's JSON format plus each record's
stamps, a `deleted` list per book and a `devices` list. Where the file
is kept is a `store` (`WebDav(url, user, password)`, or `Fastmail`,
`Android` or `Dropbox`, below): its credentials are stored on this
device only, by the store's kind ("sync" names the kind, "sync-webdav"
holds the WebDAV ones, "sync-fastmail" Fastmail's, "sync-android" the
account's address, "sync-dropbox" the refresh token), never in the backup. The merge and its tries call only `store_read` (the file,
none yet, or a failure) and `store_write` (written, a conflict, or a
failure); WebDAV's read is a GET whose ETag is the version, its write
a PUT with If-Match (a 412 is the conflict). A sync reads, merges and
writes (again after a conflict, up to 3 tries), and only once the file
is written does this device take the merge, so a failed sync changes
nothing here. It runs when the app opens, when a book is opened, when
the page is hidden, and from the screen's Sync now (`LSync`,
`sync-screen`, opened from the Settings screen's Sync row; Turn off
goes through Undo). That row says sync's state in short
(`sync_summary_show`, refreshed with the screen's status line): "Off",
"WebDAV · synced 2 min ago" ("Fastmail · ...", "Android · ...", "Dropbox · ..."), or how the last sync
failed. The screen (#331, from Android's Backup and Add account
screens and Material's settings) is a status card at its top (where
sync is kept, how the last sync went or what it needs, and Turn off and
Sync now while it is on), then "Sync with": a row per service, its name
only (`sync_service`: Google Drive, Dropbox, Fastmail, Nextcloud,
WebDAV) and, for the one chosen, a word of state ("Connected",
"Paused", "Not syncing"), then a line on what sync keeps. A row opens
its service's own sign-in step (`sync_step_open`, the layer
`LSyncStep`, `sync-step`, first in the screen so the stylesheet hides
what follows it while it shows): what the service does, its fields,
its link, Cancel and its one button (Use Android or Sign in to Google
Drive, Sign in to Dropbox, Sync with Fastmail, Sign in with Nextcloud,
Sync with this folder); a field left empty is said in the step, and
once the sign-in begins the step closes and the card says how it goes.
Escape and Cancel close the step (`sync_step_cancel`, which stops a
Nextcloud poll). The screen lists only what can be used where it runs,
each row shown by its own `data-hide` (`ui_show` in
`sync_screen_open`): no row is there only to say why it is unavailable
(a provider a browser can't reach, a build with no client or key).

Nextcloud is signed in to with its Login Flow v2 (`src/nextcloud.bats`,
#184), which ends in the WebDAV store: the screen's Sign in with
Nextcloud (`sync_nextcloud_sign_in`) takes an https address, starts the
flow (`nextcloud_start`), offers the server's sign-in page as a link
the reader taps (`nextcloud-page`: a tap is never blocked, a script's
`window.open` after an answer is), and polls the flow's endpoint every
3 s for its 20 minutes (`nextcloud_poll`, a form body `token=…`); a new
sign-in or Turn off ends a poll (`_sign_in_generation`). Granted, the
user's id (`nextcloud_user_id`, OCS `cloud/user`: a login name can be an
email, the files folder is named by the id) makes the folder,
`<server>/remote.php/dav/files/<id>` (`nextcloud_folder`), kept with the
login name and the app password as `WebDav`, and a sync runs.

**Fastmail** (#184, #271), in the app only: the store `Fastmail(user,
password)`, its files over WebDAV at
`https://myfiles.fastmail.com/quire/quire-sync.json` (the folder made
by MKCOL at the first write), with the Fastmail address and an app
password the row's link and steps say how to make. Fastmail's WebDAV
sends no CORS headers, so a browser page can't reach it, and a browser
lists no Fastmail and sends it nothing; the app's requests are native.
A refusal is `FastmailRefused`. `sync-providers.yml` checks weekly
whether Fastmail now lets pages in (`fastmail-cors`), so browsers could
list it too. `e2e/sync-fastmail.spec.js` plays its files.

A change is dated by a stamp (`src/clock.bats`): a hybrid logical
clock, minutes since 2025 times 64 plus a count, after every stamp made
or seen here (the browser gives the time only to the minute), written
in the file as milliseconds. Shelves, collections (by name) and being
finished take the latest change, and so does the place (#302): each
move in a book is dated (`place_modified`, only a move to another
chapter or page, not a page counted anew, and none while a book opens
at its place, `reader_open_at`, until the reader acts), and the file
keeps the
latest place with its stamp and the device that read it
(`placeModified`, `placeDevice`); at the same stamp the further place
wins, and a place never dated (kept before places were) never does. The
open book's is not taken but offered, and only when another device read
it later than this device's last move there: in a row of the reader's
bottom bar (`sync-offer`, shown with the bars, so it covers no text),
"Go to where you were on another device (chapter 3)". Dismissed, that
place is declined (`place_declined`, in the library record only, not in
the backup or the file): it is neither offered nor taken again, and only
a later place of another device's is. A backup's place is restored by
the same rule. The reading log and each book's
time are each device's own (its entry in `devices`), summed for display
(`stats_elsewhere_*`, `minutes_elsewhere`). An annotation's id is the
SHA-256 of what never changes in it (bookmark or highlight, chapter,
start, end, minute made), so it is never stored and two devices that
restored one backup give it the same id; the latest change wins, and a
deletion (`deleted`, kept 180 days, `QA3`) wins over a change made
before it. A book only another device has is kept as an orphan ("o").

**Use Android** (#184), in the app only (bridge's
`google_authorize_available`): the store `Android(account)`, the file in
the app data folder of the device's Google account's Drive
(`src/drive.bats`: a listing for its id and version, then its bytes; a
write checks the version is still the one read, else it is a
conflict, and replaces the bytes, or makes the file in
`appDataFolder`). The access token for `drive.appdata` comes from
bridge's `google_authorize` (#321: bats-lang/capacitor-plugins'
google-authorize, Play services' `AuthorizationClient`, shaped as
Flutter's google_sign_in 7.x; Capawesome's Google Sign-In, which shows
Credential Manager's sheet each time, is not used). Use Android and
Sync now ask with `google_authorize_scopes`, which shows Google's
consent screen only when access is not granted; the syncs the app makes
by itself (`_google_access`) with `google_authorization_for_scopes`,
which never shows anything. The token is kept on the device
("sync-google-token", `_google_token_save`) as well as in memory
(`_token`). When Drive refuses it (401, its hour is up) it is
forgotten, taken out of Play services' cache (`google_clear_token`,
which would otherwise give it again) and one asked for once with
nothing shown (`_google_renewed`): a read is made again, a write's round
reads, merges and writes again. Only `NotAuthorized` (the reader took
access back in the Google account) pauses sync (`SignInAgain`): the
Sync row says "Android · paused, tap Sync now", the screen "Sync
paused: tap Sync now to sign in to Google again", no banner; each sync
point still asks with nothing shown (`_paused` is a browser's only), so
a grant given back ends the pause, and Sync now asks for consent. A
cancel says so, and a failure by its code (`_authorize_failure`:
NETWORK_ERROR or TIMEOUT can't reach the server, anything else Google
refused). The account ("sync-android") is the one the authorization
names, else Drive's (`drive_account_address`: about.get's
`user.emailAddress`, which `drive.appdata` may read), else none. Turn
off holds the token for the Undo; made final, it takes the grant back
(`_google_revoke`): `google_revoke_access` with the account and the
scope, or, with no account, Google's revocation endpoint with the token
(`drive_grant_revoke`). A build with no client lists no Use Android.
In a browser (Google Drive, below) the token comes from Google Identity
Services, whose window a page may open only at a tap: there it is asked
for only when the reader acts, a refused one pauses sync, and while
paused with no token the app tries nothing by itself (`_paused`), so
opening it again changes nothing. The client ID is public and not
compiled in:
it is committed in `scripts/sync-clients.env` (#200: the Web
application client `GOOGLE_WEB_CLIENT_ID`, with the Android client's ID
and Play's app signing SHA-1 recorded beside it, and Dropbox's app key,
#239; all public, none a repository variable), and
`scripts/sync-clients.sh` writes the Google client and the Dropbox key
(checked) into `sync-clients.json` beside the app, in CI and a local
build alike, read by `src/sync_clients.bats`; a build with none lists
neither Use Android nor Google Drive. `sync-identity.yml` prints the upload key's
fingerprints and checks the committed values (the IDs' form, and that
Play's SHA-1 is not the upload key's). The e2e suite stubs Google's
script (`googleStubbed` in `e2e/fixtures.js`), so it never reaches
Google; a spec that plays a provider, or a build with no client, serves
its own `sync-clients.json` (`clientsServed`). With no store chosen, the app keeps the file for Android's
Auto Backup (`STORE_BACKUP`, bridge's `backup_file` in `backup/` of
the app's files, the only thing pwa's backup rules keep): each sync
point merges it and writes it there, and the file a reinstall
restores is merged at the first launch like any sync file; a store's
write writes it too. `e2e/sync-android.spec.js` plays GoogleAuthorize
(the account's grant, Play services' token cache and the account it
names, `capacitorPlayed` in `e2e/sync-stores.js`), Filesystem, Drive's
API and Google's revocation endpoint. In a browser the same store is **Google Drive**
(bridge's `google_token_get` there goes through Google Identity
Services' token model: a token for about an hour, no refresh token),
listed only in a build with a client, so Google's script is loaded
only then; the summary says "Google Drive · ...", and Turn off revokes
the token bridge was given in this session (one kept from an earlier
session lapses within its hour) and forgets the one kept.

**Dropbox** (#184): the store `Dropbox(refresh)`, the same `quire-sync.json` in the
app's own folder (Apps › Quire; scopes `files.content.read` and
`files.content.write`). `src/dropbox.bats` reads it with
`files/download` (its rev from the `Dropbox-API-Result` header; a 409
`not_found` is no file yet) and writes it with `files/upload`, mode
`add`, or `update` with the rev read: a 409 `conflict` is the
conflict. `src/web_request.bats` holds the requests it shares with
`src/drive.bats`. The sign-in is OAuth's code flow with PKCE (S256, no
secret: the app key of the Dropbox app "Quire reader" is public,
committed as `DROPBOX_CLIENT_ID` in `scripts/sync-clients.env` (#239)
and written into `sync-clients.json` as `dropboxClient`; a build
without one lists no Dropbox). `sync_dropbox`
keeps the verifier and state ("sync-dropbox-sign-in") and leaves the
page for Dropbox's (bridge's `navigate_away`), which sends the reader
back to the page's own address with `?oauth=dropbox` (the registered
redirects are in `sync-identity.yml`). As the page opens,
`sync_start` takes the code and state from the address and puts the
address back (`replace_state`), Settings opens (`sync_returning`), and
the code is exchanged once the state matches (another's is refused);
the refresh token is kept and the access token held in memory
(`_token`), got again from the refresh token when Dropbox refuses it
(401), with no sign-in. Turn off, once made final, revokes the grant.
In the app (RFC 8252's way for a native app), Dropbox's page opens in
the system browser's tab over the app (bridge's `browser_tab_open`,
Capacitor's Browser plugin), and the redirect is the app's own address,
`quire://oauth/dropbox`. `src/bin/gen-pwa.bats` writes the Android
project's `intent-filters.xml` itself: pwa's `build_intent_filters`,
then the `quire` scheme's filter (`APP_SCHEME`; a scheme Android cannot
match fails the build). pwa's activity hands each such address to the
page once, not again when it is recreated. The app is opened there,
and bridge's `listen_app_link` (the App plugin's `appUrlOpen`, the
`RAppLink` slot of `regs`) hands the address to `sync_app_link`, which
takes the code and state as a browser takes them from its address; the
tab is gone by then (the app's activity is `singleTask`, so coming
forward finishes what is above it, bats-lang/bridge#135). One that
starts the app again (Android stopped it while the reader was in the
browser) waits for `sync_start` to load the stores (`start_state`); one
while the app runs is taken at once (`return_moment`: `AtStart`,
`WhileOpen`). Dropbox is listed in the app only with both plugins
(`_round_trip_available`: `browser_tab_available` and
`app_link_available`, quire's own sequencing of the two).
Dynamic client registration was tried and Dropbox refuses it (only its
trusted partners may), so the app is registered by hand (quire#239).
`e2e/sync-dropbox.spec.js` plays Dropbox's sign-in page, token
endpoint and files API (`e2e/dropbox-server.js`), and
`e2e/sync-dropbox-android.spec.js` the app's Browser and App plugins
with it.

### Catalogues

`src/catalogues.bats` keeps the OPDS catalogues books are got from
(the library menu's Catalogues): each one's name and URL, stored under
"catalogues", Project Gutenberg's alone until the list is changed. A
removal is offered back by the Undo toast; the backup lists them by
name and URL. `src/catalogue.bats` browses one, a page at a time, each
page a step of a trail Back walks (and from the first page, back to
the list). A page is fetched through the bridge (`$FE.fetch`: its
status and bytes), read into an arena piece of at most 4 MiB (a larger
one is refused) and read by `src/opds.bats`, OPDS 1.2 (Atom, with
xml-tree) or OPDS 2 (JSON, with jsonio), into a feed of at most 500
entries: links to other pages, and books (title, author, cover, EPUB)
with Get; its next and previous pages; its search template
(`{searchTerms}`, or OPDS 2's `{?query}`), or the OpenSearch
description that holds one, fetched after the page. Every address is
resolved against the page's own (`src/url.bats`, RFC 3986). Get
fetches the EPUB acquisition link (an EPUB 3 one first), puts its
bytes on the JS side (bridge's `$BF.file_store`) and imports them as a
picked file is (`import_fetched`), so a book already there is asked
about. Where the fetch fails (in a browser, a page without CORS), Get
gives way to a download link (`ui_download_nn`) "then import it". A
page that cannot be read says why: not readable by a browser, not
found (404), needs a sign-in (401, 403), or not a catalogue.

### Narration

A book with EPUB 3 Media Overlays (EPUB 3.3 §9) is read aloud by its
own recorded narration (issue #133). Its chapters' overlays are found
once, with the chapters (`_spine_build`): a spine item's manifest
`media-overlay` names the SMIL's item, whose entry is kept in the
chapter (`chapter_overlay` in `src/book.bats`); `_book_narrated` is set
when any chapter has one, and the bottom bar's `narration-controls`
then take the place of reading aloud by speech (`_narration_offered`).

`src/overlay.bats` reads a SMIL's bytes (the format alone, as
`src/stardict.bats` reads a dictionary's): its body, seq and par
elements flattened, in order, into clips, each a par with an audio
element (one without is passed over; `media:duration` is not read).
Each clip is 32 bytes of a `clip_table(count)`, at most 32768: its
begin and end (clock values as H.4 has them; no clipEnd is the audio's
end; a value over 2^31 - 1 ms makes the clip invalid), its audio entry
(found relative to the SMIL's directory when the chapter loads), its
text's fragment, whether it is skippable (it or a seq around it is a
footnote, endnote or pagebreak) and the clip after the innermost
escapable table, list, figure or aside it is in. A clip's index is
proven below the table's count, so reading past the table does not
type-check (`tests/static/reject/clip-past-end`).

As a narrated chapter is rendered, an element with an id is matched
against the next 8 clips not yet matched (`_clip_match` in
`src/reader.bats`): a match keeps the element's first content node and
the one after its last (`!_content_count` after its children, as
`_link` does). An unmatched clip still plays, with nothing marked and
no page turned. Then the SMIL is freed and only the clip table is kept,
for the narration to take (`reader_clips_take`).

`src/narration.bats` plays it on one `<audio id="narration">` (made by
`ui_audio`: no controls, `aria-hidden`; not a control, so the tag type
stays closed to them), for the whole book, so the permission a click
gave it holds clip after clip. Its state is `Idle`, `Playing(clip,
generation)` or `Paused(clip, at)`, each clip proven below the table's
count. The source is a blob URL of the audio entry, made on the JS side
from the book's file when it is stored (`book_blob_url`, file's
`file_blob_url`), or from its bytes inflated into a piece when it is
deflated; the URL is revoked when the entry changes and when the book
is closed. Each clip is played from its begin (one that follows the
last in the same audio plays on without a seek), marked with
`mark_range` kind 5 (`::highlight(bats-mark-5)`, the proven pair of
read-aloud's highlight), and its page shown when its text is not on
the page. A timer at its end, by the speed, checks `audio_time` and
moves on within 20 ms of the end, else sets itself again; the timer
reaches `_tick` through a cell (`_tick_handler`), as an event reaches
its listener, so playing on is not a recursion. `timeupdate` is a
backstop, and `ended` covers an audio file shorter than its clip. A
generation number drops the timers and answers of earlier clips. At a
chapter's end the narration goes on into the next chapter with an
overlay (`book_narrated_after`). A page the reader shows (a turn, a
jump, a new chapter; the promise `reader_page_shown` resolves) moves it
there: from the first clip on or after the page, or the chapter's
first; so does a tap on text a clip reads. A play the browser refuses,
or an `error`, stops it, and the error banner says "This narration
cannot be played"; a
`pause` it did not ask for (a headset, a call) leaves it paused. The
screen stays awake while the reader is open, so while it plays.

The controls: Read aloud (`aria-pressed`), Previous phrase, Next phrase,
and, inside an escapable structure, Skip table (list, figure, aside).
The reading settings' Read aloud tab offers, for a narrated book, its speed (0.5× to
2× in quarters, `audio_rate`, the pitch kept) and whether page numbers
and notes are read (Skip by default: skippable clips are passed over).
Both are the device's own, kept outside the settings record as `_ruby`
is; in its storage they follow the voices, after an "N" (a record
written before them has their defaults); the reset's Undo and the
backup's settings (`narrationSpeed` in hundredths, `narrationReadsNotes`)
cover them.

### The archive is checked once

`book_begin` opens a book (an import, or a restore from IndexedDB) and
checks its archive then, once: the end record, the central directory
(zip's `cd_refs`) and every entry's local header. What survives is the
book's index (`book_index`): the kept directory and a list of entries
whose data spans are proven inside the file. Reading an entry
(`index_read`, for the container.xml, the OPF, a chapter or an image)
only looks its name up there; nothing in the file is checked again.

A book's chapters are found once too, the first time one is loaded
(`_spine_build` in `src/reader.bats`): the OPF is read and parsed, and
each spine item's href, after the OPF's directory, is looked up in the
index. The chapters (`book_chapters`, each an entry whose data span is
proven, or missing) are kept in the book (`book_spine_set`), so loading
chapter i only walks to it (`book_chapter_get`); the OPF is not read
again.

A chapter's data is checked against its CRC-32 (#529): the central
directory record the index keeps states it (offset 16), `book_entry_sum`
reads it by the chapter's name offset, and `take_text_sum` (in place of
`take_text`) computes the CRC-32 of the inflated bytes, before they are
made UTF-8 (`crc_of_cborrow`, `src/crc.bats`, proved: see "The CRC-32
table method is proved" below; the piece is lent as a `barr` by array's
`barr_of_arrx` and given back to its arena by `barr_to_arrx`), and answers no content for a mismatch or an unknown sum, so the
chapter is `ChapterNotRead` ("Chapter N of this book could not be read")
and the others read. libzip (`ZIP_ER_CRC`), Python's `zipfile`
(`BadZipFile: Bad CRC-32`) and Java's `ZipFile` check the same sum at the
end of the entry. The chapter shown and the facing page of a spread are
checked; the OPF, the container, images and the chapter reads for
search, notes and read aloud are not (yet). `e2e/containers.spec.js`
("a chapter whose CRC is not its data's").

### The CRC-32 table method is proved (#553), and it is the call's

`crc_of_cborrow` (`src/crc.bats`) is `crc_of_borrow`'s table method over
an array whose cells are in its type (array's `barr`, borrowed as
`cborrow(l, n, cs)`, its `cborrow_get` giving `NTH(cs, i, v)`), and its
type is the statement: for the cells `cs` (`CLEN(cs, n)` of them, nothing
else known) the bytes read are a list `octets` that the cells hold
(`HOLDS(cs, 0, octets, n)`, bytesarr's), and the register after them is
the proven fold's (`CRCFROM(65535, 65535, octets, 65535 - high, 65535 -
low)`, the CRC being its complement), so it cannot disagree with the
codec; a caller that knows what the cells hold has it from
`holds_functional`. No `praxi`, `assume` or `$UNSAFE`: the compiler checks

* the table: entry i is the register `bstep` makes from zero
  (`TABLED(cells, count)`, an `ENTRY` of four `NTH`s and the `BSTEP(0, 0,
  i, ...)` for each i < count, kept as the cells are set, `tabled_set`,
  by array's `setc_nth_other`; `tabled_get` finds entry k of a full
  table);
* the byte step (`bstep_by_table`): `BSTEP(high, low, octet, ...)` is
  the register shifted right by 8 bits xored with the entry of the byte
  `(low mod 256) xor octet`. It is built from arith's XOR algebra
  (`xor_comm`, `xor_assoc`, `xor_half`, `xor_double`, #553), `xor_cat`
  (the xor of numbers with numbers above them is the xor of both, by
  induction on the bits, linear in the solver) and `xor_cancel`; the
  step is linear in xor (`step1_xor`, `stepn_xor`, by cases on the
  parities of the three low halves, the polynomial xored into none or two
  of the three); a register whose low byte is zero shifts without the
  polynomial (`shift8`, from `shift4` and `shift2` by `stepn_append`, each
  statement in digits so no index nests a division: eight chained
  `step_even` with `high/256` in their indices did not finish under the
  infinite-precision solver, quire#594); every register has a next one
  (`stepn_exists`, with `xor_exists`), so the step of the whole is
  compared with the table's entry and the pure shift;
* the loop (`crc_of_cborrow`): the invariant is `HOLDS` of the bytes read
  so far (`holds_snoc`, by induction on the list) and `CRCFROM` of them
  (`crcfrom_snoc`), with `table_step` giving each `BSTEP` from the table
  read through `barr_get`.

`tests/codec` still runs it on the check value of "123456789" and arrays
of every length 1 to 300 and 4000 against the fold, as a check of the boundaries, not as the proof
(`tests/static/accept/crc-*` and `reject/crc-*`: a shift of 8 bits whose low half is off, a table entry of another
byte, the step by another byte's entry, a high half not shifted, a loop
step of another byte, the register not complemented and a cell read for
another all fail to type-check).

The call is that one (`take_text_sum`, `_sum_matches` in `src/book.bats`):
the inflated piece, an arena's `arrx(byte, l, n, arena)`, is lent as a
`barr` by array's `barr_of_arrx`, which returns the `arrx_lent(l, n, o)`
proof that keeps its owner (the arena's count of outstanding pieces does
not change while it is lent, so the arena cannot be destroyed, and
`barr_to_arrx` gives it back only as the same piece of the same arena);
the barr is frozen, `crc_of_cborrow` reads it, it is thawed and given back
before the piece is freed or made text. What the proof says of the call is
that the sum compared is the CRC-32 of a list of bytes the cells hold;
the cells are those of `barr_of_arrx`, so nothing relates them to what the
decompressor wrote into the piece (that is outside quire's types, as the
platform's atoms are). `crc_of_borrow` and its helpers are gone;
`tests/codec` checks `crc_of_cborrow` against the proven fold on the check
value of "123456789" and arrays of every length 1 to 300 and 4000, as a
check of the boundaries. This needs array 2026.10.14.60158 or later (the
one `bats.lock` names).

What is proved, then, is that the CRC-32 compared with the entry's sum is
`crcfrom`'s fold over the bytes the arena piece holds, as the production
call computes it. What is trusted, not proved: array's one unsafe core
(`barr_of_arrx` and `barr_to_arrx` are casts that keep the owner,
`cborrow_get` reads the byte it says, tested in array's
`tests/dynamic`), arith's C operators behind `xor_g1` and the prelude's
`/` (tested in arith), the stored sum `book_entry_sum` reads from the
central directory, and that the fold itself is CRC-32 (its polynomial
0xEDB88320 and the check value of "123456789", the latter tested in
`tests/codec`). Nothing in quire uses `praxi`, `assume` or `$UNSAFE` for
it.

### Note popups (#414)

A note opens as its text, in one popup (`footnote`): an element's text
is gathered from the chapter's XHTML by its id (so a note marked `aside`,
`div`, `li` or none, and one `hidden` or not, all open), a block ends in a
space and an inline element does not (a reference "3" and the "." after it
stay together), and a note over 4 KiB (`NOTE_CAPACITY`) ends in an ellipsis,
cut at a whole character and outside a character reference. The popup has no
links in it: links in a popup are what an iBooks popover collapsed on (Stack
Overflow 12952352) and Apple advises a note of one paragraph; the note's own
links, nested notes and backlink work where the note is, which Go to note
reaches, with the way back. No unmarked footnote is detected (Calibre's
maintainer does; Apple Books and Kobo ask for markup, and a heuristic opens a
popup for a "see 3" cross-reference): an unmarked link is a link.
`e2e/footnotes.spec.js` plays `e2e/note-books.js`.
### Wide and structured content (#413)
A table is its own scroll container (`.caf table`: `overflow: auto`), at
most as wide as the column and as tall as the reading area
(`calc(100dvh - var(--page-top) - var(--page-bottom))`, as a picture is):
a block that scrolls cannot be split between columns, so a table taller
than the page, as it was (`overflow-x` made it scrollable too), lost every
row past the page's foot (90 rows: the first six were all that could be
read). `pre` wraps (`white-space: pre-wrap`) and keeps its spaces, tabs
and blank lines, and, being no scroll container, continues over the pages.
Verse keeps its `<br/>` lines and the indents made of no-break spaces;
indents made of the book's CSS (`text-indent`, `padding-left`, hanging)
are not kept, since no publisher CSS is applied (#411), and a wrapped
line of verse is told from a new one only by the text.
`e2e/wide.spec.js` plays `e2e/wide-books.js`.
### Position stability and page-turner keys (#412)
The place is a content node (the first paragraph that begins on the page,
`_anchor_kept`), not a page: `e2e/stability.spec.js` changes each of the
theme, font, size, line spacing, paragraph spacing, margins and columns,
and the window (paged, two columns, scrolled, vertical, fixed-layout),
several in a row, and kills the app after each, and the paragraph is on the
page shown (the one at the page's middle is not: a page's first
paragraph is what is kept); a book converted from each of QLB1 to QLB6
opens at its stored chapter, page and anchor (`e2e/legacy-library.js`
holds the old record and the store for it, as `library-records.spec.js`
uses them). Keys: the page turns by the arrows, Page Up and Down, Space
(Shift for back), the volume keys when the reader chooses (the Android
app's), and MediaTrackNext and MediaTrackPrevious (a page turner's
multimedia mode: the DuRoBo Moodi sends previous and next track there, its
reading mode the volume keys; the others in the field send the arrows or Page
Up and Down). Enter follows the focused link and is no page key. Keys are not
the page's while a text field or a panel has the focus, and a volume key is
the system's while a panel is open. `gen-pwa test` serves the app at a port
the kernel picks, and a bare `npx playwright test` at `QUIRE_PORT`
(`playwright.config.js`), so two runs of the suite from two checkouts
do not serve each other's build.
### Where a book opens the first time (#409)
A book never read opens where it says reading starts, as Apple Books
opens at the bodymatter landmark (and as the EPUB 3.3 landmarks section,
DAISY's knowledge base and Thorium's "Start of Content" have it), not at
its cover or copyright page: `toc_start_dest` (`src/toc.bats`) gives the
chapter and fragment of the first `bodymatter` entry of the nav document's
`landmarks` nav (`nav_part`'s `PartStart`, read beside the contents and
the page list in `toc_build`), else, for a book with none (EPUB 2), of the
OPF's `<guide>` `<reference type="text">` (`find_guide_text`, its entry
found in `toc_locate`; its fragment is not kept). A start that names no
chapter of the book (no href, a file the book lacks, one outside it)
gives none, and the book opens at its first spine item, saying nothing.
`reader_open_at` takes `unread`: set by `_open_book` only when the place
is the first chapter's first page, no move has been dated
(`place_modified` 0) and no minute is read, so a book once read, even
back at its first page, opens at its kept place. The chapters, contents
and fonts are made ready first (`_book_prepare`), so the cover is never
shown before the jump; the jump is not dated, as no open is.
The landmarks are not listed in Contents (issue #409: Apple Books uses
the bodymatter landmark to open the book and lists none, Calibre's viewer
shows none, only Thorium has a Landmarks list; publishers put the
contents page, index and list of illustrations in the table of contents
too, so the list would repeat it).
`e2e/landmarks.spec.js` plays the books in `e2e/landmark-books.js`
(`createEpub`'s `landmarks`, `guide` and `epub2`), and
`e2e/epubcheck.spec.js` checks every book there with epubcheck (5.2.1,
pinned with its SHA-256 in `check.yml`; `EPUBCHECK_JAR` names the jar
locally): a valid book must pass, one that is invalid on purpose (a
landmark naming a file the book lacks) may give only the errors its
entry lists.
### Publisher styling and the reader's settings (#411)
No part of a book's own styling reaches the page: the CSS (a `<style>`, a
style attribute, `!important`, a media rule) is dropped with the rest, and
so are the obsolete presentational attributes (`<font>`, `bgcolor`,
`width`), so a book's sizes, colours, grounds, margins, alignment, line
height and font cannot fight the size, theme, margins, Justify, spacing and
Font settings, and no theme has a light slab. That is the opposite of
Readium CSS (Thorium), which keeps the publisher's styles unless the reader
turns advanced settings on, and in which an `!important` in a book can beat
a setting. What only CSS hid (`display:none` by a rule or a style
attribute) is shown, there being no CSS to say it; the `hidden` attribute is
HTML's own word and is kept: `_pass_attrs` gives an element that has it the
class `hidden-by-book`, which the stylesheet hides. `e2e/publisher.spec.js`
plays `e2e/publisher-books.js`.

### The print page list and page breaks (#415)

The Pages tab lists the page list's entries as the book gives them (not
sorted, duplicates kept, each going to its own target); an entry whose chapter
the book lacks is listed and leads nowhere (the panel stays), one whose fragment
is missing goes to its chapter, an empty page list shows no tab. The
footer names the latest page the screen reaches, from the break's `title`, else
its `aria-label`, whichever of `epub:type="pagebreak"` or `role="doc-pagebreak"`
the element has, with no page list too; a break with neither is shown and names
no page. A label in the contents or the page list is decoded as any text is
(numeric references too) and cut at a whole character.
`e2e/pagelist.spec.js` plays `e2e/pagelist-books.js`.
### EPUB 2 packages (#416)
A package of version 2.0 (OPF 2.0, XHTML 1.1, an NCX, no nav) opens as
an EPUB 3 one does: its contents are the NCX (`navPoint`s listed in
document order, whatever their `playOrder`; one with no `content` is listed
and leads nowhere, one with no label is "Untitled"), its cover the
manifest item a `<meta name="cover">` names, its `<guide>`'s `text`
reference where a first open lands (#409), its author the first
`dc:creator` as written (`opf:file-as` is not read: books are sorted by
the name shown). XHTML 1.1's named entities (`&nbsp;`, `&mdash;`) are
decoded as any text's are. A DTBook or OEB 1 spine item (`application/x-dtbook+xml`,
`text/x-oeb1-document`, which a package names an XHTML fallback for) is read
as XML and its text shown. A Hebrew book whose spine names no direction
reads right to left, as Readium reads it. A row of the contents or the
page list that leads nowhere keeps the panel up (`reader_goto_entry` and
`reader_goto_page` say whether they went).
`e2e/epub2.spec.js` plays `e2e/epub2-books.js` (create-epub.js's `epub2`,
`creatorXml`, `ncxNavMap`, `alsoNav` and `extraSpine`), each book valid
under epubcheck 2.0 rules except those invalid on purpose.

### Found while taking this inventory

* (Fixed) An EPUB larger than 1 MiB could not be imported, because the
  whole file was read into one `alloc`. Entries are now read at their
  offsets, and the file has no size bound. An entry's data and its
  decompressed content are read into arena pieces, so a chapter over
  1 MiB is shown; only the central directory is still read into one
  buffer of at most 1 MiB.
* (Fixed) Book images were not shown. A chapter's `<img>` elements are
  now filled once the chapter is rendered: each src is resolved against
  the chapter's directory ("." and ".." segments, a "#fragment"
  dropped), its entry read into an arena piece (decompressed into
  another when deflated) and handed to the element as a blob URL. An SVG
  `<image>` (a cover page's usual form) is shown the same way, as an
  `<img>` whose source is its `xlink:href` (or `href`).
* (Fixed) Ruby was shown as blocks: `ruby`, `rb`, `rt`, `rtc` and `rp`
  were made `div`s. They are now kept as themselves (`_tag_of`), so a
  reading sits over its base and `rp` is not shown. The settings' Ruby
  row (Show / Hide, byte 19 of the "S2" record, `ruby` in the backup;
  held apart from the settings record in memory, as the device's own
  settings are: each of the record's setters writes it out whole, so a
  field there costs a line in every setter, and a cell of its own one
  setter; quire#210)
  is offered once a chapter of the open book has shown a ruby
  (`_ruby_seen`); Hide adds `.caf rt,.caf rtc{display:none}` to
  `style-type`. Search (`_scan_node`) does not match inside `rt`, `rtc`
  or `rp`, but counts their content nodes as render makes them, so a
  hit or an annotation after a ruby keeps its node number.

* Where a place is (#383): the footer, the bar's label (`scrubber-percent`)
  and its tip say how far into the book in one wording, "6% of book"
  (`_put_book_percent`, over `_put_percent`; "<1%" once reading has begun),
  where the label said "6%" beside the footer's "6% of book". A Contents
  row and an annotation's chapter (its heading in the list, a bookmark's
  row) say where the chapter starts, by `toc_place_of` over src/locator.bats
  (the same `locator_kind` and number as a search hit; `ByPage` in a
  fixed-layout book, `book_fixed`; `locator_thousandth` is the one rule of
  the percent, shared with `_thousandth`). The Contents place is a span
  over the row's right end (`toc-place`, in `toc-line`), not text of the
  button, so a row's name stays its label. The `place_text` datatype of
  the issue's "Prevent" is not made: a flat datatype cannot carry the
  number, and the number's wording is written in one place instead
  (`_put_book_percent`, `locator_put`). An annotation's row goes to its
  place by the whole row (`.hgo`, with a chevron at its end), Delete is
  quiet (`.quiet`: no edge, muted; it has Undo, so it is no equal of Add
  note), and each style's filter has a swatch. `e2e/places.spec.js`.
  Not done, filed as a follow-up: a place for each annotation row (the
  chapter's is shown, not the annotation's own page).

* A search result row (#381) shows the hit in its snippet, the match in
  bold (`.mk`; no new colour pair), and where it is in the book. The
  snippet is cut into three spans (`search-hit-lead`, `-mark`, `-trail`)
  by `hit_at` and `hit_len`, which `hits_cons` carries with the proof
  `hit_at + hit_len <= snippet_len` (`_snippet`, `_hit_in`), so a row
  cannot take a span outside its snippet. The place is a `locator_kind`
  and a number (`src/locator.bats`, shared with Contents in #383):
  `ByPercent`, the thousandths of the book at the hit by the chapters'
  sizes and the hit's content node among the chapter's (`_hit_locator`,
  the footer's scale and `book_weights`), or `ByPage`, the spine item,
  for a fixed-layout book. A page of the current layout is not used: it
  is unknown for a chapter that is not laid out and changes with the
  font (Kindle's Location is fixed for the same reason). Each chapter's
  heading counts its hits ("3 results"). Decided by research (comment on
  #381): Material 3's list item has a trailing supporting text for a
  position; no help page of Apple Books, Kindle or Play Books documents
  the layout of its results.

* Search finds a phrase across inline elements (#437): un<span/>believable,
  a drop cap, `<em>emph</em>asis`, a phrase running out of a page-break
  span. The text of a block's inline nodes is searched as one text
  (`_scan_text`, `_find_in_block` in `src/reader.bats`): a tail of the
  last query length - 1 bytes, each with its content node and UTF-16
  offset, is searched for hits that start in it and end in the next text
  node, then that node for the hits inside it. A hit has a start and an
  end (content node, offset), which are different nodes for a phrase
  across elements, and `mark_range` takes both. Blocks (what `_tag_of`
  does not show inline), `br`, `hr` and images end a phrase; a ruby's
  `rt`, `rtc` and `rp` are neither searched nor a break, so a base reads
  on through its reading (the mark runs over the reading, which is in the
  page). Node numbering is unchanged, so annotation offsets do not move.
  Decided by research: foliate-js joins the strings of its text walker
  and maps a match to a start and an end in different entries; the Calibre
  viewer's manual documents whole-word, contains and accent/space-blind
  modes and nothing on tags; Readium's search architecture page and
  Thorium's pages document nothing on it (a search for them found
  nothing); the W3C find-text draft notes browsers rarely match across
  element boundaries and none across blocks is expected.

## Spine items and fallbacks (#419)

The W3C's EPUB 3 test suite (`reports/quire-w3c-epub-tests.md`) found that
a spine item was read as XHTML whatever its type: a 3 MB PNG as a spine
item killed the page (`lay-pp-images-in-spine`), a JSON or XML one was
shown as text and the fallback its manifest names was never followed.

* **A spine item shows a content document** (`find_chapter_shown_href_n`
  in `src/epub_xml.bats`, used by `_spine_chapters` in `src/reader.bats`):
  the item itself when its media type is `application/xhtml+xml`,
  `image/svg+xml`, `text/html`, an OEB 1 or DTBook document (read through,
  quire#416) or none is given; else the item its `fallback` names, and so on
  down the chain (at most 16 items, so a loop ends), as EPUB 3.3 §3.3
  says. An item with the property `scripted` and a fallback is replaced by
  the fallback too, since Quire runs no scripts (`scr-support-fallback`;
  one with no fallback is shown, scripts unrun). An itemref none of whose
  items is a content document is left out of the chapters, so the reader
  never turns to it and never reads its bytes as XHTML; the book opens at
  the next. Decided by the spec and the suite's reports: EPUB 3.3 (§3.3,
  §3.5.1) makes a foreign resource valid in the spine only with a manifest
  fallback to a content document, and the suite's own pass criterion is
  that the fallback is shown; the W3C working group's minutes (2022-03-11)
  found few reading systems that show it, so the suite's reports hold
  the comparison (`lay-pp-images-in-spine` 2/2, `pub-foreign_json-spine`
  4/9 pass). No documentation of what Thorium or Readium do with a
  spine item they cannot render with no fallback was found (searched:
  the specs, the working group's minutes, Readium's wiki); skipping it is
  chosen because the alternatives are a page of binary text or refusing the
  whole book, and no word of the book is lost. The
  chapters' count is the count kept, not the itemrefs' (`_spine_chapters`
  returns both).
* **An `<img>` whose manifest item is a type no browser draws and has a
  fallback is shown as the fallback** (`pub-foreign_image`): at the
  spine build the items that are not a core image type and have a
  `fallback` are found (`find_image_fallback_n`, `find_image_target`: the
  chain down to a core image, 16 items at most, 256 items at most) and
  their entry paths kept (`image_fallbacks`, replaced by the next book's),
  and `_show_image` shows the target's entry when the image's path is a
  kept one, so the image viewer does too.
* **The title and author are the first `dc:title` and `dc:creator`**
  (`_opf_metadata_node`), as EPUB 3.3 §5.4 makes the first title the main
  one and a reader needs one author (`pkg-title-order`,
  `pkg-creator-order`). EPUB 3's `title-type` refinement is not read.

## The archive and the XML are checked for what EPUB forbids (#419)

* **A zip that EPUB's OCF forbids is refused at import** (`src/zipcheck.bats`,
  called from `book_index_make` in `src/book.bats`; the suite's
  `ocf-zip-comp` and `ocf-zip-mult`, both "MUST treat ... as in error"):
  an archive whose end record names a disk other than 0 (a split
  archive), and one with an entry compressed by a method other than stored
  or Deflate. The zip package leaves such an entry out of its references
  without a word (its own documentation says so), so a book with a bzip2
  chapter used to open with the chapter gone; `zipcheck` reads the end
  record's and the central directory's own fields, `book_refusal` says
  why, and the import banner says it (`ArchiveSplit`,
  `CompressionNotAllowed`: "... is a zip split into segments, which an
  EPUB may not be ..."). The zip package is the tool that could report this
  itself (a refusal in `cd_refs`); until it does, the check is Quire's.
* **A content document that is not well formed is not shown**
  (`src/wellformed.bats`, `xml_well_formed`, called by `_chapter_render`;
  `pub-xml-non-validating_unclosed`, `pub-xml-names`, both "The reading
  system must produce an error", EPUB RS 3.3 §3.1: a non-validating XML
  processor, a fatal error for a document that is not well formed):
  an element not closed by its own end tag, an end tag that closes
  another, and an element name with two colons, a colon at either end, a
  digit first or a character no name has. The chapter is then a chapter
  that could not be read: the banner says "Chapter N of this book could
  not be read" and to open another chapter or import it again with
  Replace. Comments, CDATA, processing instructions, the DOCTYPE and
  quoted attribute values (with a `>` in them) are read over, and entity
  references are not checked: XHTML's named entities are decoded as any
  text's are. Of the reading systems the suite holds, 8 of 9 (unclosed)
  and 9 of 9 (names) pass, Thorium and Apple Books among them. The check
  is on the chapter shown; the chapters read for search, notes or
  narration are not refused. xml-tree builds a tree from any bytes, so it
  reports nothing itself; a well-formedness error from the parser would
  be the better place for it.
* **An image the manifest does not list is shown, by decision**
  (`pkg-manifest-unlisted-resource`, a SHOULD): the zip is read by name.
  11 of the 15 reading systems that answered the suite show the image
  too, hiding it would blank the images of books whose manifest is merely
  incomplete, and nothing is gained, the file being in the book's own
  archive.

## The package's directions and language (#419)

* **A title's and an author's direction are the package's** (`opf_text_directions` in
  `src/epub_xml.bats`; the suite's `pkg-dir_creator-rtl`, `pkg-dir_rtl-root-ltr`,
  `pkg-dir_rtl-root-unset`, `pkg-dir_unset-root-rtl`): the first `dc:title` and the first
  `dc:creator` take their own `dir` (`ltr`, `rtl`, `auto`), else the `package` element's.
  They are kept in the book's record as one number (`text_directions`, title + 4 * author, the
  optional group `tdir`, lower case so an older Quire keeps it as an unknown chunk), set at
  import and again by Replace, decoded once into a `text_direction` (`_direction_of_code`), and
  the library card sets `dir` on its title and author (`ADir`). `dir=auto` is the browser's
  first-strong-character rule; none leaves the page's. A book imported before this has none
  until it is replaced. The backup and sync do not carry it (it comes from the package).
* **The package's language and direction are not the content's, by decision, and the suite's
  `pkg-lang_but_not_content` and `pkg-dir_but_not_content` stay failures.** A chapter that
  names no language is shown in the book's (`_page_book_lang`; "und" when the book names none):
  browsers hyphenate and pick quotation marks only for text whose language is known (MDN on
  `hyphens`; the CSS specification requires hyphenation only where the content language is
  known), and the package's `dc:language` is the only language a book declares. A Hebrew or
  Arabic book whose spine names no direction reads right to left (#416, as Readium reads it): the
  page is one flow of CSS columns whose order is the page's `direction`, so a list or paragraph
  in it inherits it. The suite's criterion (a document that names none stays in the reading
  system's own language and left to right) is met by 11 of the 15 reading systems that answered
  for language and all 13 for direction, which lay each document out on its own; Quire's flow
  cannot without giving up one of those two decisions. They stay listed as policy in the report.

## Addresses and labels in a book (#419)

* **A path-absolute address is the container's** (`href_rooted` in `src/paths.bats`, used by
  `book_find_relative` and `_load_image` in `src/reader.bats`; the suite's
  `ocf-url_link-path-absolute`, "MUST ... resolved from the container's root"): an image's `src`
  or a link's `href` that starts with `/` names the entry of that name from the root of the
  zip, not from the document's directory, so `/OEBPS/images/a.png` in OEBPS/ch1.xhtml is
  OEBPS/images/a.png, not OEBPS/OEBPS/images/a.png. epubcheck calls such an address a
  warning (RSC-026); the reading system still shows it.
* **An image given as a data URL is shown** (`src/dataurl.bats`; `pub-data-urls_browsing-context`
  and `pub-data-urls_top-level-content`, "must display the image rather than opening it in a new
  top-level browsing context"): `data:image/<png|jpeg|gif|webp|svg+xml>;base64,...` is decoded
  by Quire (`base64_decode`) and given to the image as any entry's bytes are (`_load_data_image`),
  because the dom package refuses a `data:` URL as an attribute (a script cannot run from one).
  One over 512 KiB of text (alloc's bound is 1 MiB) or of another type is not shown, and it is not
  offered to the image viewer (it is not an entry).
* **A navigation link holding an image is labelled by the image's alt text, else its title**
  (`_gather_image` in `src/toc.bats`; `nav-non-text_img`, `nav-non-text_img_title`): EPUB 3.3
  asks for alternative text on a link's image, and the label was "Untitled".
* `nav-spine_in-spine-hidden-toc-html` passes: the navigation document in the spine hides an
  entry marked `hidden` (the attribute is kept, #411) and the contents panel, made from the
  nav, lists all.

## Audio and video play (#424, #419)

An `audio` or `video` element of a chapter is made as such with the browser's own
controls (dom's `Controls`) and never autoplay; its `src`, or the first `<source>`'s,
is the book's entry, given as the picture's bytes are (`images_cons` on the element:
bridge's `set_image_src` makes a blob and sets the element's `src`, which is generic,
not an image's). A `<source>`'s file goes to the media element itself, since a
`<source>` given its src after insertion is not looked at again (the last of several
sources given, the first in the document, wins: no `type` selection). By research: Apple
Books plays embedded audio and video, Kobo's apps do (its e-ink devices show the
fallback), Thorium, Foliate and Calibre's viewer are browser engines that play them. The
file passes through wasm memory (a piece of the chapter's arena); a long video is
heavy there (a stored entry could instead be a range blob on the JS side, as narration's
audio is: not done). Leaving the chapter removes the element, which stops it.
`e2e/media.spec.js` plays a real mp3.

## Links out, scrolled books, fonts and speech for the W3C suite (#419)

* **A link out of the book asks first** (`_external_ask` in `src/reader.bats`;
  `pub-external-links`, `pub-external-links_consent`: "should open it in a new
  browser instance after the reader's consent"): the page's `<a>` no longer carries
  the address (it would open at once); the address is kept (`links_cons`, up to
  2048 bytes) and a tap or Enter on it opens the note overlay with "This link leaves
  the book. It goes to <address>." and a real link, Open link (`footnote-open`, `rel=noopener`,
  `target=_blank`), that the reader taps (a tap is never blocked, a script's
  `window.open` after an answer is); Close ends it. The same overlay as a note's
  (`LNote`), with Go to note hidden. By research: the suite's reports have 7 of 15 reading systems
  passing `pub-external-links` and 4 of 12 `pub-external-links_consent`, and the test is
  "should open it ... after the reader's consent"; a link that opens at once cannot be told from one the page did not mean to
  follow, and nothing is lost by one more tap.
* **A book can ask to be scrolled** (`opf_scroll_preferred`, `flow_scrolled`,
  `_book_scrolls` in `src/settings.bats`; `lay-pkg-flow-scrolled-doc`,
  `-continuous`): the setting Pages | Scroll starts as `ByBook` (the default of a new
  install; a kept setting keeps its value): a book whose OPF has `rendition:flow`
  `scrolled-doc` or `scrolled-continuous`, or `rendition:layout` `roll` (EPUB 3.4's
  draft roll layout, webtoons; `lay-roll-embedded-images*`), is scrolled until the reader
  chooses Pages or Scroll; any other is in pages. The reader's choice outranks the
  book's (EPUB RS 3.3 lets a reading system override `rendition:flow`; Readium can
  scroll any book on the reader's word). A roll is not one strip across documents:
  each document scrolls and the next follows at its end. Reset to defaults puts `ByBook` back.
* **A SMIL with no audio is read by speech** (`_overlay_load`; `mol-tts_single`,
  `mol-tts_multi`, "falls back on Text-to-Speech when no audio file is present"):
  a chapter whose SMIL has no clip to play (`overlay_count` is 0) does not offer
  the narration's controls, so reading aloud by speech (where the platform speaks)
  takes its place and reads the chapter from the page; the SMIL's order and its
  `media:active-class` highlight are not used.
* **The package's fonts are the Book font** (`cnt-css-fonts_ot`, `_tt`, `_woff`,
  `_woff2`): the book's CSS is dropped (#411), so which text uses a font is the
  reader's: Font: Book loads the first font of the manifest (`font/otf`, `font/ttf`,
  `font/woff`, `font/woff2`) for the text. An obfuscated font is undone (#410, below).

## Obfuscated fonts are undone (#410)

EPUB OCF 3.3 section 4.1.2 requires a reading system with a viewport to undo
the two font obfuscations, and a reader that skips them falls back to a default
face without a word. `src/font_obfuscation.bats` undoes both (xor is its own
inverse, `font_unmask`): IDPF's (`http://www.idpf.org/2008/embedding`: the
key is the SHA-1 of the package's unique identifier with its white space,
U+0020, U+0009, U+000D and U+000A, taken out, 20 bytes, xored with the font's
first 1040 bytes going round; `idpf_key`) and Adobe's
(`http://ns.adobe.com/pdf/enc#RC`: the 16 bytes of the identifier's UUID, after its
last colon and without its dashes, xored with the first 1024; `adobe_key`).
SHA-1 is `src/sha1.bats` (pure Bats, as the sha256 package is written; it is
used for nothing but this key, and belongs in a package of its own when one is
made). The unique identifier is the `dc:identifier` the package's
`unique-identifier` names (`opf_unique_identifier`, copied by `_font_locate`).
Which algorithm a font has comes from `META-INF/encryption.xml`, read as the font
is loaded (`_font_cipher_find`): each `EncryptedData`
(`encrypted_nth`) names a `CipherReference` URI, found with `book_find_relative`
from the container's root, and it is the font's when its entry is the font's
(`font_cipher`: `FontNotListed`, `FontObfuscatedIdpf`, `FontObfuscatedAdobe`,
`FontCipherOther`). The font is unmasked in its piece before its blob URL is made
(`_font_blob`), every time the book is opened, so a reload works as an import does.
It degrades where it is (no banner for the book; the text is set in the reader's
own face, `var(--bookfont,Georgia),serif`): an algorithm Quire has no client for
(`FontCipherOther`), an identifier that makes no key (an Adobe one that is no UUID,
none, over 4096 bytes), a font the archive lacks, noise, and one shorter than the masked
bytes (the browser's decoder refuses it). By research: the OCF specification
gives both algorithms and requires them of a reading system; Readium's streamer
(`FontDecoder`), Calibre (`oeb/polish` font deobfuscation) and foliate-js
(`epub.js` deobfuscators) each undo both the same way, and a resource they cannot
decode is not drawn, not a failure of the book.

**A font encrypted in an unknown algorithm does not make the book DRM** (#410
against #427): `_encrypted_data_unknown` (`src/epub_xml.bats`) passes an
`EncryptedData` whose `CipherReference` is a font file (`.otf`, `.ttf`, `.ttc`,
`.woff`, `.woff2`) even when its algorithm is none of the two, since the text
of such a book reads and only the face cannot be had. Anything else under an
unknown algorithm is refused as before (`e2e/drm.spec.js`), and a namespace of
ADEPT, LCP or Kobo anywhere in the file still is. `e2e/fonts.spec.js` plays
`e2e/font-books.js` (checked by epubcheck, the font `e2e/marker-font.ttf` has one
glyph no system has, U+E000, 1.7 em wide, so the page's face is told by measuring
it; `create-epub.js` has `obfuscatedFonts`, `identifier` and `manifestOnly`, and
`obfuscateFont`, written apart from the app's): masked each way, an identifier with
white space, a reload, no Book chosen, and each degrading case.

### Settled by research, kept failing (#419)

A must test stays failing only where two documented behaviours conflict, and the one
that wins is named:

* **The book's CSS is not applied (#411) wins over the suite's CSS tests**
  (`cnt-svg-css-inclusion` (the svg is drawn; the page's style does not reach it), `nav-spine_in-spine-hidden-toc-css`, `lay-pp-xhtml-icb`,
  `_multi`, `_multi_declarations`, `_repeated-in-meta`, `_units`, the deprecated
  `lay-fxl-*` copies, `css-epub-*` (ten should, vendor-prefixed properties),
  `mol-css`, `ocf-font_obfuscation`): each asks that a rule of the book's own style
  sheet change how its text is drawn. The stylesheet's colours are the app's, each text and
  ground pair proven to reach 4.5:1 in each theme (`SURF`), and the reader's size, margins, spacing,
  Justify, Hyphenation and Font settings are the reader's (accessibility is what a
  reading app is for); a book's colours or sizes would break the proofs and
  the settings. Readium CSS (Thorium) keeps the publisher's styles by default and
  offers a switch to turn them off (its docs: "publisher styles"); Quire is the other way
  round, on purpose. The icb tests' viewport is read and measured (`lay-pp-viewport-*`
  passes); their pass criterion is a grid the book draws, which no reading system of the suite's
  reports answered (0 of 0).
* **The package's language and direction (#416, the book's language on its chapters)
  win over `pkg-lang_but_not_content` and `pkg-dir_but_not_content`**, above.
* **`pub-cmt-jxl`** is the platform's: Chromium and Android's WebView have no
  JPEG XL decoder (Chrome removed its own in 2023), so the image is not drawn. A
  fallback is followed when the manifest names one (`pub-foreign_image`).
* **`pkg-manifest-unlisted-resource`**: see above.
* **Deprecated tests** (`fxl-spine-overrides_duplicate`, `lay-fxl-orientation-landscape`):
  the suite itself files them as deprecated (the `fxl-*` and `lay-fxl-*` copies
  that the `lay-pp-*` tests replace), and `rendition:orientation` is not read.

## SVG is drawn as a picture of its own (#419)

An inline `<svg>` of a page, and an SVG content document, is drawn by
`_render_node` in `src/reader.bats` as an `<img>` whose source is a blob of the
element's own bytes (`images_svg`, `_load_svg`): a copy of the element from its `<svg` to
its closing tag (`_svg_end`, which passes over comments, CDATA sections, processing
instructions and quoted values, so a `</svg>` in one does not end it), with the
`xmlns` and `xmlns:xlink` it was given by its page written in when it names none. Its
children are still made, so every content node keeps its number (search, read aloud and
the overlays count the same tree), but an `<img>` shows none of them. An svg that holds
an `<image>` (a cover page's usual form, drawn by the existing `<image>` path) or is over 512 KiB, or one inside
another, is not drawn this way.

By research, why a picture and not the element in the page, which is what other readers
do: Readium's navigators (Thorium, Readium Mobile), Apple Books, Kobo, Calibre's viewer and
foliate-js each show a content document in a frame or view of its own, so an svg's `<style>`,
ids and links are scoped to that document. Quire's page is one DOM shared with its own
interface and every chapter, with no frame, so a `<style>` in an svg would be a global rule
that could restyle the interface (the proofs of `style.bats` and quire#411 are about exactly that),
an id could collide with the app's, and a script-capable element is something a book may
never put there. A sandboxed image has the same drawing, its own style scope and no
script or outside load (a browser's rule for an svg used as an image), and no care about ids.
What it costs: the book's page CSS does not reach it (`cnt-svg-css-inclusion`, kept
failing by #411 above), its links and scripts do nothing, it uses system fonts, not the
book's, and a dark theme does not recolour its black text (an image is not themed; the
image dimming setting applies to it). Its text is kept in the page, hidden, so a search hit can
still be counted.

## MathML is the browser's (#419, #408)

A `math` element of a chapter is made element for element in the MathML namespace
(`_math_add`, `_math_attrs` in `src/reader.bats`: dom's `add_math_element` and
`set_math_attr`, which write bridge's `math:` tag, `createElementNS`), so the browser sets the
equation and its accessibility tree has the MathML (no `role`, no text copy), the
one rendering both #419's `cnt-mathml-support` and #408 need. The elements are
MathML Core's presentation ones; `maction` and `annotation-xml` (they can carry behaviour
or foreign content) are refused, as are any colour or background attribute (the page's colours are the
theme's: the text's own colour, so each equation reaches the contrast the proofs hold for text) and any link or handler. A
refused element makes none and its children go to its parent; elements and texts take
their content-node numbers as everywhere, so search and read aloud count the same tree.
A token's (`mi`, `mn`, `mo`, `ms`, `mtext`) text is its own; text anywhere else in a math element is not shown. A
display equation wider than the column scrolls along it (`math[display=block]`).
By research: every reader that shows a content document in a browser engine (Thorium,
Readium Mobile on Android, Calibre's viewer, Foliate) leaves MathML to the engine, and Chromium
has set MathML Core since 109; Apple Books' WebKit too. Where an engine has no math font the text falls back.

What #408's tests (`e2e/math-native.spec.js`, `math-fallbacks.spec.js`, `math-layout.spec.js`,
books in `e2e/math-books.js`, each checked by epubcheck) hold, and what they found:

* **A display equation scrolls along its width only.** `math[display=block]` was `overflow: auto`
  on both axes, and Chromium counts a glyph's font box (ascent and descent) in the scrollable
  overflow, a few pixels beyond the equation's own box, so a display equation had a vertical
  scroll of 4px. It is `overflow: auto hidden` with .3em above and below, so what the font
  box adds is room inside the equation's box and a page boundary neither splits nor clips it.
* **`dir` is the page's own attribute** (`_math_attrs`): dom's allow-list of MathML attributes
  has none, MathML Core takes `dir` on any math element, so it is set as an HTML `dir` is
  (`$D.Dir`): an equation is set left to right even in a Hebrew book (`math` has `direction:
  ltr`) unless it says `dir="rtl"`.
* **`alttext` and `altimg` are not shown when MathML is drawn**, by research: EPUB 3.3 and the
  MathML specification make them the fallback for a system that cannot draw the math (the
  W3C EPUB group's thread on MathML: "fallback images via the altimg attribute" for the many
  readers that cannot render it; the DAISY knowledge base: support "depends heavily on the age
  of the reading system", fallbacks for the old ones); no reading system researched shows the
  fallback beside a drawn equation, and none documents that it should. The engine draws MathML
  Core, so the picture would show every equation twice, and the text is the equation's name
  for assistive technology, which the browser exposes. `altimg` is not an allowed attribute
  of dom's, so no image is ever made of it.
* **Unsupported and broken MathML degrades where it stands.** An element dom does not make
  (`maction`, `annotation-xml`, `mstack`, `mglyph`, ...) makes none and its children go to its
  parent; a token's text stays. A broken tree (a fraction of one child, an unknown element) is
  drawn by the browser as it can: the words around it are not lost. (The broken book is not
  valid MathML, so epubcheck refuses it by `RSC-005`, which its entry lists.)
* **Accessibility.** Chromium's tree has a `MathMLMath` node for each `math`, and
  `MathMLFraction`, `MathMLIdentifier`... for its parts (the name CDP gives the role ARIA calls
  `math`); Quire sets no `role`, `aria-hidden` or `aria-label` on MathML.

## Equations as pictures (#408)

A picture of an equation (a PNG, an inline `<svg>`, an `<img src="x.svg">`) is a picture of
text. Two decisions, by research (also in the issue):

* **A picture grows with the reader's text size.** Quire drops the book's CSS (#411), so the
  `em` heights publishers give such pictures are not there, and a picture was always its own
  pixels. Amazon's guidelines say inline images "should be sized in em units so that they scale
  in relation to the text around them when users adjust the font size" (quoted by Jutoh's
  manual; a block picture is sized in px or % there), Readium CSS has no setting that scales
  pictures (its `invert`, `darken` and `blend` flags only recolour), and a MobileRead report
  has em-height pictures overlapping text in Readium. So a picture is its own size at the
  default text size (18px) and is scaled by the reader's size from there (`--image-zoom`, in
  thousandths, written by `_apply_type` in `src/settings.bats`; CSS `zoom` in `.caf:not(.fixed)
  img`, a fixed page being fitted by its own box), kept to the column's width and the page's
  height as before (the height is divided by the zoom, which multiplies lengths). It is the
  same for any picture, not only equations: Quire cannot tell an equation from a diagram or a
  photograph, and a photograph is kept to the column anyway.
* **Black ink on no ground is drawn on paper in the dark themes.** Black on the Dark, Night and
  Grey grounds was 1.1 to 1.8 to one (WCAG asks 3:1 for graphics). Readium CSS (Thorium) offers
  the reader an `invert` flag for night mode that inverts every picture; Quire has no setting
  for it and cannot tell a picture with no ground from one with colours that inversion would
  ruin (a photograph), so a picture is drawn on white in those themes (`tint`, no new colour
  role): a picture with a ground of its own covers it, and black ink has 21:1. The cost is a
  white rectangle behind a transparent picture of white ink, which is rare next to the
  typeset equation, the diagram and the line drawing; the image dimming setting dims it as
  it dims every picture.

## The platform, in Bats

What the browser and the Android app offer beyond the page (reading
aloud, full screen, the rotation lock, the brightness, sharing,
installing, keeping the storage, the local time, files opened with the
app) is quire's own logic, on bridge's typed atoms (each with its
`*_available`, and each JS answer decoded into a datatype that is
matched exhaustively), not pwa's page scripts (bats-lang/pwa#49): no
element carries a `data-pwa-*` marker and no rule keys on a `pwa-*`
class, so pwa's scripts act on nothing of quire's. A control is shown
only where its platform has it, by its own `data-hide`.

* **Reading aloud** (`src/read_aloud.bats`): Read aloud (the bottom
  bar) reads the chapter shown from the first sentence on the page
  (halving the sentences by where each starts against the page:
  `placement`, `Before | OnPage | After`, across as the book reads, down
  when scrolled), Read from here from the sentence the selection starts
  in. A chapter's sentences are its `script` (`src/reader.bats`): the
  text of each block holding no other block (a paragraph, a heading, a
  list item, a quotation, a term, a description, a caption, a cell,
  preformatted text), a ruby's `rt`, `rtc` and `rp` left out but their
  content nodes counted as render makes them (search and render's walk,
  a third time), cut by bridge's `segment_sentences` in the book's
  language; each sentence knows its text and where it is on the page
  (content node and UTF-16 offset at each end). Each is said by
  `speech_speak`, marked with `mark_range` as mark 5
  (`::highlight(bats-mark-5)`, the search hit's proven pair), and when
  the next one starts past the page the page is turned by
  `reader_turn_on` (the next page button's turn, as a promise of
  `turned`: `TurnedPage | TurnedChapter | NotTurned`), into the next
  chapter too, at most 3 turns for one sentence; reading stops where
  nothing turns. The state is one `aloud`: `Silent`, `Loading` (a
  script being made), `Saying` (a sentence, its utterance's number),
  `Turning` (a turn awaited, for a sentence or the chapter's end:
  `turn_for`) or `Paused`; each run is numbered, so what an earlier
  run started is dropped. A pause cancels what is said and says that
  sentence again on resume, when it is still on the page shown (else
  from the page's first): `speechSynthesis.pause()` stops for good on
  Android's Chrome and after some 15 s on desktop Chrome. Read aloud is
  pressed (`aria-pressed`) while it reads, and the screen kept awake
  (`keep_awake`; the reader keeps it awake anyway). The speed
  (`speech_rate`, 0.75 to 2 times) and the voice of each language (by
  the language's primary subtag, the voices whose language has it)
  are kept with the settings, outside the settings record (bytes 20
  and 23 on of "S2", as `ruby` is), so like them they are not saved
  over settings that could not be read (`storage_savable`, #174). They are settings like the others,
  and so are the brightness, the rotation lock and full screen: in the
  backup (`readingSpeed`, `voices`, `brightness`, `rotationLocked`,
  `fullScreen`) and reset
  with the settings, Undo putting them back (`set_reset_undoable`;
  `screen_controls_apply` sets the screen again). Going to the library, opening
  another book, or the page going away (`pagehide`) stops reading.
* **The screen** (`src/screen_controls.bats`, the reading settings'
  Page tab, a row each, quire#300): Full screen (`fullscreen_*`; in the
  app bridge hides both system bars, Capacitor's `SystemBars`, Android's
  immersive mode) and Lock rotation (`orientation_*`, a `rotation` kept
  with the settings and locked again as the app starts) are switches:
  a button named by its label, with a drawn track whose knob moves when
  it is pressed (`_switch_row` in `src/app.bats`), and a line saying
  what it does (`aria-describedby`). In the app full screen is kept
  (quire#313): a `fullscreen_choice` (`FullscreenOff | FullscreenOn`),
  the device's own, after an "F" at the end of the "S2" record, turned
  and kept by the switch (`screen_fullscreen_toggle`) and by nothing
  else, the switch saying it from the first frame
  (`screen_controls_start`). It is the setting for the immersive reading
  screen only (quire#348): the system's bars are hidden when the setting
  is on and the reader is shown with its own bars away (`_immersive`,
  set by quire.bats' `_chrome_set` and `_show_library` through
  `screen_immersive_set`), and shown in the library, in the in-book menu
  and its panels, and as the app starts; the setting is not changed by
  what the bars show, nor by the menu coming up. A browser keeps none:
  the Fullscreen API enters only at a click (the user's activation), so
  a page opened again starts out of it, its switch off, and a click
  there does not change what is kept, and the page is in full screen or
  not as that click left it.
  The rotation lock is the Capacitor plugin's alone in the app (bridge
  never takes the web API there, where Chromium's WebView has none; quire#355).
  `_lock` matches every `lock_outcome` with `case+`: `Locked`;
  `LockRefused(text)`, the plugin's rejection, which removes the row for
  the session and says in the banner what happened and what to do, the
  plugin's error kept as written in the Copy details (`notice_rotation_refused`,
  not a claim that the device cannot lock); `LockUnavailable`, nothing to
  lock with, which removes the row with no banner (availability is also
  decided before the tab is drawn, `screen_controls_show`); and
  `LockUnexpected(code)`, through `notice_unexpected`. A
  control that cannot work is not shown. While the reader is immersive and full screen is on, a page shown hides the
  bars again (`_bars_hidden_again` in `src/reader.bats`), since Android
  brings them back at a swipe from the edge, the reader's own way out of
  immersive mode (quire#314). pwa's activity reports each bar's
  visibility at each window insets dispatch (`batsNative.systemBars`,
  bridge's `listen_system_bars`, `RSystemBars`), which lays the chapter
  out again when it changes (quire#356). Brightness while reading
  (`brightness_*`, the app only, quire#392: a `brightness_choice`, the
  device's own or `BrightnessOwn`, with a level of 10 to 100 kept apart
  as the narration's speed is, `set_brightness_level`; kept with the
  settings, in the one byte of the "S2" record that held the five levels
  of the old select (1 to 5 still read as 10, 25, 50, 75, 100), and set
  again as the app starts) is a slider that changes the screen as it
  moves (`screen_brightness_moved`, on each `input` event, so the reader
  sees the brightness they choose and no percentage is shown), and a
  "Same as device" switch (`screen_brightness_system_toggle`) that gives
  the screen back to the system and, pressed again, to the level the
  slider shows.
  `e2e/controls-shown.js` checks, on every screen the layout spec walks,
  that no control's text is cut (a select's chosen option too) and that
  every toggle looks different on and off.
* **Sharing** (`src/sharing.bats`): the selection, quoted and cited
  ("“…”\n— Author, Title"), by `share_text`; the annotations' Markdown
  file (`annot_export` to `ToShare`) by `share_file` where files can be
  shared (`share_as`: `AsFile | AsText`), else, or when the platform
  refuses it as a file (`FilesNotShareable`), as its text.
* **Installing and keeping the storage** (`src/platform.bats`): Install
  Quire is shown while the browser offers to install the app
  (`install_prompt_available`, `listen_install_prompt`) and asks for it
  (`install_prompt`); the Home Screen hint shows on iOS Safari only
  (`is_ios_browser`, `src/library.bats`). The storage is asked to be
  kept (`storage_persist`) once, after the first book is imported, and
  in a browser a line of Settings, under Backup (`settings-storage`),
  says whether it is (`storage_persisted` at startup); the Android
  app's storage is its own, and there nothing is said (#333).
* **The local time** (`src/local_time.bats`): its offset from UTC
  (`timezone_offset_minutes`) and whether it is night (22:00 to 07:00,
  from `epoch_millis`), for the auto theme (checked each minute while a
  book is open, through the timer, and at each page turn) and the
  reading statistics' local day.
* **Files opened with the app** (`launchQueue`, the share target, the
  Android app's files) arrive on bridge's external-file path, which the
  library imports (`OnExternalFiles`); pwa writes no JS of its own
  (bats-lang/pwa#49), so bridge's service worker keeps a file shared
  with the installed web app, and bridge's `batsNative` entry points
  are what the Android activity calls. They are asked for only once
  the stored library is read (#262): `_external_wait` in
  `src/bin/quire.bats` needs the proof `LIBRARY_READ`, which only
  `_library_read` makes, after `lib_load`, so a book is never added
  to the library the read then replaces; until then the bridge keeps
  the files in their order. When the library could not be read, each
  file is kept (`_handed_kept`, linear) and not added, and the banner
  says so (when Try again is offered, they wait for it: see "A library
  that cannot be read says why").

## The library is stored as records (#354)

The library is not one record any more. Each book is a record,
`library/book/<14 hex digits>` (its id as two 28-bit halves, 7 digits
each), and the collections another, `library/index`. They are read
together by their prefix (`libstore_read`, bridge's `idb_get_prefix`)
and saved one at a time, so a change to one book writes one book's bytes,
and a record damaged in one place costs that record's damaged part and
nothing else.

**The format** is `QREC`, a kind (book, index), the version of the
format that wrote it (1) and the least version that can read it (1, the
reader's `READER`), then chunks as PNG has them: a u32le length under
2 to the 20, a 4-byte tag, the data and a CRC-32 (IEEE, 0xEDB88320, the
check value of "123456789" is 0xCBF43926) as its low 16 bits and then
its high 16 bits, little endian, over the tag and the data; the last
chunk is `IEND`. A record is a set of groups, one chunk each, written
in ascending tag order (a book's: `AUTH BOOK COLL ELSE FNSH ORDR PLCE SERI SHLF
SIZE TIME TITL`, the index's `LEGA NAMS`) and read by tag, in any order
(#510, below); a group the record needs or that every version has
written (`req`, `opt`), when it is lost (absent, its CRC bad or its fields
not parsing), is read with its substitute (`SUBSTITUTES` in
`scripts/record_tables.py`, else 0 and empty) and said to be lost, and the
record is used (`rr_loss`); nothing about a group makes a record unusable.
A chunk of a tag this version does not
know is kept as it is, at the end, when its first letter is lower case
(ancillary, as in PNG), so a newer Quire's addition survives this one's
save; a capital one (critical), or a least version over `READER`, makes
the record `Newer`, and a first four bytes that are not `QREC` make it
`NotQuire`. What a record is decoded to is one of those five outcomes
(`recres`: `rr_ok`, `rr_loss`, `rr_notquire`, `rr_newer`, `rr_damaged`);
a decode never fails to say which.

**Chunks are looked up by tag, in any order, a tag twice is a loss that
is used** (#510). Research (written on the issue): protobuf "parsers must
be able to parse fields in any order" and take the last value of a field
twice; PNG fixes the order only of its critical chunks and lets a
decoder pass over an unknown ancillary one; EBML has no order among the
children of an element, ignores what it does not know and reads an absent
element as its default; CBOR leaves a map with a key twice to the
decoder. So the format is a set of chunks found by their tags, and the
order is the writer's, not the format's.

* `CANON` (`src/schema.bats`) puts the chunks of a record in the order of
  the groups before they are read: for each group in turn, `EXT` takes
  every chunk of its tag out of the list wherever it stands and chooses
  the last whole one (else a damaged one, else none); what is left
  follows, as the chunks a newer Quire added. `SDEC` then reads that
  list as it always did. `canon_functional`, `ext_functional` and
  `lostcat_functional` make the result one, `canon_read` is the run time
  one (`ext_read` per group), and `record_read` is total as before.
* A tag twice is damaged but recoverable, not `Damaged`: the later
  whole chunk wins (a later one whose CRC is bad does not hide an earlier
  whole one: protobuf and CBOR take the last because they have no
  checksum to tell which is whole), the earlier ones are dropped from the
  value and their tag is among the `lost` of `rr_loss`, so the book is a
  `LossyBook`, said once, and the next save writes one chunk of each tag
  and keeps the old bytes under `library/damaged/<id>/<crc>`. `JOIN`
  joins the dropped tags to the groups' own losses (`LOSTCAT`).
* A chunk this version does not know (a lower case first letter) is kept
  whole and in order, twice if it was there twice: it is opaque, and a
  repeat can be the newer writer's list (PNG allows several tEXt chunks),
  so it is not for this version to drop one. They are written after the
  groups. One whose tag is a group's is not kept (`NOTKNOWN`).
* What makes the written chunks read back as they were is a proof the
  writer carries: the tags of the groups are all different
  (`SPECSOK`, from each `SPV_cons`, generated by `scripts/gen-record.py`)
  and the tag of a kept chunk is none of the groups' (`extrasv` carries
  it: `EXV_cons(ANC, NOTKNOWN | ...)`), so `senc_canon` shows that the
  chunks written are their own canonical ones (`tests/static/reject/
  codec-group-twice-earlier-wins`, `codec-group-twice-not-said`).
* **A group the record needs, lost, is substituted (stage 2b).** The
  `LOSES(requirement)` constructors of `SDEC` (`SD_garbled_lost`,
  `SD_bad_lost`, `SD_absent_lost_end`, `_good`, `_bad`) are one set for
  `req` and `opt`, a group absent, with a bad CRC or fields that do not
  parse; `added` keeps its own, for which absent is silent. A book whose
  TITL is lost is "Untitled" (the contents panel's word for a label with
  none), whose AUTH is lost has no author, whose BOOK is lost has ids 0
  in the record and the ids of its key in the library. **The key wins**
  (`_read_book`, `_keyed_book` in `src/libstore.bats`): a record found
  under `library/book/<id>` is the book `<id>` whatever ids it holds, and
  its save writes the key's ids. Such a save (`_repaired`) writes the
  library's image whole, every group, and keeps the bytes the record had
  under `library/damaged/<id>/<crc>`, in the same transaction. Research
  (on #510): SQLite's `.recover` keeps what it cannot place in a
  `lost_and_found` table and calls the result a salvage, and Calibre
  rebuilds a lost `metadata.db` from the book folders, so the record
  is salvaged and the book files stay the source of truth (stage 2c, below,
  reads the title and author from the file again).
  `tests/codec` and `e2e/library-records.spec.js` lose each of AUTH, BOOK
  and TITL, absent and damaged.
* **What a record lost and the book's file can say is read again from
  the file (stage 2c).** As a book is reopened from storage (`Reopen` in
  `_opf_store`, `src/import.bats`), where its OPF is parsed anyway,
  `lib_rebuild` (`src/library.bats`) takes from it what a field holds only
  as a placeholder: the title "Untitled", the author "Unknown", a series
  with no name or no position, no direction of the text, no file size. A
  field holding any other value is never changed (the file is the source
  of what a record lost, not of what it holds), and what the reader made
  (place, shelf, collections, finished, minutes, order, notes) is never
  read from a file. Not rebuilt: the cover, the progress weights (the
  reader works them out as the chapters are laid out), the accessibility
  summary. A rebuild that changes something saves the library at once (the
  record is repaired and the old bytes kept); one that changes nothing
  writes nothing. `e2e/old-library.spec.js` removes a real book's title
  and author groups and opens it.
* **The version before (stage 2d).** `library/previous/<id>` holds a
  book's record as it was before a save, and `library/stamp/<id>` when
  the record was last written (4 bytes, seconds since 2025; read once at
  the library's load into memory, `_stamps` in `src/libstore.bats`). A
  save keeps the record it replaces as the previous version only when
  that record was last written 60 seconds ago or more (an unknown stamp
  counts as old) and decodes whole, and writes the stamp on every save,
  in one batch with the record: KOReader's rule (its `.old` is not
  rotated until 60 seconds old, so a crash loop cannot overwrite the good
  copy with a bad one), on the age of the file replaced, so saves a few
  seconds apart never rotate and a bug that damages a record at each save
  leaves the version from before the first. A book whose record is broken
  beyond recovery (`UnusableDamaged`, the framing) and that has a
  previous version is read from it (`_recover`, a `LossyBook`); the save
  of a book whose stored record is not whole writes the library's image
  as a new record and keeps the bytes under `library/damaged` (it used to
  be refused; `NotQuire` and `Newer` still are). Emptying the Trash
  deletes the record, its previous version and its stamp together. The
  stamp is a key of its own, not a group: a group would be a field of
  every image and record, and it is the library's bookkeeping, not the
  book's. Not done: salvaging the chunks before a cut in a record's
  framing, and offering the sync file or Auto Backup copy for a record
  whose reader state is lost (a notice action: #507's).
* By the principle for any record that does not decode cleanly (the user's
  rule for #510): recover fanatically; if a bug in Quire damages a record
  the reader must still read the book. In order: (1) usable with
  defaults or substitutes (a lost or absent group, a tag twice, a bad
  CRC, and, from the next stage, a lost required group); (2) said, once,
  in the notice (#507: Copy details with the record's id and what was
  lost); (3) the old bytes kept under `library/damaged/<id>/<crc>` when a
  save repairs it; (4) `Unusable` only for what cannot be read as a
  record at all (`NotQuire`) or is a newer Quire's (`Newer`, not
  damaged). A bug that leaves a record unusable is fixed by widening the
  recovery, not by setting the record aside.
* Tests: `tests/codec` (the chunks in the opposite order, a group twice
  either way), `e2e/library-records.spec.js` (every rotation, the
  reverse and seeded shuffles open as the same book and are not written
  by opening; a group twice; an unknown chunk twice).

**A group added later is not loss when it is absent** (#497).
A group is one of three modes in `scripts/record_tables.py`: `req`
(the record needs it), `opt` (every version of the format has written
it: absent is damage, present and damaged is loss, the defaults), and
`added` (added to the format after records were written: absent is
nothing, the record reads whole and the group has its defaults; present
and damaged is loss as for `opt`). `prog`, `snum` and `tdir` are `added`,
and every group added from now on is. Before this an absent group of
either mode was `Damaged`, so a Quire that added a group made every
record written before it unreadable: the book was shown nowhere, the
banner said it could not be read, and Settings offered to set it aside
(which would have moved it out of the library). By research: a PNG
decoder must not require an ancillary chunk, protobuf reads an absent
field as its default, and SQLite's `ADD COLUMN ... DEFAULT` leaves old
rows unrewritten and valid; none counts a record written before the
addition as damaged. The format version cannot tell them apart (the
records in the wild are all version 1, with any prefix of the groups),
so it is the group's own mode. A chunk cleanly cut out of a record is
the same as one that was never there, as in PNG. The decoded record
says which groups were absent (`rx_mk(format, least, vals, extras,
absent)`, `vals` holding the group's defaults), reading is a proof
about it and writing an absent group writes nothing, with the proof
that the next chunk is not the group's (`SENC_absent_*`, `TAGDIFF`), so
`decodes_encodes` and `encodes_decodes` hold byte for byte for a record
with and without the group. The app only ever writes records with every
group (`record_write` has `ab_nil()`), so the first save of an old
record writes the groups it lacked; opening writes nothing and keeps no
copy (`e2e/library-records.spec.js`, "written before ... existed").

**The rule cannot be forgotten, and every table that shipped opens**
(#515). A group of a record is added only as `added`, never `req` or
`opt` (those are the first table's twelve groups and the index's two),
and a group added is named in `RELEASES` in `scripts/record_tables.py`
with its commit. `tests/static/groups.py` (in `tests/static/run.sh`'s
`checkers`) fails a group of the other modes after the first table, a
group not in `RELEASES`, and a change that does not add the library of
the table before it: `e2e/old-library.spec.js` has one library for each
table that shipped (`SHAPES`: the first table, then each prefix of
`RELEASES`; the real build's library cut of the groups a build before it
did not write, which is byte for byte what that build wrote, since a
chunk's CRC covers its own tag and data), and each opens with every
book, nothing said, nothing to set aside, no record changed or copied on
open, and a save writes the current groups. The QLB1 to QLB6 formats of
the old whole-library record are in `e2e/library-records.spec.js`. The
Settings row "Set aside unreadable records" is absent for every record
that reads (even with loss), in each of those specs.
The flake of the set aside spec (#515) was the specs', not the app's:
on the android project the app syncs as it opens (Auto Backup's file is
merged), and the records it writes (`library/index`, and the books'
`ORDR` renumbered by the save after a merge once a record is missing)
land when that sync ends, not when the books show, so they landed over a
spec's change to the store or after the snapshot it compared with.
`syncEnded` / `reloadSettled` (`e2e/legacy-library.js`) take
"sync-state" away before a reload and wait for the sync's end to write
it (`_end`, after the saves), so a spec changes and snapshots the store
only when the app has stopped writing it.

**The codec is proven** (`src/bytes.bats`, `crc.bats`, `chunk.bats`,
`seq.bats`, `fields.bats`, `schema.bats`, `record.bats`; the book's and
the index's tables are in `scripts/record_tables.py` and
`bookrec.bats`, `indexrec.bats`, `bookimage.bats`, `indeximage.bats` are
generated from them by `scripts/gen-record.py` and `scripts/gen-image.py`,
so a field is added in one place). Byte strings are a datasort
(`bytes`) in the types, `blist(bs, n)` linear lists indexed by them, so a
proof can say what the bytes are. Reading is a relation between bytes
and its result (`DECODES(sp, kind, bs, res)`, built of `CK`, `SEQ`,
`FIN`, `SDEC`), writing another (`ENCODES(sp, kind, x, bs)`, built of
`CKENC`, `CHAINS`, `SENC`), and the laws are lemmas the compiler checks,
so a codec that is not the inverse of itself does not type-check:

* `encodes_decodes`: what is encoded decodes to what was encoded, as
  exactly that record (no padding is accepted, no kept chunk is lost:
  `tests/static/reject/codec-drops-unknown-chunk`);
* `decodes_functional`: bytes decode to one result;
* a record read and saved is never changed in meaning: whatever the
  chunks' order or repeats were, `record_write` of the very values a
  read gave (`vals`, `extras`) is `ENCODES` of the same record, and
  `encodes_decodes` makes that decode to `rr_ok` of it, so
  decode(encode(decode(x))) = decode(x) on the value. The first law of
  an earlier version, `decodes_encodes` (the bytes decode to x, so
  encoding x gives the same bytes), no longer holds and is gone: out of
  order bytes decode to x and are written in ascending order (#510,
  below);
* `record_read` is total: it answers every list of bytes with a result
  and its `DECODES` proof, and `record_write` returns the `ENCODES`
  proof of the bytes it made. The CRC's tables are `CRCP`, a relation
  checked by the same compiler, and the stored sum is compared with it
  before a chunk is `ok` (`CKD_ok` cannot be built from a sum that
  differs).

**The round trip is proved, from the value to the bytes and back.**

* A stored book is a `book_image(x)`, indexed by the book `x` it holds
  (`bookx_mk(author, id_high, ..., title)`): each number is an
  `int32v(n)` (its four bytes and the proof `LES` that they are the
  number `n`), each string a `bstr(bs)`, an array of array's `barr` whose
  cells are proved to hold the bytes `bs` (`HOLDS`, by induction on the
  list over array's own lemmas about `NTH` and `SETC`). `int32_make`
  gives the number `n = x` of an int `x`, or says it is not one of 32 bits.
* `book_record_new` makes a `bookrecord(x, 1, 1, ex_nil())` of an
  image, `book_record_image` an image of the very `x` of a record,
  `book_of_image` and `book_image_of` keep it; the lemma
  `book_roundtrip` (generated with the records: `index_roundtrip` too)
  proves that bytes written from `x` and read back as a book `y` make
  `x = y`, and `book_enc_dec` that they are read back as a book at all.
  `book_image_roundtrip` is the whole of it as a function: an image
  written as a record and read back from the bytes is an image of the
  same book, and the compiler accepts it only by those lemmas
  (`tests/static/reject/image-roundtrip-another-book`). Without the
  lemma it does not type-check.
* The bytes of a record reach an array through `blist_to_buffer`, which
  fills a `barr` whose cells it proves hold the list. What is outside the
  proof is only what is outside quire: bridge's atoms that write an array
  to IndexedDB and fill one from it (JS), the array package's memory
  primitives (`barr_get`, `barr_set`, ..., the one unsafe core), arith's C
  operators (`and_proved`, `or_proved`, and `xor_g1` from them) and the
  prelude's `/`. Each is tested where it lives (array's
  `tests/dynamic/content`, arith's `tests/dynamic/xor`). The copy of
  a library `Book`'s fields into an image and back (`_image_of_book`,
  `_book_of_image` in `src/library.bats`) is a copy of its numbers and
  strings by `book_image_make`, which refuses a number that is not 32 bits.
  `tests/codec` runs the whole on bytes and numbers at the edge (damage to
  every byte, every prefix, fuzz) as a check of those boundaries, not as the
  proof.

**The solver is 32-bit**: a constant or a coefficient of 2 to the 30 or
more in a hypothesis makes the context contradictory, and anything is
then proved. No proof here has one (integers are built from bytes,
`b + 256 * m`, and bounded by 2 to the 28); `tests/static/literals.py`
fails the checkers on a literal of 2 to the 29 or more in `src/`, apart
from a run-time value marked `(* wide *)`.

A context can be contradictory with no large literal at all (#594): a
proof with nested divisions (`h/256 + 256*(l mod 256)`, two deep) made
the solver's elimination overflow, its context contradictory, and the
compiler accepted a false statement (`ROTR(16, h, l, l, h+1)`). It is not
only nested divisions. `tests/static/solver/` (standalone fixtures, run
by `tests/static/solver.py` under any patsopt) holds the cases found with
the `ATS2-Postiats-int-0.4.2` solver (CI built it until it moved to
the infinite-precision build, whose own risk is a proof it cannot answer in
time, not a false one it accepts; the caps of `setup-bats` end that): a context of `h < 65536`,
`q == h / 256`, `r == q + 256*h` proves `1 == 2`; so does a pair of
matched copies of arith's `ROTR1` constructor (`rotr1_functional`,
`shr1_functional` and `add32_functional` proved nothing); a product
passing 2^32 does (`b < 2^20`, `v == 4096*b`). The infinite-precision
build rejects all of them. The rules for a proof's arithmetic, which keep
true under either (a proof that only the infinite-precision solver can answer
in time is split, as `date_text` and `add32_functional` were):

* **Keep the magnitudes down, and name the digits.** A statement is made
  of steps that divide (or take `mod`) by a constant of at most 16 at a
  time and numbers built a digit at a time (`b + 256 * m`, as `LE` and
  `STEP1` are), never a closed form with nested `/` or `mod`, a product of
  two variables, or two equations over the same variables with scales
  (1024 and 64 in sha256 stage D). Digit form helps and is not a
  guarantee: the guard is that no bound times a coefficient reaches 2^31
  after elimination, and that is only known by the next rule.
  `tests/static/proofs_audit.py` lists the places that are not (report
  only, a human reads each).
* **A false variant of every lemma.** Each lemma (`prfun`, `prfn`, a
  `primplement` of a `#pub prfun`) has its false variant rejected:
  `tests/static/mutation_check.py` makes them (a numeric index plus one, a
  guard's `==` shifted by one, a bound tightened by one, a byte string
  consed with a byte, an argument of another sort replaced by a fresh
  variable, each part of a tuple result, and `[1 == 2] void` in place of a
  guard) with the lemma's own body, and the compiler must reject each
  (`--root DIR --run WORK file.bats` for another package, `--ats-home DIR`
  for another patsopt, `--inplace` for a recursive `#pub` lemma, whose
  declaration and primplement are changed where they stand and whose
  dependents are checked again: minutes a mutant). An accepted mutant is a
  vacuous proof (or a mutation that is true: `tests/static/mutation_known.txt`),
  and is filed as its own p2 issue with the minimal case. A lemma no
  operator reaches (a `FALSEP`, `EQFD` result) gets its false variant as a
  fixture in `tests/static/solver/reject/`, with its true statement in
  `accept/`. The checker is itself tested (`tests/static/mutation_test.py`,
  a step of the `checkers` member: a stand-in compiler that accepts the
  mutants of a vacuous lemma and rejects those of an honest one, the
  operators, the in-place edit, the choice by a diff). The solver
  fixtures run as the `solver` member (122 files, 38 s under the
  infinite-precision build, all as they should be; the -int build accepts 5
  of the false ones).

* **No `[a | prop]` as the result of a `prfn`.** The issue found that such
  a return silently dropped the proposition; the guards `[p; q] void`
  and `[p && q] void` of crc and arith were all checked by mutants and are
  not dropped, so the rule is kept for the existential with a variable
  only: return a dataprop (an `EQI`, a `LEN`), or state it with a `prfun`.

### The mutation check in CI (#594)

Measured under the GMP solver on a shared 4-core machine, a whole module is
8 to 30 minutes, `src/crc.bats` about an hour. The nine proof modules
(`tests/static/mutation_modules.txt`: bytes, chunk, crc, fields, seq, schema,
record, bookrec, indexrec; about 480 mutants over 220 lemmas) are some three
hours of mutants in all. That cannot be in the required `check` of every
pull request, and it cannot be a few big jobs either: the first version
(four groups, one job each, #611's merge queue run 38703942820) took 42, 48,
71 and 15 minutes for its groups beside a plain group of about 33, and the
merge queue's 60 minute window removed the entry while the group was still
passing. A job's time is the app's check (about 11 minutes cold, the queue's
run is cold) plus its mutants, so the design target is **no mutation job
over about 25 minutes on an idle pool**, and a job costs 11 minutes before
it mutates anything: halving a module's mutants halves only the second part.
From the four measured groups the rate is about 0.43 minutes a mutant for
crc, 0.22 for bytes, fields and seq, 0.25 for schema and chunk and 0.1 for
the small record modules, so a job holds 14 minutes of mutants:

* **Members are parts of a module** (`mutation/crc-part2of5`, `mutation/seq`;
  the parts are in `tests/static/mutation_modules.txt`, which
  `scripts/ci-groups.py` and `run.sh` read): `mutation_check.py --shard I/N`
  takes the I-th of N parts of the lemmas otherwise selected, balanced by
  their number of mutants (heaviest first to the lightest part, so the parts
  are disjoint, together every lemma, and the same on every machine;
  `partition`, unit-tested). Expected minutes per job (11 for the app, plus
  mutants at the rates above): crc 5 parts of 28 mutants, 23; bytes 2 parts
  of 44, 21 each, with seq (21 mutants) 26 and with bookrec and indexrec (18)
  23; schema 2 parts of 50, 24 each; chunk 50, 24; fields and record
  (49 mutants), 20. Eleven groups, each one job, side by side. A pull
  request's incremental check restores the app's build, so its jobs are
  shorter by most of the 11.
* **A pull request selects by its diff** (`check.yml`: the groups
  `mutation-*`; `scripts/ci-groups.py affected <group> <base>` says whether
  the change since the pull request's base, `HEAD^1` of the merge checkout,
  leaves anything for the group, and a job that has none ends after its first
  step: a pull request that touches no proof costs 15 seconds a group, no
  compiler, no cache). If so `QUIRE_MUTATION_BASE` makes `run.sh` pass
  `--diff` to the checker, which mutates only the lemmas the diff touches
  (`select_by_diff`), those that mention a name a changed line declares (a
  lemma whose statement changed, a dataprop), and every lemma of a module
  whose diff is outside all its lemmas; a comment or blank line selects
  nothing; the shard is then of the selected lemmas. A push to main and a
  dispatch run none of it.
* **What selects what.** A change to a proof module selects as above. **A
  change to the solver, its pin (`setup-bats/action.yml`) or its fixtures
  (`tests/static/solver/`, `solver.py`), selects everything**, sharded so
  each job fits. **A change to the checker alone** (`mutation_check.py`,
  `mutation_test.py`, `mutation_modules.txt`, `mutation_known.txt`,
  `proofs_audit.py`) **selects a smoke set**, the modules marked `smoke` in
  `mutation_modules.txt` (bookrec and indexrec, 9 mutants each, 5 to 10
  minutes beside the app's check), run whole: it shows the checker still
  runs end to end on the real compiler, and the checker's own unit test
  (`mutation_test.py`, in `checkers`) tests what it decides. Running every
  module on the checker's change put #611, which changes no proof, through
  three hours of jobs and out of the queue; its judgement on the proofs is
  the nightly's. Groups, workflows and CLAUDE.md select nothing.
* **Nightly, in full** (`.github/workflows/mutation.yml`, 02:41 UTC and on
  dispatch, the same groups side by side on main, built from nothing, an
  issue opened when one fails): it has what a diff cannot see (a locked
  package whose lemmas a proof calls, a compiler move, a bug of the
  selection) and every change of the checker. A vacuous lemma that gets in
  through a relock is found within a day, on main, and is not a red main
  (the proofs still check).
* **Why this shape, by research.** Stryker's incremental mode stores the
  previous run and reruns only the mutants whose code or tests changed, and
  says itself that only mutated and test files are tracked, not dependencies;
  PIT's incremental analysis keeps a history, reruns what changed, and says
  that the assumption that a dependency change rarely changes a mutation's
  status is "currently unproven"; cargo-mutants' `--in-diff` mutates only
  what overlaps the diff of the branch against the pull request's base, and
  says it is "not a substitute for a full test run" (an edit in one region
  can leave another poorly tested). All three give diff-based feedback and
  leave the full run to a schedule. A schedule alone would let a vacuous
  lemma merge and be found the next morning; a full run per pull request
  would put hours beside a 15 minute check. The dependency set here is
  small and textual (a lemma calls another by name), which is why the name
  rule can stand in for PIT's dependency analysis. (Sources:
  stryker-mutator.io/docs/stryker-js/incremental,
  pitest.org/quickstart/incremental_analysis, mutants.rs/in-diff.html.
  mutmut and Dextool were not read.)
* The job has `timeout-minutes` 120 (the nightly's 150) as a backstop, with
  the patsopt caps (`BATS_PATSOPT_TIMEOUT_S`, `BATS_PATSOPT_MEM_MB`, from
  `setup-bats`) under it, so a runaway proof fails with its module named.

**The only way to change a record** is `libstore_save_book` and
`libstore_save_index` (`idb_update`, bridge: one transaction in which a
key is read, the closure decides from what it read, and the answer is
written back, kept as it was or deleted). The closure reads the stored
record, decodes it, puts the groups of the image that changed into it
(`book_record_patch`: the other groups, and the chunks it does not
know, stay as they were), writes it, and answers `BookSaved`,
`BookRefused` (undecodable: `Newer`, `NotQuire`, `Damaged`; nothing is
written) or `BookNotSaved`. A record that lost a group is repaired, and
its old bytes are kept in the same transaction under
`library/damaged/<id>/<crc>`. Nothing else writes `library/` keys
(`tests/static/keys.py` fails the checkers on a `"library/` key named
outside `src/libstore.bats`).

**What the library keeps in memory** (`src/library.bats`): the books and
collections, and a shadow of each record (`shadows`, `index_shadow`): the
image of what was last sent. `lib_save` makes the image of each book,
compares it with its shadow by group (`book_image_diff`) and sends the
groups that differ, none when it does not. A shadow is set when its
groups are sent, not when they are kept, so a change sent and changed
back before the first is kept is still sent; a save that is refused or
fails puts the shadow back (`_shadow_unsend`) and says so once. A book
whose record is no longer in the library has its record deleted; a stale
tab sends only its own groups, so two tabs changing different parts of a
book (a shelf, a collection) keep both changes (`e2e/library-records.spec.js`).

**The order and the view.** A book's record holds its place in the
library's order (`ORDR`, the `position` it had when last saved), and the
books are read back in it, so a book touched last is first again. The
view kept for a reload ("view") names its book by id (the key is only
the number the book was given as the library was read, and records are
read in id order): `lib_index_of_id`; a view kept before, of a key
alone, is found by the key.

**The old record** `"lib"` (QLB1 to QLB6) is converted once, by
`_convert_legacy`: when no record of the library is there, "lib" is read,
shown, and written as the records of its books and the collections'
(with the size and the byte sum of "lib", `LEGA`) in one transaction,
all or none (`batch_commit`, bridge's `idb_write_all`, the index in it
too); until it commits nothing is saved. "lib" itself is never changed or
deleted, so an older Quire still finds it; a "lib" that is not a QLB1 to
6 record is a library that could not be read.

## How far through the book: by the text's size, to the text's end (#426)

`_progress` (the library card and Book info) counted every spine item the
same, so a book of 3 long chapters and 10 short notes read 23% at the end
of its text, and a cover, a title page and a copyright page started a
book at 20%; the reader's footer and scrubber already weighed chapters by
size (`book_weights`). They are one rule now, written down here first, by
research:

* **By size, not by spine item.** Readium's positions are a resource's
  size in 1024-byte steps (the W3C EPUB working group's thread on page
  lists: Adobe since 2007, Readium-based apps since; some systems divide
  the zip entry's size, as `book_weights` does), and Kobo's percentage
  follows the book's words or size, not its pages (MobileRead users on
  the same book as an EPUB and a KEPUB, where 160 of 405 pages and 812 of
  2607 differ). Kindle's is a location, which is also size. Nothing
  comparable counts spine items, except for a fixed-layout book, where
  every spine item is one page of the same worth and the page indicator
  counts them: `book_weights` gives each chapter 1 when every chapter is a
  fixed page (`book_all_fixed`).
* **The text's end is 100%.** Kindle counts the back matter in the
  percentage, and its readers say what the Mudita forum's reader said
  (64% to 100% on the last page of the text) and keep a bookmark where the
  notes begin; Kindle's own "end of book" is the cure Quire takes. The
  EPUB 3 landmarks' `backmatter` entry (the same nav `toc_start_dest`
  reads `bodymatter` from, `PartEnd` in `src/toc.bats`) names the first
  chapter of the back matter; `toc_build` hands it to
  `book_text_end_set`, and from that chapter on `book_weights` gives
  nothing (before = total, own = 0), so the total is the text's, the
  back matter reads 100%, and the scrubber, the ticks and the time left
  follow. A book with no such landmark counts all of it. `epub:type` inside
  a chapter is not read: that is every chapter opened, for one that is
  not the book's. A `backmatter` landmark at the first chapter is no end.
* **The page's start, but the last page of the text is 100%.** The
  footer has always said where the page starts (a first page is 0%, a
  second "<1%"); the page that holds the text's last line says 100%
  (`_permille`), so the percentage is not 98% on a finished book. The book
  is finished (`done`) when the percentage is 100%, which for a book
  without back matter is the last page, as before, and for one with it is
  the end of the text (`_weighed_stored` >= 1001 in `_record_position`).
* **Stored once, carried with the place.** The library cannot weigh a
  book it has not opened, so the reader keeps the thousandth of the place
  (`progress_weighted`: the thousandth plus one, 0 when never worked out,
  decoded once into a `progress_basis`, `ByChapters | Weighed`, by
  `_progress`) beside the place whenever it saves it. A book not read
  since keeps the old count by chapters until it is. It is the record's
  `prog` group (lower case: ancillary, so a Quire without it keeps it and
  reads the record, as for any unknown chunk; every group before it is
  capital), the backup's and the sync file's `progressWeighted`, slot
  `SLOT_PROGRESS_WEIGHTED` taken whenever the place is (`_take_place`),
  and the 18th number of an orphan record ("QO1"). A file that does not
  have it gives 0, so a place restored or synced from an older Quire is
  counted by chapters until the book is read here.
* The size is the entry's size in the archive, as before: the e2e books
  store their chapters, so it is their bytes. A book whose chapters
  compress very unlike each other weighs them by compressed size; the
  uncompressed size is in the zip's directory and is not carried to the
  chapters yet.

`e2e/progress.spec.js` (books in `e2e/progress-books.js`, checked by
epubcheck) plays each of #426's cases, and backup and sync carrying the
number (`e2e/sync.spec.js`).

## Replace keeps what the reader made (#425)

A book's id is the SHA-256 of its file (`_file_id` in `src/import.bats`),
so the duplicate question (Skip / Replace) is asked only for a file that
is already in the library, byte for byte, and an archived book is put
back by importing it with no question. Replace (`import_mode` `Replace`)
changes the book's file (one `b<id>` entry), size, series and cover (when
the file has one) and nothing else: the place, collections, finished
mark, minutes, annotations and notes, order and id stay, and so does a
hidden book's shelf; only an archived book or one in the Trash comes back
to the Library, as the reader asked for it. `e2e/replace.spec.js` holds
the whole record of the library, the file's size and the card, before and
after, to be the same, and plays a backup, a second device and a second
tab over it. By research (the issue's comment): Apple Books and Kobo make
a corrected file a new book and the notes stay with the old one, which is
what users complain of; so a corrected file of a book in the library is
offered Replace too.

**A corrected file** has another id, so it is not the duplicate question's.
When the OPF of a new file is read (`_opf_done`), its title and author are
compared with the library's (`lib_find_similar`: case and the white space
around them ignored, a title that is empty never matches, a book in the
Trash is not one); a match asks "Newer file of a book?" (`QNewerFile`,
`_ask_newer`): **Replace** or **Add as new book** (also Escape: nothing is
lost either way). Nothing has been stored by then (`BookLooksLike`); after
the answer the OPF is read again as `Replace` (the file, cover and
accessibility data stored under the *book's* id, the id kept) or as
`AddAlone`.

**Chapters are found by name.** The hrefs of a book's chapters (`src/chapter_hrefs.bats`,
the chapters as `_spine_chapters` numbers them, an empty line for one that
names no file) are kept under the key `h<id>`, written when a book is
opened and by every replace. A replace reads the old record, makes a
`chapter_map` with the new file's hrefs (`MapByHref`; `MapByNumber` when
the old file's were not kept, a book not opened since: the same number
when the count is the same) and:

* the place (`_place_moved`): the chapter of its href, at the same page and
  anchor; else the chapter of the same number if there are as many, else
  the first, at its start; the progress weights are counted anew. Nothing
  changes when the hrefs are the same in the same order.
* each note (`annot_reanchor`, `_relocate`): its chapter's new number; one
  whose chapter is not in the new file is kept under `LOST_CHAPTER` + its old
  chapter, which is listed after every chapter under "Not found in this
  version" with its words and note, painted nowhere, leading nowhere,
  exported with that heading. A note's id contains its chapter, so a moved
  note has its old id deleted (a tombstone) and sync passes on a deletion
  and a new note. A note of a chapter that exists but has not the node it
  names is lost the same way when the chapter is shown
  (`annot_chapter_shown`, from the chapter's count of content nodes): the
  nodes of a chapter are known only when it is rendered, and a changed
  word is not noticed (a note is lost when its nodes are gone, not when
  its text changed).

By research for the annotation rule: Kobo keeps an annotation of a
restructured book in the list when it no longer shows in the text; Apple
Books and Kobo lose them when the corrected file is a new book. No
documentation was found of how Thorium or Moon+ match annotations of a
replaced file (searched), so nothing is taken from them.

**Another tab** (`src/file_version.bats`): bridge has no channel between tabs,
so a tab that has a book open asks, when it is shown again
(`visibilitychange`, the moment sync runs; web apps refetch stale data when
a tab regains focus, as TanStack Query does by default with
`refetchOnWindowFocus`), which
file the book is made from: the key `v<id>` holds the file's id when it is
not the book's own (a corrected file; deleted when the book's own file comes
back). If it is not the file the tab opened, the tab goes to the library and
the banner says "This book was replaced with another file in another tab"
with Reopen Quire (`BookReplacedElsewhere`). A tab in a second window
side by side is told when it is shown again, not at once. An identical file
changes nothing, so nothing is said. `e2e/replace-corrected.spec.js` plays
all of it with fixtures that pass epubcheck (`e2e/replace-books.js`).

## A library that cannot be read says why, and offers what fits (#374)

Bridge's IndexedDB read says why it failed: `Unreadable(cause)` carries a
`browser_reason`, the DOMException's name decoded once there
(`Transient` = UnknownError, `StorageBlocked` = SecurityError,
`NewerVersion` = VersionError, `Aborted` = AbortError, `NoErrorGiven`,
`BrowserUnexpected` with the name, a line feed and the message).
`src/unreadable.bats` turns that into a `failure_kind` (flat, copied
freely: `KindTransient`, `KindStorageBlocked`, `KindNewerVersion`,
`KindAborted`, `KindNoReasonGiven`, `KindBytesUnreadable`,
`KindUnexpected`), and the library's read keeps it: `library_content`
(`src/libstore.bats`) matches the lookup itself, where `lookup_content`
folds every cause into `ContentUnreadable`, and `library_read.ReadFailed`
carries a `failure_found` (the kind and, for an unexpected one, the
name and message as text, cut at 4096 bytes, never dropped). No other
read of storage changed: each still folds, as #174 says.

* **Hope is a proof.** `HOPE(failure)` is a dataprop with a constructor
  for `FTransient` alone (the sort `failure` and the witness
  `failure_is(f)` of each kind sit beside the flat `failure_kind`, which
  a cell can hold). The screen's `remedy` is `TryAgain(HOPE(f) | failure_is(f))`
  or `NoRemedy`, made only by `remedy_of`, a total `case+` over the
  kinds, and `ui_try_again_show` needs the `HOPE(f)`: Try again for any
  other kind does not type-check (`tests/static/reject/try-again-without-hope`;
  `accept/try-again-transient` shows the transient one does). `retry_hope`
  (`Hope | NoHope`) is read off `remedy_of`.
* **Aborted has no hope**, by research (the decision is also next to
  `HOPE`): the IndexedDB specification defines only UnknownError as
  transient; AbortError is "a request was aborted", raised when a
  transaction is aborted (by `abort()`, or after a failed request nothing
  handled), and Quire's read never aborts, so something else did and
  nothing says it will not again; Dexie's page on AbortError says only
  that it happens when the transaction was aborted and gives no advice
  to retry, and localForage reconnects and retries once, but on
  InvalidStateError and NotFoundError when a transaction cannot be
  created, not on AbortError.
* **What the screen says** (`library-empty`, `_unreadable_text` in
  `src/library.bats`; every text ends "Quire has not changed anything and
  will not save until it can read your library.", and none says "Import
  an EPUB", which is for an empty library): Transient, "Quire could not
  read your library this time." with Try again (`library-try-again`);
  StorageBlocked, the private window or site data blocked and to allow
  site data for this address, or leave the private window, then reopen
  Quire; NewerVersion, "This device holds data from a newer version of
  Quire. Update Quire."; Aborted, NoReasonGiven and BytesUnreadable, to
  reopen Quire to read it again; Unexpected, an unexpected error with the
  details in the banner. None but Transient has a button. Import is off
  while the library is unreadable (`inert` on `import-file`, and the
  button drawn disabled: muted text on the card, a cursor that says no,
  `#import-button:has(input[inert])` in the stylesheet, a `surf` pair
  proven in each theme; a file handed or dropped is refused with "Books
  cannot be added until Quire can read your library"). Records that can be read but not
  used are another case, below (set aside); a read that failed as a whole
  is not one, since nothing is known of what it holds and a new library
  made beside it could not be seen while the read keeps failing.
* **Records that cannot be used are set aside, not replaced** (the
  follow-up of #374). A library whose read worked can still hold a book's
  record, or the collections', that is not Quire's or whose framing is broken (cut short, a length past
  the end, no end chunk; every other damage is used, #510, and a book with
  a version before it is read from it, 2d) is shown nowhere and not
  written over by a read; the collections' record, and a book's of a newer
  Quire or not Quire's, are never written over, so no collection can be made
  while the collections' is one of them, and a book of those cannot be
  imported again (a book whose framing is broken can: its import writes the
  library's image over the record, the bytes kept, 2d). Settings shows a row then (`settings-aside`,
  `lib_aside_show`: "Set aside unreadable records",
  `settings-set-aside`), and only then. Pressing it
  (`lib_aside_run`, `lib_set_aside`) reads the library again and, for each
  such record, runs `libstore_set_aside_book` / `libstore_set_aside_index`:
  one `idb_update` transaction that reads the record, decides again with
  the codec (`_read_book`, `_read_index`; what was believed before does
  not decide) and, only for `UnusableDamaged` and `UnusableNotQuire`,
  writes the record's bytes to `library/damaged/<id>/<crc>` and deletes
  the record in the one batch (`_aside_writeback`), so an aborted
  transaction leaves the old record byte for byte
  (`e2e/library-records.spec.js`). A newer Quire's record
  (`UnusableNewer`) is never set aside: it is not damaged, an update of
  Quire reads it (`AsideNewer`). Nothing is lost, so it is not a `harm`
  and has no confirmation; the row then says to import those books again
  and restore a backup, which re-applies their places, shelves and notes.
  By research: Firefox renames a corrupt `places.sqlite` to
  `places.sqlite.corrupt` and starts a new one; Mozilla's application-services
  weighed moving the file aside against deleting it and chose deleting only
  because it acts on confirmed corruption; Roon and Miro tell the user to
  keep the old data folder or back the corrupt database up, then start
  fresh. Quire keeps the copy, as they do, and acts on one record at a time
  instead of the whole library, so what reads is never touched.

* **The banner.** A kind the screen says completely has no banner: the
  screen gives what happened, what Quire did, what to do and the
  browser's name for it ("Details: UnknownError."), which is what a
  report needs. Only an unexpected failure raises one
  (`notice_unexpected`: the name and message as the answer, Copy details,
  Report), since it carries what the screen cannot and its screen has no
  button for it to cover. A banner shown first at the foot of the library
  covered Try again on a short phone (CI, mobile-portrait), and one at
  the top covered the header; over the library the banner is now part of
  the page, above the header, and pushes it down (Material 3: a banner
  sits under the top app bar and moves the content; position relative
  with the base rule's centring), so it is over nothing. `coveredByBanner`
  (`e2e/controls-shown.js`, run by `fits`) reports the header's controls,
  `library-empty` and `library-try-again` under the banner, and Try again
  under anything at its centre, whether a banner is up or not; the layout
  spec runs it on an unreadable library of each sort in every project. A
  banner wraps its buttons under its message on a narrow window instead
  of squeezing Report. Over the reader it is fixed at the top while the
  reader's bars are away, and under the top bar while they are up
  (`.banner.under-bars`: the bar's safe inset,
  44px control and 2px, and 8px), as material.io's, Flutter's and
  Zeta's banners sit under the app bar and none draws over it;
  `e2e/storage.spec.js` raises one over the reader with its bars up and
  runs `coveredByBanner` on both bars.
  A modal layer is over the status (#556), as an Android dialog or drawer
  is over its activity's Snackbar, and the library's menus were already
  over the banner (#507): while a library menu is open the Undo toast is
  drawn under its veil, and while a veiled reader panel is open (Contents,
  highlights) the banner is under the scrim; both are still up, and back
  when the layer closes (an Undo offer lasts until dismissed, #364). The
  layer module says it as attributes of the element it places, as it opens
  and closes (`_open_set`, `_modality_show` in `src/layer.bats`:
  `data-menu` on `undo-toast`, `ui_undo_under_menu`, and `data-veil` on
  `error-banner`, `ui_banner_under_veil`; `data-menu` on the banner is the
  same for #507), and the rules are `#undo-toast[data-menu='1']` and
  `#error-banner[data-veil='1']`: the first version of #556 asked
  `#bats-root:has(...)` of both, which `tests/static/has_root.py` (#538)
  rejects, since a `:has()` on the root that holds the chapter is
  re-evaluated over all of it (#423). A
  panel with no veil and the screens leave them where they are (a screen
  offers an Undo of its own). `coveredByBanner` also checks every control
  of an open menu, panel, sheet or dialog, and `toastClear` every control
  under a toast; `e2e/containers.spec.js` (a failed chapter's banner, then
  Contents) and `e2e/back.spec.js` (the Trash's Undo, then the library
  menu) use them instead of dismissing first. The details of an unexpected
  failure outlive its banner: they are kept in memory (`_details` in
  `src/notice.bats`, replaced by the next such failure, never stored)
  and About shows "Copy last error details" (`about-error-copy`, an
  `about_control` of the screen's one listener, since the table of
  listeners is full) once one is kept, as Firefox keeps its
  troubleshooting information on about:support with a Copy text to
  clipboard button. Start-up with a library that could not be read yet
  does not write over the stored view (`_library_shown(false)`): the
  retry opens the book it names, as the sync that waits for the retry
  runs then (`e2e/storage.spec.js`).
* **One honest retry.** Try again repeats the read start-up makes
  (`lib_load`) through `_library_read`, so the `LIBRARY_READ` proof is
  still only made there. `lib_retry_begin` spends the retry when it
  starts, so a second press does nothing and a failure leaves the screen
  with no button for the rest of the session (it says it tried again).
  When the first read fails for a reason with hope, the start-up steps
  that wait for the read (`_after_read`: files handed to the app, sync, the
  stored search and view) are held and run once when the retry ends,
  whichever way (the bridge keeps the files in their order meanwhile); for
  a reason without hope they run at once, as before (the files are kept,
  not added). The flag that stops every save of the library
  (`storage_savable`) is cleared only by `storage_read_again`, given
  `AttemptRead` by a read that worked (`Readable`); `AttemptFailed`
  leaves it (`StillUnread`). A read made again starts from nothing
  failed (`_read_outcome`), the kind it failed with is `_read_kind`, and
  `library_view` is `ViewBooks | ViewEmpty | ViewUnreadable(failure_kind)`
  (fixture `library-view-unmatched`).
* `e2e/storage.spec.js` stubs the library's read to throw a DOMException
  of each name (`failLibrary`), once or always: each kind's text and
  button, an unlisted name's details, Try again showing the books and a
  later import being kept, and a retry that fails.

## Encodings and languages (#436)

**Text documents are read as UTF-8 whatever they are encoded in**
(`src/text_encoding.bats`, tables in `src/text_tables.bats` made by
`scripts/gen-encodings.py`). Every document that is text (the container, the
package, the navigation document, a content document, an overlay,
encryption.xml; not an image, font or audio) goes through `take_text`
(`src/book.bats`) instead of `take_decompressed`: a byte order mark says the
encoding (UTF-8's is dropped, UTF-16 either way becomes UTF-8), so does `<` and
a null byte; else the XML declaration's `encoding` by the WHATWG labels
(`iso-8859-1`, `latin1` and `us-ascii` are windows-1252, as in a browser) for
UTF-8 or a single-byte encoding with a table here (windows-1250 to 1257,
ISO-8859-2, 5, 7, 8, 15, KOI8-R); else UTF-8. UTF-8 that is not UTF-8, or an
encoding with no table (Shift_JIS, GBK) in a document that is not ASCII only,
refuses the document ("Chapter N of this book could not be read", a
`PlanRefused`): XML calls it fatal, and a guess is mojibake. A document that
says a single-byte encoding but is valid UTF-8 with non-ASCII characters is read
as UTF-8 (it is wrong about itself). A plain UTF-8 document is not copied
(`PlanAsIs`). The research is in the issue: Thorium and Apple Books use a
browser's XML parser, Calibre the mark and the declaration and then a guess.
A title, author or series in the package has its references decoded
(`_span_arr`), and the library sorts by letters (`_fold`: Latin letters without
their accents, so Łukasz is under L; other scripts by code point).

**Languages.** Quire does not guess a book's language from its text (no reading
system researched does): no `dc:language` is `und`, with the voice automatic,
Look up in English and the direction the package's; the text is set by the
Unicode bidirectional algorithm. `dc:language` and `xml:lang` are normalised
to BCP 47 by `language_normalize` (`src/language.bats`): `EN-us` and `en_US` are
`en-US`, `eng` is `en`, `heb` and `iw` are `he`, the first of several is the
book's; the page's `lang`, the voice and Look up go by it (primary subtag).
A chapter's own `xml:lang` or `lang` on its html or body (`_chapter_lang`, cleared
as each chapter is shown) is the language in force there, for the page, the
voice and Look up (`_lang_take`). In the text read aloud an element that says a
language other than the one in force, inside a block, is a block of its own
(`_runs_node`, `_block_lang_add`): a sentence of its own, said in its language
(`SentenceOf`'s `book_lang`, `script_lang`). `e2e/encodings.spec.js`,
`e2e/languages.spec.js` and their `*-books.js` test it.
## A book's place in its series is a position in hundredths (#434)

`opf_series` (`src/epub_xml.bats`) reads a book's series and position: the
first `belongs-to-collection` that is a series (one another meta refines as
`collection-type` `set` is not), and the `group-position` that **refines it**
(any, when the collection has no id); else Calibre's `calibre:series` and
`calibre:series_index`. A position is a number with an optional sign, digits
and a `.` or `,` with digits after it, spaces around it ignored (`_number_scan`),
kept to two places (3.125 is 3.12), `-99999.99` to `99999.99`; anything else
("II", "Part Two", "2 5", "1e2", empty) is no position, never a refusal. Calibre
keeps `series_index` as a float, so 0 is a prequel and 2.5 a novella between
volumes 2 and 3: the library sorts a series by the number, 0 and negatives
included, and a book of the series with no number after those that have one,
by title.

`bnums.series_position` is `series_position_of(hundredths)`: 0 for none, else
the hundredths plus 10000001 (as `progress_weighted` is the thousandth plus one),
so the order of the ints is the order of the positions. The card and Book info
(a Series row, `lib_series_line`) show it as written without a trailing zero
(`Foundation · 2.5`, `· 2`, `· 1.25`, `· 0`, `· -1`). A record keeps it in an
ancillary group `snum` (`series_position`), written only when SERI's whole number
does not already say it; SERI keeps the **whole number** (`_series_whole`: 2 for
2.5, 0 for none or below 1), so an older Quire reads 2 and keeps `snum` as it
keeps `prog`, and a record with no `snum` reads as SERI's whole number
(`_series_read`), as the records written before it do (they read whole: a
group that is absent from a record written before it existed is not loss, #497). Neither the backup nor the
sync file holds a book's series (it is the book's own, read from its file, so a
second device or a restore shows what the file says). `e2e/series.spec.js`,
`e2e/series-books.js` and `e2e/library-records.spec.js` test it.

## The sizes a book's CSS gives (#431, stage 1)

`src/css_size.bats` reads a book's `font-size` rules as the format alone
(nothing of it reaches the page yet; stages 2 and 3 of #431 measure a book's
dominant size and apply the proportions). Only `font-size` is read: rules
selected by element names, classes, ids and descendant chains of them
(`sheet_rules_read`, at most 4096 rules, each with its selector's span in the
sheet, specificity and order), an inline `style` and `<font size>`
(`declarations_size_read`, `font_size_attribute_read`), in px, pt, pc, in, cm,
mm, em, ex, rem, % and keywords; `calc()`, `clamp()`, `var()`, `vw`, a
negative size and `!important` are `SizeIgnored` with their reason, and a
selector with a combinator, pseudo, attribute or `*` is skipped and counted.
Every answer is a `datavtype` matched with `case+` (`size_read`,
`selector_read`, `sheet_read`). What the types prove: a size is at most a
thousand pixels or times (`size_declared`), a computed one is a pixel to a
thousand of them (`size_computed`), a proportion to the dominant size is from
10 to 60 twentieths (`proportion`, so `font-size:1px` and `font-size:400%` are
held to half and three times, as Readium clamps), a rule's selector lies inside
its sheet, and its order is below the most. What is tested, not proved
(`tests/css-size/run.sh`, a CI step beside the codec's, on bytes, with a fuzz):
that the grammar read is CSS's. The `rem` trick of the fixtures is on `html`
(`e2e/size-books.js`).

### The size most of a book's text is set in (#431, stage 2)

`src/css_cascade.bats` matches those rules against a chapter's elements
and counts its characters by the size they are set in; `src/publisher_size.bats`
reads a sample of the open book's chapters and keeps the size with the most
characters (`publisher_dominant_size`, thousandths of a pixel, 0 when none).
`_spine_build` runs the measure before the first chapter is shown. Nothing
reaches the page yet (stage 3).

* The cascade (`chapter_tally`): an element's size is its inline `style`, else
  the rule of the highest specificity (the later one at the same), else
  `<font size>` (a presentational hint, below every rule), else its parent's;
  em, % and keywords resolve against the parent, rem against the html
  element's computed size (html itself against the initial 16px). The
  browser's own sizes (h1 at 2em) are not counted, only what the publisher
  declared. A rule's chain of compounds is matched right to left, the nearest
  ancestor first (`_match_up`); an element name is matched exactly, as in XML.
  Text of `head`, `style`, `script`, `title`, `rt` and `rp` is not counted; a
  character is a non-white-space UTF-8 character.
* The tally (`size_tally`) holds at most 64 sizes, each rounded to a quarter
  of a pixel; the dominant size is the one with the most characters, the
  smaller on a tie, 16px when nothing is counted. By research (on the issue):
  Calibre's base font size is the most common font size in the document.
* The sample: at most 16 chapters at an even stride through the spine, 1 MiB of
  decompressed chapters in all, none compressed over 512 KiB (so the open of
  a book of one huge chapter is not made to wait: it is not measured). A
  chapter's `<link rel=stylesheet>` sheets (not alternate, media all or
  screen), read by `book_find_relative`, and its `<style>` texts are joined,
  links first, into one sheet of at most 512 KiB (`sheet_acc`), so one rule
  order serves them; a chapter that links to sheets is read twice (the sheets
  are awaited between). A sheet with an unclosed comment or block takes the
  ones joined after it with it.
* Kept in memory per open, not as a record group: derived from the file by an
  algorithm that will widen, so a stored number would go stale at every change.
* Tested: `tests/css-size/run.sh` natively (`css_cascade_test.bats`: the
  cascade, inheritance, the book A and B fixtures' rules, the tally, a fuzz).
  The wiring (links read stored and deflated, the three size books measured
  16px, 12px and 12px, a plain book 16px) was checked by hand with a
  temporary attribute and is not a permanent e2e: nothing of it is visible
  until stage 3, which tests it by what the page shows.

### A book's sizes reach the page (#431, stage 3)

A reflowed chapter's elements that its publisher gave a size carry a
`data-fs` (`_size_mark` in `src/reader.bats`): the element's size against a
base, in twentieths from 10 to 60 (`proportion`, so half to three times,
as Readium clamps), and the stylesheet `style-sizes` (`src/size_rules.bats`,
a sheet of its own, 51 rules proven to fit its budget, each one a
selector of 19 bytes and a value of 30) gives it
`font-size: calc(var(--reading-size) * step / 20)`, where `--reading-size`
is the Size setting (written by `_apply_type`). The map of a chapter's
elements and steps is made as the chapter is loaded (`_sizes_load` after
`_overlay_load`, in `_chapter_open`: `publisher_sizes_load`, which reads the
chapter and its sheets again, like the measure does) and taken a name at a
time by the render (`publisher_sizes_begin`, `publisher_sizes_step`,
`publisher_sizes_end`: an element is known by where its name is in the
document, and the render asks in the document's order). A fixed-layout
page is not restyled, and a chapter's load that cannot make its map shows
the chapter without sizes.

* **In proportion (the default).** The steps are against the book's
  dominant size (`publisher_dominant_size`), the cascade starting from the
  browser's 16px, so the body text of every book is the Size setting
  and a book's headings, small print, captions, notes and lead
  paragraph keep their proportion to it (a book that sets no size has
  no `data-fs`, and its headings are Quire's own, as before). An element is
  marked when it was given a size or its size differs from the one it is
  shown in (`html` and `body` are not made as elements, so a size they give
  is given to their children: the rem trick's 62.5%).
* **Respect the publisher's sizes** (`publisher_sizes`, `SizesInProportion |
  SizesAsPublished`; the Look tab's switch, `publisher-sizes-switch`; the
  device's own, kept in the "S2" record after "F" as "P" and a byte, in the
  backup as `publisherSizes`, reset with the settings and brought back by their
  Undo). The cascade then starts from the Size setting as the root and the
  steps are against it: the publisher's sizes as a browser would draw them
  with that root, an absolute size absolute (B's 9pt is 12px) and a
  relative one relative (A's 1.6rem is the setting). Because an absolute size is
  against the setting, the map depends on it: the chapter is shown again (at its
  place, `reader_sizes_reload`) when the switch turns, when the Size moves
  while it is on, and when the settings are reset or put back. A step is a
  twentieth of the base, so a size is within 2.5% of the publisher's, and
  one under half or over three times the Size is held there (12px at a
  Size of 32).
* By research (on the issue): Calibre rescales to a base font size
  that is the most common size in the document; KOReader's two switches
  (Embedded Style, Ignore publisher font sizes) are on or off and its
  tracker records that ignoring sizes also drops the engine's heading
  sizes (koreader#13295); Readium CSS keeps relative publisher sizes
  scaled from the user's size and leaves absolute units as they are.
* Tested: `tests/css-size` (the map: A's and B's books, the floor and the
  ceiling, respecting) and `e2e/publisher-sizes.spec.js` (the books of
  `e2e/size-books.js`: the body text at the setting in each at 12, 20
  and 32, the ratios 2, 1.5, 0.8 and 1.25 in both, a size on body, on a div,
  by html and rem and by calc(), a title page of headings, the floor and
  ceiling, only the size read, a linked sheet, and the switch on, kept,
  backed up, reset and undone). `e2e/publisher.spec.js`'s sizes test now expects the
  point size inline to keep its proportion (it expected every size equal while the book's
  sizes were dropped); the `!important` sizes are still not read.

## What allocates is linear

wasm has no garbage collector, so outside `$UNSAFE` nothing that
allocates is non-linear (bats-lang/bats#224): a type whose constructor
carries data is a `datavtype`, consumed by a `case+ ~` match (a list
has a `_free` walk); a closure is a `lincloptr1`, made with `llam`.

Quire never frees a closure itself (`cloptr_free` needs `$UNSAFE`):
each one is handed to a library that runs it once and frees it, a
promise (`$P.finish`, `$P.and_then`) or the bridge (a listener of the
`regs` table, `ui_listen_all`). What waits for a later answer keeps a
promise's resolver, not a closure: the Undo offer (`undo_offer`
returns the promise of how it `settled`: `Undone` or `Final`), the
dialog (`modal_open` and `modal_confirm` return the promise of its
`reply`: `Accepted` or `Declined`), a sync's round (`_rounds` in
`src/sync.bats`). The caller hands its continuation to that promise,
and the cell resolves it exactly once, so what would not have run
before (an undo made final, a dialog's other button) still runs,
told so by the value, and is freed. A function that called a closure
for each item takes data that says what to do instead (`lib_nums_set`,
`counted` in `src/annot.bats`, `regroup` in `src/library.bats`).

A promise's payload type implements `$P.dispose`, before its first use
in each module that makes a promise of it (`$P.create`, `$P.ret`,
`$P.resolved`): `bats check` does not catch a missing one, only the C
compile of `bats build` does.

## A choice is a datatype

An int never encodes one of a fixed set of cases (bats-lang/quire#192):
a choice is a datatype matched with `case+`, so a case left out does
not type-check ("pattern match is nonexhaustive"), and "none" is an
option, not -1. Ints are quantities, offsets and indexes. Stored bytes
stay as they are, decoded once as they are read and encoded once as
they are written: a book's `shelf` (`shelf_of_code`, `shelf_code`) and
cover (`image_of_code`, `image_code`), and the library view's
`sort_order`, `layout` and `book_filter` (`lib_state_set`,
`lib_state_get`, which packs them only to be saved with the settings),
and each setting of the "S2" record and the backup (`font`, `alignment`,
`hyphenation`, `image_dimming`, `tap_zones`, `volume_keys`, `readout`,
`page_flow`, `column_count`, `ruby_display`, each with its `_code` and
`_of_code`). The theme chosen is a `theme_choice`, `Auto` or
`Fixed(theme)`, kept apart from the settings record since it is linear;
a `theme` (style's `palette_theme(n)`) is indexed by its number in the
palette, `theme_palette` the one function that gives it, and the theme
rules are written from it (their selectors too), so a theme's colours
and its proofs cannot be another's.
How a sync ended is a `sync_result`, stored as its code in
"sync-state" (`_result_code`, `_result_of_code`); the store's kind a
`store_kind` (`WebDavKind`, `AndroidKind`, `BackupKind`, `DropboxKind`,
`NoStoreKind`);
and an HTTP status is read once into an `http_answer`.
An annotation's kind (`Bookmark`, or a highlight in its
`highlight_style`) is stored as its code in the "QA" record
(`_kind_code`, `_kind_of_code`), the record's version is a
`record_version`, a highlight's mark set a `mark_set`, and the list's
filter a `style_filter`. A kind is one flat datatype, not `Highlight of
highlight_style`: a constructor that carries data would make it linear,
and an annotation's numbers are copied freely.
Opening an archive is done in an `import_mode` (`Reopen`, `AddNew`,
`Replace`) and ends in an `archive_outcome`; an import's promise
resolves with an `import_outcome` (`Added(key)`, `Kept`, `Failed`), the
duplicate question with a `duplicate_answer`, and a chapter's load with
a `load_outcome` (`ChapterShown` or why not, `load_shown`).
A link found on the page is a `link_found` (`NoLink`, `InBook`,
`OutOfBook`); a spine's direction a `spine_progression`; a book's
accessibility metadata an `a11y_feature` each (its bit in the stored
flags made by `a11y_bit` alone, asked by `a11y_has`) and a
`wcag_level`; an OPDS list of links a `link_list`; the catalogue's
fields `entry_field` and `page_field`, and a refused fetch a `refusal`.
A click's target is decoded once, in `src/ui.bats`, into its listener's
own control datatype (`typography_control`, `selection_control`, ...),
each control's id given by its `*_control_id` (which
`tests/static/ids.py` reads: each must be made, none twice), and each
listener matches it with `case+`; a key event is decoded once into a
`key` and its `modifiers` (`ui_key`, `ui_modifiers`).
A dictionary's form (`dict_form`, a record: a .dict.dz, a .syn) is
its byte in "dicts" (`_form_code`, `_form_of_code`); a file to import is
a `dictionary_file`; a lookup finds a `word_match` (`Exact`,
`CaseFolded`, `NotFound`) by stardict's `word_order` (`Before`, `Same`,
`After`); an article's part is a `part_kind`.
`tests/static/case_plus.py` fails on any plain `case` (ATS2 checks only
`case+`), in CI through `tests/static/run.sh`.

## Backup: Export says it saved, Restore says what it did and can be undone (#362)

A restore overwrites, from the file, the settings (the device's own too:
brightness, rotation lock, full screen, voices, sort order), the books it
has in the library (shelf, place when the file's is later, collections,
finished, minutes), the notes of each book it names (the book's stored
array is replaced, deletions dropped), the reading log's missing days,
and the collections it names (made when missing); a book the library
does not have keeps its record as an orphan ("o"). Nothing went to the
Trash, so the Undo rule was not met: nothing was offered back.

Now what is in the library is kept first, as a backup file in memory
(`backup_snapshot`, linear: the same file Export makes, made by the same
code into an `export_sink`, `IntoReader` or `IntoSnapshot`), then the
file is restored, `_restored(restore_report)` says it (books, notes,
settings, days, and the books the backup knows that this library lacks:
`_restored(1)` does not type-check, `tests/static/reject/restored-bare-count`),
and `undo_offer(BackupRestored())` is made; its `Undone` puts the snapshot
back (`PutBack`: shelf, place and Trash exactly as they were, the reading
log replaced, not merged), its `Final` frees it, so a snapshot unconsumed
is a type error (`snapshot-not-handed-on`). A restore whose snapshot
cannot be made (memory, a book's notes unreadable) is not made; a file
found damaged midway is put back at once. Left behind by an Undo: a
collection the restore made stays, empty, and orphan records a restore
kept for books not in the library stay until they are imported.

Export says how it ended (`export_outcome`, matched with `case+`:
`tests/static/reject/export-unmatched`): in a browser the file is
downloaded and the dialog says it is in the downloads; in the app a
blob download does nothing in the WebView, so the file goes to Android's
share sheet (bridge's `share_file`) and the dialog says it was shared,
a closed sheet or a failure is said too. Settings says under Backup,
browser and app alike, what a backup holds and that the books' files are
not in it.

## Every error says what to do (#360)

The error banner (`error-banner`, `src/notice.bats`) says a failure and
a next step, made in one place from data: `notice_say(failure)` for a
fault (`SettingsNotRead`, `BookFileLost`, `StorageFull`,
`RotationNotLockable`, ...; `notice_say_part(chapter)` for a chapter
that could not be read, which it names), and `notice_say_named(name,
name_len, named_failure)` for a file or book that has a name
(`NotAnEpub`, `PackageDamaged`, `FileEmpty`, `BookFileNotStored`, ...).
The words come from two total `case+` matches, `_what_put` (what
happened, per `host`: `InBrowser | InApp`, so the app never says
"browser") and `remedy_of` / `named_remedy_of` (the next step, a
`remedy`: `ReopenQuire`, `ImportAgain`, `OtherChapterOrReplace`,
`ChooseAnotherFile`, `UpdateQuire`, `FreeSpace`, `OpenAgain`,
`RemoveGrantByHand`, `UseDeviceRotation`, `CopyByHand`, `RestoreBackup`,
`TryNextPhrase`), so a failure added without words or without a next
step does not type-check (`tests/static/reject/notice-without-remedy`).
Where reopening is the step, the banner has a Reopen Quire button
(`error-reopen`, a reload). A step is words, not a Try again button: no
failure has data to retry from, and a retry would be a closure (linear).
A chapter's failure does not say "import the book again" alone: that
meets the duplicate dialog, so it also says to choose Replace.
`notice_error` is private; `tests/static/notice.py` (in
`tests/static/run.sh`) rejects `notice_error(` outside `notice.bats` and
a wildcard in a match of `ArchiveFailed(_)` (`tests/static/notice/reject`).
Import's causes are matched one by one (`_archive_named`); only a book
that declares its protection is blamed on DRM (below), never a damaged one. A sync's result texts, made by
`sync.bats` from its `sync_result`, go through `notice_sync_said`.
`expectBannerSaysWhatToDo` (`e2e/helpers.js`) checks a banner has a
Reopen Quire button or words naming the step, and in the android project
no "browser".

## A book that declares its protection is refused, named (#427)

A file that *declares* its encryption is not a guess, so it is refused at
import, before its container.xml is read (`_protection_check` in
`src/import.bats`, only for an import, since a stored book was checked
then), with the scheme named and not added to the library. What it looks
for, in this order: `META-INF/license.lcpl` (Readium LCP,
`ProtectedByLcp`), `META-INF/sinf.xml` (Apple FairPlay,
`ProtectedByFairPlay`), `META-INF/rights.xml` (Adobe ADEPT,
`ProtectedByAdept`); then `META-INF/encryption.xml` read by
`encryption_of` (`src/epub_xml.bats`): `ns.adobe.com/adept` (ADEPT),
`readium.org/2014/01/lcp` (LCP), `kobo.com` or `kobobooks.com` (Kobo,
`ProtectedByKobo`), else any `EncryptionMethod` whose `Algorithm` is
neither font obfuscation (IDPF's `http://www.idpf.org/2008/embedding`,
Adobe's `http://ns.adobe.com/pdf/enc#RC`: undone by a reading system,
no DRM, and not refused) is `ProtectedUnknown`. Each is a
`named_failure` and an `archive_failure` (`DrmAdept`, ...), matched with
`case+`, so a scheme added without words does not type-check. A damaged
book that declares nothing, or whose encryption.xml cannot be read, stays
"damaged": DRM is never guessed from damage.

By research (Thorium, Calibre, Readium's docs): Thorium, which has an LCP
client, only says what is missing ("This publication needs an LCP
passphrase", and, for an encrypted publication with no licence,
"Publication is encrypted but lacks an LCP license!"); Calibre, which has
none for the schemes it cannot open, says the book is locked by DRM and
points the reader to its manual's DRM page, offering no way round it.
Quire has no client for any scheme, so its words name the scheme (as
Thorium names LCP), say it cannot open it and that the book was not
imported, and give the next step, which is to read it in the app it came
from or get a copy without DRM (`ReadWhereItCameFrom`); it points to no
way of removing DRM. A build that one day has a client for a scheme
changes only that scheme's case. Kobo's check is a guess at its
namespace (the issue names `http://www.kobo.com/...`; no Kobo book was
available to look at), written in one place. The books the tests use are
made by `e2e/drm-books.js` (chapter bytes replaced by random ones, the
encryption.xml and licence files written), registered in
`e2e/epubcheck.spec.js`, and played by `e2e/drm.spec.js`.

An OPDS entry whose acquisition link has type
`application/vnd.adobe.adept+xml` or
`application/vnd.readium.lcp.license.v1.0+json` is an `acquiring`
(`AdeptAcquisition`, `LcpAcquisition`, in `src/opds.bats`, kept over the
entry's other acquisitions): with no EPUB link of the entry's own, the
row says "Protected by Adobe DRM: Quire cannot open it, so it cannot be
got here" (or Readium LCP) in place of Get and the licence is never
fetched; an entry that also has an EPUB is got as ever
(`e2e/drm-catalogue.spec.js`).

**Copy details and Report on every read failure (#507).** A failure
whose banner is about stored data or a book that could not be read
offers Copy details and a Report link, as `notice_unexpected` does, and
keeps the details for About's Copy last error details. The details are
data built in one place (`_report_make` in `src/notice.bats`): Quire's
version, the platform, the failure's name (`_failure_name`, a total
match), a chapter's number or the length of a file's name, a line saying
what the details hold ("no book text, titles or passwords") so the
reader sees it before sending (Firefox's about:support and Signal's
debug log both say what they hold, and hold none of the user's content),
and, for a failure of records, how many the last read could not use and a
line for each of the first 16 (`record_note`: the record's id, which is
the hash of a file and not a title, why it cannot be used, its size and
its first 12 bytes, which are the format's magic, kind and versions, as
a crash report keeps a file's header and not its content). The library's
read notes them (`libstore_read`) and the failure that says so takes
them. Which failures have details is `detail_source_of`, a total match
(`FromFailureAlone`, `FromRecordNotes`, `NothingToReport`, the last for a
platform's refusal of a copy, a selection, a rotation lock, a grant or a
narration, which leaves the details of the failure before it in
place), so a failure added without saying does not type-check
(`tests/static/reject/notice-without-details`). A later field (the groups
lost, each one's CRC: #510) is one more field of `record_note` and one
more line of `_put_note`. `e2e/notice-details.spec.js` checks each kind
of record, annotations and settings: the buttons, the fields, no book
text, and About.

## Every outcome is said, and the unexpected as such

After #334, where a Google error that ended the consent screen reached
quire as the reader backing out, and was said only on a line of the
Sync screen:

* The plugin and bridge report every error and unexpected condition as
  an outcome of its own, never folded into another. What they do not
  recognise is an explicit `...Unexpected` constructor, carrying which
  case it was as a datatype (bridge's `google_unexpected`) and the
  answer as bridge's JS wrote it.
* quire matches every answer with `case+` and handles every
  constructor visibly: google_authorize's `AuthorizeRefused` by each
  `google_status` (`_refusal_result` in `src/sync.bats`), a cancel the
  reader made noted on the Sync screen, every other end of a sign-in
  or sync the reader started said in the error banner (`_reader_told`).
* An `...Unexpected` outcome goes through `notice_unexpected`
  (`src/notice.bats`): the error banner says an unexpected error
  occurred while doing what it was doing, with Copy details (Quire's
  version, the platform, what was being done, the call, the case, and
  the answer as the atom kept it, an access token's value written as
  its length) and a Report link to Quire's GitHub issues. A refusal
  with a code is said the same way (`notice_failure`), the code in its
  text ("Details: DEVELOPER_ERROR (10)").
* An e2e test passes through every constructor of every answer quire
  handles (`e2e/sync-android-outcomes.spec.js` for google_authorize);
  an answer bridge's JS never gives is passed through by bridge's own
  dynamic test.
* A call that never answers is an outcome too (#340): no call to Google
  is left pending with nothing shown. A call that shows nothing
  (`authorizationForScopes`, `clearAuthorizationToken`, `revokeAccess`)
  is ended after 30 s (`GOOGLE_ANSWER_MS`: Play services documents no
  timeout, so it is chosen from what comparable software does: OkHttp
  ends a request at 10 s each for connect, read and write; Firebase
  Auth's own 3 minutes is the length developers call too long, and
  Flutter developers who bound a hanging `signIn()` themselves use
  about 30 s; Google's Tasks guide says to bound a wait and gives no
  value, only a 500 ms example; and Nielsen's 10 s is the limit of a
  reader's attention, a sync saying "Syncing..." meanwhile) as `GoogleNoAnswer`: "Google didn't
  answer. Check the connection, then try again." (a revoke's, in the
  banner, with where to take the grant back by hand). The consent screen
  (`authorizeScopes`) is the reader's to take as long as they like, so
  no timer ends it: while it is awaited (`GoogleAsking`) the status card
  says "Waiting for Google's consent screen. Finish it there, or stop
  waiting." and shows Stop waiting (`sync-stop`, `sync_stop`) in place
  of Sync now and Turn off; it ends the ask as the reader's cancel, as
  backing out of Google's screen does, and a second ask meanwhile is
  said as the consent screen already open. Each such call is the
  promise of a resolver kept in a cell with the call's number
  (`answer_wait`, `consent_wait` in `src/sync.bats`): the plugin's
  answer and the timer or Stop waiting each settle that number, the
  first resolves it, and what comes after (the answer of a call already
  ended) is dropped, so it changes nothing, keeps no token and asks
  Google nothing more (`_authorization_late`: a late answer that logged
  the reader in after they were told Google did not answer is what
  Flutter developers who time out Firebase's sign-in found).
  `e2e/sync-android-hang.spec.js` leaves each call pending (`hold` in
  `e2e/sync-stores.js`) and settles it late.

## What the types guarantee about the interface

The stylesheet is built in Bats, not written as CSS, in modules that each
have their own `.sats`, so a change to one (or a static fixture put into
it) re-checks that module and what stages after it, not all of it
(#462; `style.bats` was 3478 lines and 7 to 18 minutes a change). In
order: `src/palette.bats` (the roles, `PAL`, and the statements `SURF`,
`EDGEP`, `HARMONY`, `VEILED`), `src/palette_proofs.bats` (their proofs,
written by `scripts/gen-harmony.py`, each an exported `prval` with a
`primplement`: the costly part), `src/sheet.bats` (the builder, rules,
layout declarations, the spacing scale), `src/declarations.bats` (the
declarations that name a colour, under their proofs),
`src/theme_rules.bats` (the themes and the base rules), the screens'
rules (`shell_rules`, `overlay_rules`, `reader_rules`, `page_turn_rules`,
`panel_rules`, `reading_settings_rules`, `adaptive_rules`) and
`src/style.bats`, which puts them in order (`app_style`). A fixture goes
into the module of its area, not into one that holds proofs
(`reject/role-unmatched` is in `palette.bats`). Keep each module's `#pub`
declarations stable: bats re-checks what staloads a `.sats` only when
more than line positions change in it (bats-lang/bats#243):

* A text colour and its background are only ever set together
  (`surf`), with a proof (`SURF`) that the pair reaches 4.5:1 in each
  of the five themes. The proof is css's `CONTRAST` over the palette
  (`PAL(t, r, c)`, its theme a `palette` and its role a `colour_role`,
  both datasorts, so a role is passed as a `role_value(r)`, never a
  number): a table of every sRGB channel's linear light (`LIN`, made by
  css's `scripts/gen-contrast.py`) bounds each colour's luminance, so
  a pair that falls short does not type-check. Control edges and
  accents need 3:1 (`EDGEP`). A field's placeholder is text like
  any other (quire#357): `input::placeholder` is written through `surf`
  as muted on the field's card (`S_muted_card`, proven in each theme)
  and drawn at full opacity, so a placeholder is under the proof too;
  `textContrastShort` in `e2e/controls-shown.js` measures it in the light
  and dark themes (`e2e/layout.spec.js`).
  A chosen tab is told apart by more than a tint (quire#358, WCAG
  1.4.11; Material 3: an underline on the active tab): `.tab
  [aria-selected=true]` keeps the card and draws `underline`, a 3px inset
  line in the accent whose `EDGEP(accent, card)` is proven 3:1 in each
  theme; `stateCueShort` in `e2e/controls-shown.js` fails a tab list whose
  chosen tab has no cue the others lack. Grounds without text (`fill`, `tint`)
  set their font size to 0, and a dialog's veil makes its own text
  transparent.
* Each theme is written (`theme`) only with a proof (`HARMONY`) that
  it follows css's harmony rules (`harmony.bats`, which gives each
  rule's source): its hues in at most three families of 30 degrees;
  its surfaces, bars, edges and text neutrals of the first; danger and
  the error banner red, highlights yellow; accent and danger as
  saturated; a card lighter than the page; body text at 7:1; and, in a
  dark theme, a ground that is not black, text that is not pure white,
  and calm accent, danger and edges. No text/ground pair vibrates: one
  of them is calm (`SURF`). `scripts/gen-harmony.py` writes the proofs
  from `PAL`; the solver checks them, so a palette that breaks a rule
  does not type-check.
* Spacing comes from one scale (#331): `space(n)`, Material's grid as
  a datatype indexed by its length (4, 8, 12, 16 and 24 px), written
  by `spaced` and `spaced_pair` into the paddings, margins and gaps of
  the screens, sheets, menus and dialogs. `SPACE_INSET` (8 px,
  Material's least gap between targets) is the least a control keeps
  from its container's edges; the page gives it as `--space-inset`,
  and the layout walk (`insetsShort` in `e2e/controls-shown.js`, run
  by `fits` on every screen it walks) fails any control nearer its
  container's padding box than that. A full screen's rows and notes
  are cards inset 8 / 16 px (`spacing_rules`), a panel opened as a dialog
  16 px, a dialog 24 px. #332 is to prove the insets statically.
* Only the spacing forms write a gap, padding or margin, and only
  `scrolls`, `scrolling`, `clips` and `capped` write an overflow or a
  max-height (#500): those properties are not in `lay`'s `prop` (they are
  `spacing_prop`, which only the forms take), so `lay(sheet, Gap(), "10px")`
  does not type-check (`tests/static/reject/lay-writes-gap`, `-padding`,
  `-overflow`, `-max-height`). A value is a step of the scale (`SpaceNone`
  to `SpaceExtraLarge`: `spaced`, `spaced_pair`), or a form named for what
  it is: a safe-area inset (`spaced_safe`, `reserve_safe`), a margin pulled
  out (`pulled`), automatic (`auto_margin`, `centred`), the book's em
  (`prose_margin`), room kept for something drawn in the padding
  (`reserve`: a chevron, a page number, an outline's indent, the Undo
  toast), the reader's own variables (`page_padding`, `safe_area_margin`).
  Values that were off the scale moved to the nearest step (2 to 4, 6 to
  8, 10 to 12, 14 to 16), a few pixels. `offScale` in `e2e/controls-shown.js`
  holds every visible element's gaps to the scale on every screen the walk
  reaches. The sheet's budget is 64000 bytes (it was 60000): the costs the
  forms declare are upper bounds, and the sheet stays under 65536.
* The page's width and height are a whole number of pixels (`page_extent`,
  indexed by whether it is whole; `page_width_rule` and `page_height_rule`
  (`src/page_size.bats`, a module of its own so its fixtures check in a
  minute, where a snippet in the old `style.bats` cost 7 to 18) give the `.caf`
  rule's `max-width` and `max-height` from a `page_extent(1)` only,
  so an extent that is a fraction does not type-check:
  `tests/static/reject/page-width-fraction`, `page-height-fraction`). The reader
  scrolls to page n by n times the width (the height, down) it is told and
  counts pages by the scroll width over it, and both are whole numbers (bridge's measure
  and `scrollWidth` round). A Pixel 9's window is 1080 device pixels at
  2.625 a CSS pixel, 411.43 wide and 923.43 high; the page was as large as
  that, the
  offsets 0.43 px out more with each page, and a chapter of 19 pages or
  more was counted a page too many, whose scroll clamped to nearly the
  page before it: the last page of every chapter, doubled, and each page
  before it begun in the previous page's last letters. The rule rounds
  the container's width down (CSS `round()`, Chrome 125; a WebView
  without it drops the declaration and is as before). What the proof does
  not reach is the browser (that columns are as wide as the page and that
  `round()` rounds): `e2e/fractional-window.spec.js` plays a window 411.43
  wide or 923.43 high and walks two chapters page by page across, right to
  left, as a spread, down (a vertical book) and scrolled.
* A setting with two states is a switch (`_switch_row`: Justify text,
  Hyphenation, Dim images, Turn pages with volume keys, Full screen,
  Lock rotation), never a segmented On | Off nor a lone pressed button
  (quire#363, Material 3: a switch makes a binary selection and takes
  effect at once); a segmented group is for three or more choices, or
  two that are not on and off (Pages | Scroll). `onOffPairs` in
  `e2e/controls-shown.js` fails a screen that has one, in `fits`.
* A sign-in field is named by a visible label (quire#361, WCAG 3.3.2 and
  1.3.1): `ui_form_field` (`FormUrl`, `FormUser`, `FormPassword`,
  `FormName`) makes a `<label for>` above the input and shows only an
  example as the placeholder, so the name does not vanish as the field is
  typed in; `ui_field` has no such kinds, so a password field made
  without a label does not type-check (`tests/static/reject/
  form-field-as-field`). A sync service's step button is `Sign in to
  <service>` for every service (`sign_in_label`, the title being
  `service_title`), and a row that opens a screen ends in a chevron
  drawn by the stylesheet (`.chev::after`, with an empty alternative text),
  never a character of its words: `tests/static/glyphs.py` rejects U+203A in
  `ui_text_btn`. `labelsShown` and `labelInName` in
  `e2e/controls-shown.js` check both on every screen the layout walks.
* The base rules are the only `!important` ones: every control is at
  least 48px square (quire#403: Material 3 and Android's accessibility
  guidance say 48dp, Apple's HIG 44pt, WCAG 2.5.5 44px, which 48 also
  meets; the app is released on Android; `targetsShort` in
  `e2e/controls-shown.js` measures it on every screen the layout walks), text fields use a 16px font (so iOS does not zoom
  in), and focus shows a 2px ring in the text's own colour.
* The sheet's size is in its type (`sheet(r, media, open)`: r bytes
  left, and whether an @media block and a rule are open), so it always
  fits the 64 KiB text it is put in, and a rule is opened only outside
  another and closed only once.

Elements are made through `src/ui.bats`:

* Plain elements come from a tag type with no interactive tags; a
  button, a field or an image can only be made by a constructor that
  names it. A text button is named by its text alone, so its name
  holds what it shows (WCAG 2.5.3); an icon button is given its name;
  an icon is a glyph of one monochrome set, a subset of Material
  Symbols (Apache-2.0, `assets/fonts/material-symbols-subset.woff2`,
  made by `scripts/icon-font.py`) at its Private Use Area code point
  (`_glyph`, `ui_icon_set`), drawn in the button's own proven text
  colour, never an emoji (#274);
  images are decorative (`alt=""`); an audio element (`ui_audio`) has no
  controls and is hidden from assistive technology; a role that needs a name (dialog,
  region, toolbar, menu, group) is given one with it.
* Each element id is made at one place in the code, no numbered id
  (`nid_make`, a prefix and a number) can spell another, and every id
  the code names is one it makes: `tests/static/ids.py` checks the
  source (the constructors, `ui_harm_id`, the controls' `*_control_id`,
  and helpers that pass an id on), in CI through `tests/static/run.sh`. An element made again to
  reset it (a search field, a file input) is made by one function,
  called at startup and at the reset.
* `ui_attr` takes a typed attribute that cannot be a name, a role or a
  style. The inline styles are a place (`ui_place`: left or width,
  in tenths of a percent up to 100%) and a fixed page's box
  (`ui_fixed_box_n`: width and height, 1 to 10000 px, and a zoom of 1
  to 10000 thousandths, so a zoom of 0 does not type-check), each
  written from numbers alone, so no inline style can set a colour or
  anything else the stylesheet proves.

Nothing is lost at a click, except by emptying the Trash. That is the
one irreversible action because it is the one with no visible effect: it
only gives storage back, so nothing a reader needs to do ever requires
it. Every other action changes what the reader sees, and is offered back
(Undo), keeps what it replaces, or can be done again (reauthorizing
sync brings back what turning it off took, with the security boundary
the revocation is for); an action with a visible effect is never a
`harm`. Removing a dictionary does not follow this yet: its files are
deleted when the Undo offer is made final (#396 moves them to the Trash).

* Removing a book moves it to the Trash (the shelf `Trash`), where it can only be
  restored; archiving, hiding, deleting a highlight or bookmark and
  resetting the settings are done at once. Each is offered back by the
  Undo toast (`undo_offer` in `src/undo.bats`), whose undo runs only
  from its own button, whose listener the module registers
  (`undo_listen`). An offer stays until it is used, dismissed (the
  toast's Dismiss) or another takes its place, which makes the earlier
  one final (quire#364: Material 3's snackbar with an action, WCAG
  2.2.1): `undo_offer` takes an `offered(UntilDismissed)`, a datatype
  indexed by its `offer_life`, so an offer with a `Brief` life does not
  type-check (`tests/static/reject/undo-offer-brief`), and each
  constructor says what an Undo would undo. `offered` is a `datavtype`:
  `MovedToTrash` carries the book's title, and the toast names it
  (`'Keep Me' moved to Trash`, a title over 60 bytes cut at a character
  and ended with an ellipsis, `title_put` in `src/titles.bats`; quire#385,
  Material 3's snackbar says what was done).
* A factory reset moves every book to the Trash and resets the
  settings (`lib_trash_all`, `set_reset_undoable`), with one Undo that
  puts back each book's shelf and the settings.
* Emptying the Trash is the one irreversible action, and the one
  question with a red button: the dialog (`src/modal.bats`) asks a
  `harm` (`src/ui.bats`), which has only `HEmptyTrash`, made of the
  number of things the Trash holds, `{things:pos}`: the Trash cannot be
  asked about when it is empty (`tests/static/reject/harm-empty-zero`).
  The question counts and names what goes (quire#385, M3's dialogs pose a
  specific question; Gmail and Drive say "Delete forever"): "Delete 2
  books forever?", the text naming at most 3 titles and the dictionaries
  ("'A', 'B' and 'C' will be deleted for good ..."), the red button
  "Delete forever". It closes any Undo offer first, since what that would
  put back is gone.
* Red is the stylesheet's rule for `[data-harm=y]`, which only
  `src/ui.bats` sets, and only from a harm: on the harm's button
  (`ui_harm_button`, whose id and label are the harm's; the Trash's
  Empty Trash, beside its summary) and on a button whose tone is
  `Danger(h)` (the dialog's, for `Harmful(h)`). A click on a harm's
  button is dispatched by the harm its id belongs to (`_harm_clicked` in
  `src/bin/quire.bats`, which counts what the Trash holds first) to
  `lib_ask_harm`, which asks that same harm, so a red button always asks
  about what it names.
* The Trash's screen says what it holds (quire#385): under its title a
  line "1 book · 4.0 MB. Kept until you empty the Trash." (the books
  and the dictionaries in it, the books' file sizes; `_trash_head` in
  `src/library.bats`, `lib_trash_dictionaries_set` from
  `dict_trash_render`) with Empty Trash beside it, there only while the
  Trash holds something. Nothing is purged by itself: that would be an
  irreversible action the reader did not take. A book in the Trash has
  Restore first in its menu.
  Restore all books (`trash-restore-all`, quire#494; Windows' Recycle Bin
  has "Restore all items" beside its empty button, Drive and Gmail only
  select-all then restore) comes before Empty Trash, plain since nothing is
  lost: `lib_restore_all` puts every book of the Trash on the shelf, as a
  single Restore does, and returns the Trashed books' shelves, so the offer
  `BooksRestored` (Undo) puts exactly those books back in the Trash
  (`lib_untrash_all`) and its end lets them go (`lib_shelved_free`). It
  says "books": the dictionaries in the Trash have their own Restore.

What deletes is private to the module that owns it: deleting a book
and emptying the Trash (`src/library.bats`), and dropping an
annotation (`src/annot.bats`) have no `#pub`. Emptying runs only in
`lib_ask_harm`, when the promise of the dialog's answer
(`modal_confirm`) resolves `Accepted`, and only the dialog's second
button's click resolves it so: the dialog registers that listener
itself (`modal_listen`) and its answer function is not exported, so
other code can dismiss a dialog (`modal_dismiss`, which answers
`Declined`) but never confirm one. A destructive question's title, text, button verb
and red marking all come from one `harm` value.

No promise's value is dropped unread (`$P.discard` is not used): a
chain ends with `$P.finish`, and a value it ignores is written out as
`llam(_) => ()`, with a comment saying why losing it is harmless (a
cover, a hint, a delete nothing reads again). What fails is said
(`src/notice.bats`): the error banner (`error-banner`, `RAlert`) is a
child of `bats-root`, so it shows over the library and the reader
alike. A write of the reader's own data (the library, annotations,
settings, statistics, catalogues, dictionaries, sync's store) ends in
`save_checked`, which says once a session that storage may be full; a
book whose own file was not stored is named (`_book_store_checked` in
`src/import.bats`). A chapter that cannot be shown leaves the reader on
the page it was on (`_jump_checked` in `src/reader.bats`), or, as a book
opens, back in the library; either way the banner says why. A copy is
confirmed by the copy status (`copy-status`, `RStatus`), apart from the
Undo toast.

A read of storage that failed is never taken for an empty one (#174):
`lookup_bytes` and `lookup_content` (`src/book.bats`) answer
`StoredUnreadable` / `ContentUnreadable` apart from nothing stored, so
every load must say what it does then. A record each save rewrites
whole (settings, statistics, reading speed, catalogues, dictionaries,
sync's state, a book's annotations) that could not be read is not
saved this session (`src/storage.bats`: its save checks
`storage_savable`), and an unread book's annotations cannot be made;
the banner says so. The library is read as its records are (below): one
that could not be read at all is not saved this session and books are not
added to it, and the screen says why and offers what fits (#374, below); a book's record that is newer or not Quire's is
shown nowhere, said once and never written over; one that lost a group, or
that is under other ids than its key, is used, and one broken in its framing
is read from the version before it when there is one, else shown nowhere (#510). A backup that could not
read a book's notes is not made.

The overlays (the menus, book info, the reader's panels and the full
screens: Settings, Sync, a sync service's step) are a `layer` (`src/layer.bats`), whose
element ids only that module knows: they are shown and hidden only by
`layer_open` and `layer_close`, which keep the stack of open overlays,
last opened on top. Escape answers the dialog if one is open, and
otherwise closes the top of that stack (`layer_escape`), whatever
opened it: from Sync, Escape goes back to Settings, and another closes
Settings.

Back, Android's and the browser's, is one model (#333, `_go_back` in
`src/bin/quire.bats`): the dialog is answered No, else the top of the
stack closes as Escape closes it (Sync to Settings, Settings to what
was under it), else the in-book search's results end, else the book
goes back to the library; at the library with nothing open it is the
platform's. In the Android app the App plugin's `backButton` reaches
it (bridge's `listen_back_button`, `RBackButton`), and at the root the
app goes to the background (`app_minimize`, `minimizeApp`: what Android
12+ does itself at a root activity; `exitApp` would finish it). In a
browser `src/back.bats` pushes one history entry (the guard, at the
page's own address) above the page's own once there is anything to go
back from (a dialog, an overlay, the reader: `back_dialog_set`,
`back_overlays_set`, `back_view_set`), so Back takes it (`popstate`,
`back_popped`) and the app goes one step back, pushing it again if
something is still open. The app never takes a guard back on its own
(`history.back()` is asynchronous, and raced pushes and reloads): one
left after something closed another way is taken by the next Back, and
with nothing to go back from that Back is the platform's, so the app
goes on back past its own entry (`back_leave`, bridge's
`history_back`) and the page is left at once. The page restores its own
scroll (`history_scroll_restoration`, `ScrollManual`), so going back
over a guard never moves the library. `e2e/back.spec.js`
walks every screen of the layout's walk (`e2e/walk.js`, which
`e2e/layout.spec.js` walks too, so a screen added there is covered) and
checks Back goes exactly one step from each, in a browser and in the
android project, and leaves at the root.

The Settings screen (`LSettings`, `settings-screen`, made by `app.bats`
and wired by `_wire_settings_screen` in `src/bin/quire.bats`) follows
Android's settings pattern: one screen of groups, each complex area a
screen of its own opened from a row that shows its state. It opens
from the library menu's Settings only: in a book, the reading settings
sheet is the one settings place (#342). It holds Sync ›, Dictionaries ›, the backup
(Export backup, and Restore backup: the input `backup-file`), the daily
reading goal (also in the statistics panel; `stats_goal_show` marks
both), Reset settings and Factory reset, each with its Undo, and
About Quire › (`LAbout`, `about-screen`): the app's name and links out
of the app (`ui_link_out_https`, an address dom's `set_url_literal`
sets) to the home page, privacy policy and terms (no link to the
source: nothing in the app or its pages points to the repository but
the GitHub issues the pages give for contact).

Where sync and the backup are (#501): sync is how a new phone gets places,
shelves and notes, so the library menu has a Sync item (two taps from the
library, `MenuSync`, opening the Sync screen over the library, whose Escape
or Back returns to it) and an empty library offers "Sync with another
device" (`empty-sync`) beside Import and Get free books; the backup stays
in Settings (three taps), with a line under the first group saying that sync
keeps places, shelves and notes the same on the devices, that a backup holds
them in a file, and that neither holds the books' files. By research: Play
Books syncs through the Google account with no setting to find, Moon+ Reader
keeps its backup in Settings; a prompt after the first book is not used (a
nag before the reader has anything to lose). `e2e/settings-screen.spec.js`
checks both depths and the empty library's offer.

The reading settings' themes are swatches (#501, `theme_swatch_rules`): each
fixed theme is a button that wears its theme's class (`th-sepia`), so its
variables are that palette's and its sample "Aa" on its card is the theme's
own pair, proven in every theme (`S_fg_card`), the chosen one ringed in its
accent and underlined (`E_accent_card`); its name is its `aria-label`. Auto
(the clock's) is a word. `looksActionable` (`e2e/controls-shown.js`, in
`fits`) fails a chevron on something that is not a control, one that is
not drawn, or one without a control's pointer.

A pushed screen (Settings, Sync, Dictionaries, About: class `info`, opened
from a row that ends in a chevron) has a top bar, not a Done at its foot
(#502; Android's settings and Material 3's small top app bar have a
navigation icon and the title, iOS pushes a screen with a back item and
keeps Done for a sheet): `ui_screen_bar` makes a Back icon button (48 px,
named "Back", the `SettingsBack`, `SyncBack`, `DictionariesBack` and
`AboutBack` controls) and the screen's title, outside what scrolls
(`.tbar`), so it stays at the top. Back does what Escape does (with a
service's sign-in step open on Sync it ends the step), and the first focus
of a screen is its Back. The error banner (z-index over the screens, so its
Dismiss, Copy details and Report are pressed) sits under the bar while one is
open (`ui_banner_below_bar`, `data-below`, set where the stack of overlays
changes, `_open_set` in `src/layer.bats`): over the top of the screen it had
covered Back (found by sync-dropbox-android.spec on #544). Statistics, Catalogues and Collections are
centred dialogs and keep their Done (`dismiss_label(DismissScreen)`).
`e2e/settings-screen.spec.js` checks the four bars, that none has a Done, that
the bar stays put as the screen scrolls, and that Back closes it.

The home page, privacy policy and terms are plain static HTML in
`homepage/` (#216), published by `deploy.yml` beside the app at
`https://bats-lang.github.io/quire/homepage/` (`privacy.html`,
`terms.html`). They are not the app's: gen-pwa does not read them, the
Android project does not hold them, and the service worker (bridge's
`produce_service_worker`) answers only files directly in its scope, so
it neither answers nor keeps them (`e2e/about.spec.js`). The privacy
policy states what the code does: change it with any change to what is
stored, what leaves the device, or the Google scopes asked for.

The library bar's More options (Material's overflow, ⋮, #333: a gear
would say it goes straight to Settings) opens the library menu:
Settings, About Quire (the same About screen, so the library reaches
it without Settings), Catalogues, Reading statistics, Hidden, Archived
and Trash (each a screen of its own, below), Install Quire (while the
browser offers it) and Close. Empty Trash is not in it: it is on the
Trash's own screen.

## The library screen (#375, #376, #377, #404)

One redesign of the library's header and empty state, decided by
research (what comparable library apps do) and written here:

* **The bar is one row** (`library-bar`): the name, Import (`import-button`,
  a plus; its file input, named Import EPUB, lies over it, since a page
  cannot open the picker itself), Sort and view (`sort-menu-button`) and
  More options, with the search field on a row under them. Material 3's
  top app bar is a title and up to three trailing actions, the rest in an
  overflow menu; Apple Books has its view and sort control in the top
  right of the library, Play Books its sort in a menu. At 320 px the
  bar used to wrap to five rows (the first book began 53% down); it is
  one row now and the first card begins in the top 40% of the screen
  (`e2e/library.spec.js`, "the first book starts in the top 40%"). Import is
  the screen's main action but an icon, not a chip among chips: it is the
  only control that adds, and Material's guidance is that chips are for
  filters and choices, not for actions.
* **Sort and view is one menu** (`LSortMenu`, `sort-menu`, an `ovl` over the
  library; Apple Books' Sort By menu offers Recent, Title, Author and
  Manually in one menu, Material's menus check the current choice): the
  five orders (`sort_order`: Last opened, Title, Author, Date added,
  Series) and List or Grid (`layout`) as two groups of
  `menuitemradio`s (`ui_menu_choice`), the current one `aria-checked`
  (`_view_show`), the mark drawn by the stylesheet (`.mi[aria-checked=true]::before`).
  A choice closes the menu and is kept as before (`set_apply`, `set_save`).
  `sort_next` is gone; `tests/static/next.py` fails a `*_next` function
  that takes and gives a datatype of more than three constructors (the
  reader's footer readout, tapped to go round as the Kindle apps' footer
  does, is the one allowed). The filters (All, Unread, Reading, Finished)
  stay chips: they are a filter of the collection, which is what Material
  3 chips are for, and List and Grid, a view, are no longer among them.
* **Hidden, Archived and Trash are screens of their own** (`LShelf`,
  `shelf-header`: a back button, the shelf's name and More options, in
  place of the library's bar while it is open), opened from the library
  menu, reusing the library's list; there is no shelf selector on the
  library (the old shelf button cycled four shelves, up to four taps from
  Trash back to the library, and a prominent Hidden undercut hiding a
  book). Kindle keeps archived items out of the main library list too, in a
  menu entry of its own. A shelf is a layer, so Escape, Back and the back
  button close it as one step (`_escape_overlay`: `Escaped(LShelf())` shows
  the library again), and the filters, search and collection are the
  library's alone (`_passes` lets everything on a shelf through; opening a
  shelf clears the search and the collection). More options stays on a
  shelf's screen (the other shelves are one entry away). Empty Trash is on
  the Trash's screen, beside what it holds, as Drive's Trash has its Empty
  trash (quire#385). A book opened from a shelf's screen closes to
  the library (`_show_reader`). A shelf's rows offer Unhide, Unarchive (it
  says to import the book's file again: archiving drops the file) and
  Restore (Trash). A row's actions open on its More button and on a long
  press or right click (`contextmenu`), as before.
* **A book's menu is grouped, and Book info reads** (quire#386; Material
  3: "Vertical menu items can be grouped by adding a divider or small
  gap"). The menu is Read (Continue once opened, Read again once
  finished: `lib_reading_state`, the one rule behind the card's word and
  the filter chips; none for a book in the Trash or archived), Book info,
  Collections, a divider (`role=separator`, `.msep`), Hide, Archive, and
  Move to Trash, which is made by `ui_removal_item` from a `removal` (as
  `ui_harm_button` is from a `harm`) and drawn by the stylesheet's
  `[data-removal]` rule with a line above it; it is not red, since Undo
  and Restore bring the book back. Book info has the same Read as its
  primary button, Move to Trash apart from Hide and Archive
  (`ui_removal_button`), and the author in `.info-author`, proven on the
  page's ground (`.ba` is proven on the card's: reusing it left a strip of
  the card's colour behind the author). `strayGrounds` in
  `e2e/controls-shown.js` fails a text element whose own ground is not the
  one behind it unless it is a control or a card. A book whose metadata
  says nothing of its accessibility is told so once ("This book gives no
  accessibility information.") instead of a "No information" line under
  each heading.
* **An empty library says what to do, and only that one** (`emptiness`:
  `NoBooksYet | NoMatch | NoCollection | NoUnread | NoneReading |
  NoneFinished | NothingHidden | NothingArchived | TrashEmpty`, made by
  `_emptiness_of`, said by `_emptiness_text`, and `_emptiness_offers` is
  true for `NoBooksYet` alone, each a total `case+`). NN/g on empty
  states: communicate system status, provide learning cues, direct
  pathways for key tasks. With no book to search, sort or filter the bar
  keeps its name and menu (`_tools_show`), and the message offers Import
  EPUB (`empty-import`, a primary button, its own file input
  `empty-import-file`, both inputs always there so a pick is never lost to
  a control made again) and Get free books (`empty-catalogues`, which opens
  the Catalogues). Every other reason for an empty view is said and offers
  nothing, since importing would not change it. The unreadable library
  (#374) keeps the bar's inert Import and no offer.
* **The book menu button is one box in both views** (#495): a 48 by 48
  square, `align-self: center` in the list (the card row stretches its
  children, which made it as tall as the card) and over the cover's corner
  in the grid; Material 3's trailing icon button is a 48dp target round a
  24dp glyph, centred in a one- or two-line list item and in the corner of a
  media card, never stretched. `cardMoreBoxes` (`e2e/controls-shown.js`)
  measures it, and `e2e/layout.spec.js` fails if the list's and the grid's
  boxes differ.
* **One word for a book's state** (`reading_state`: `StateUnread |
  StateReading | StateFinished`, `_reading_state_of`): the filter and the
  card use it, so the card says Unread and Finished where it said New and
  Done beside chips that said Unread and Finished.
* `e2e/library.spec.js` plays each of these (and `e2e/walk.js` walks the
  sort and view menu and the three shelf screens, so the layout, safe
  area, target size and Back specs cover them). The listener table has
  room for them: the library's wiring grew by four.

The page turns by a horizontal drag, recognized by the gestures package
(its classifier and drag state machine are proven there). Bridge's
`listen_pointer` on the reader view (`OnPointer("reader")`) sends each raw
pointer record. `_gesture_record` in `src/bin/quire.bats` hands it to the
gestures package's pointer source (`gestures_raw`), which batches the
records per frame and feeds the recognizer. The source answers with
gesture events and with actions for the host: `CapturePointer` (done by
`ui_pointer_capture`) or `WantFrame` (bridge's `animation_frame`, then
`gestures_frame`, at most `FRAME_ROUNDS` frames in a row). A pan scrolls
the page with the finger (`reader_pan`), a commit turns it and a cancel
puts it back. The page (`page`, region 1, `data-gesture-region`) takes
touch and pen only, so a mouse drag still selects text; its CSS
touch-action comes from the same axes the region is declared with
(`page_turn_axes` in `src/style.bats`). A drag's end suppresses the click
the browser sends after it (`_dragged`). The source captures a mouse
pointer only once it has moved more than 4 px: capture at pointerdown
would send the click to the reader view instead of the button under it,
so no button in the reader could be clicked.

Every page turn is animated (#246): a tap, a key, a button, reading
aloud and a drag. A copy of the page is kept in an overlay
(`page-turn`, idle: laid out but `visibility:hidden`), made by
`ui_copy_inert` in one flush of the DOM stream's own operations
(bridge's CLONE_NODE, then the copy's tabindex and gesture region
removed, `inert` set, its scroll set: quire's policy, not bridge's),
again a moment (`COPY_SETTLE_MS`) after the page last changed (a
chapter shown, laid out anew, an image come in), so a turn only
scrolls the copy to the place and shows it (the copy's images share the page's
blob URLs, which bridge revokes only once no image still loading holds them,
quire#532, `e2e/progress.spec.js`): on a 300 KB chapter its
first frame comes in 20 to 30 ms, where making the copy at the turn
took 110 to 200 (`e2e/page-turn.spec.js` holds it within 30 ms of an
instant turn's, in the same page). A turn shows only a `fresh_copy`,
which only `_copy_ready` gives, making a stale copy again first, so no
turn shows a chapter or a layout gone. The page
itself goes to the incoming page at once, so the place, the indicator
and the arenas' window move as before. The overlay is a strip of
[copy | gap] scrolled each frame, so the copy slides off (mirrored
right to left, along the axis for `Down`) with the stylesheet's edge
shadow, over a shade (`turn-shade`) on the page beneath. 280 ms,
eased out; a drag's commit takes what is left. Under
`prefers-reduced-motion: reduce` a turn is instant and nothing is laid
over the page; so it is in a chapter too big to slide a copy of
(`_chapter_heavy`, #423, below), which keeps no copy ahead either. The turn is a `turn_cell` in `src/reader.bats`
(`TurnStill`, `TurnHeld`, `TurnReturning`, `TurnWaiting`,
`TurnSliding`), each holding a linear `turn_sheet(HELD | SLID)` whose
constructors are local: a sliding sheet ends only by `_sheet_lift`, a
held one only by `_sheet_put_back` (the page back at its place) or
`_sheet_commit`, so no turn, interrupted or late, leaves the copy over
the page or the page between two places (`tests/static`'s
`page-turn-*`). The shade's levels are proven in each theme
(`VEILED`, written by `scripts/gen-harmony.py`): under it the text
keeps 7:1 and the links, highlights and marks 4.5:1, so Night has
none.

A book's picture is shown full screen in the viewer (#382; opened by a
double tap on it or a long press, #365; `src/image_viewer.bats`). It is
fitted whole to the screen on the bars' dark ground (`RoleBar`, dark in
every theme; a picture is best seen on a dark ground, and the Close and
Zoom buttons are `RoleBarText` on `RoleBarHigh`, proven), not shown at its
inline size. The picture's box is the scroller's own size (`ui_picture_box`,
the one inline style besides a place and a fixed page's box:
`ui_fixed_box_n` with literal ids) at a zoom in thousandths of the fit;
`object-fit: contain` fits the picture in it, so the fit needs no
knowledge of the picture's size, and a zoomed box is larger than the
scroller, which scrolls it: a pan is a scroll (`ui_scroll_set`). The zoom
is held to 1 to 4 times the fit by `viewer_clamp`, whose result type is
`[zoom | 1000 <= zoom <= 4000]`, and every zoom reaching the page passes
through it (a zoom of 0 or a box past `ui_fixed_box_n`'s limits does not
type-check). A pinch is the gestures package's own (`GPinch`, a pinch
region 2 on the scroller, `image_zoom_axes`: none, so its `touch-action`
is none and the browser's pinch is not used; the scale is of the zoom
the pinch began at, the point of the picture under the fingers' middle
stays under it); one finger's drag is the viewer's own, read from the
raw pointer records (`viewer_pointer`: nothing to classify, every move
is a pan, a mouse is not dragged: its wheel and scroll bars are), and a
second finger ends it. A double tap (`dblclick`) zooms to 2.5 times the
fit where it is made, and the next goes back to the fit; it is instant,
so it is the same under reduced motion. The Zoom in and Zoom out buttons
(1.5 times, about the middle) are the single-pointer way (WCAG 2.5.1).
Resizing fits the picture again. By research (issue #382): Apple Books
and Kobo zoom a picture by pinch and double tap; PhotoSwipe, the web's
usual viewer, fits the picture, zooms to 2.5 times the fit on a double
tap and at most 4 times the fit (photoswipe.com/adjusting-zoom-level).
`e2e/image-viewer.spec.js` plays each, the pinch and the pan as touch
pointer events on the scroller.

The reading settings' sheet (`typography-panel`, opened by the bottom
bar's Reading settings) holds every reading setting in named tabs
within the one sheet (#288, which gives the research: Kindle's Aa menu
has tabs; a "More" row and a screen over the sheet were a vague label
and a modal over a modal): Look (theme, font, size, the spacings, ruby,
dimmed images), Page (pages or scrolled, pages on screen, margins,
justify, hyphenation, the screen), Turning (Tap to turn pages, each
choice with a drawing of its zones, mirrored for a book read right to
left, and in the app one switch, Turn pages with volume keys) and Read
aloud (shown where the platform speaks or the book is narrated), with
Reset to defaults under them all. The tabs (`sheet_tab` in
`src/ui.bats`) follow WAI-ARIA's tabs pattern: the chosen one alone
selected and in the Tab order, the arrow keys, Home and End moving the
focus and the panel with it (`_sheet_tab_key` in `src/bin/quire.bats`);
the sheet opens on Look, and its head (title, Close and the tabs) stays
at its top as it scrolls. The sheet is as tall as its tallest tab
(#301): the panels lie one over another in one grid cell
(`typography-panels`, `.tabpanels`), the ones not chosen `.unchosen`
(`visibility: hidden`: their room kept, but not seen, focused or read
out), so switching tabs moves neither the sheet nor its tabs, and the
height follows the rows actually shown; a tab chosen shows from the
sheet's top (`ui_scroll_to_top`). Their controls are one `typography_control`
datatype, stored, backed up and reset as before.

The reader is fixed to the window (`.rv`, not a height in `vh`, which
an Android WebView can make taller than what it shows), and the page
keeps out of the screen's safe area on every side (#275): above and
below in its paddings (`env(safe-area-inset-top)`, `-bottom`), at its
sides in its margins (`-left`, `-right`), so no text is under a camera
cutout, in or out of full screen, in either orientation. In the app the
WebView is given the cutout's insets by Capacitor's SystemBars (pwa's
`insetsHandling: native`: a WebView from 140 on reads them out, an
older one is padded natively instead). Every other screen, panel,
sheet, dialog, toast and bar pads the sides it can touch by `--safe-*`
(`spacing_rules` in `src/adaptive_rules.bats`): that side's inset and the spacing
scale's least inset beyond it, so none of its controls or text comes
near a system bar (#341, `e2e/safe-area.spec.js`). A spread's columns are at least
40vw, so two fit beside a cutout. A sheet's height is in `dvh`, and the
typography sheet's head (`.shead`), with Close, is held at its top as
it scrolls. `e2e/layout.spec.js` sets the insets through DevTools.

The visible reading area is given once, as the reader view's (`.rv`)
variables in `src/reader_rules.bats` (#296): the running footer sits 8px above
the screen's bottom inset (`--footer-bottom`, Android's navigation bar,
which the app is drawn over edge to edge), 16px tall
(`--footer-height`), and the page's paddings (`--page-top`,
`--page-bottom`) keep the text half a line (at least 12px) clear of the
footer and of the top inset. A column is the page's height less those
paddings, so it is exactly that area; a vertical page's column gap and a
picture's largest height are the same paddings. Pages are counted
across by the page's scroll width, which the column's height does not
change. Scrolled, the same variables are the page's margins instead
of its paddings (`_put_scrolled` in `src/settings.bats`), so the page
is the reading area itself and its text is clipped there, never drawn
under the footer or a system bar; two transparent fixed bands (the
page's `::before` and `::after`) keep a tap or a drag beside it the
page's, and a turn (`_step`) scrolls the area's height less one line
of the text, so the line its foot cuts is whole at the next screen's
head. `e2e/page-margins.js` measures those margins against the
insets the page computes, and the e2e fixture measures them at the end
of every test in the phone-sized projects (`MARGIN_PROJECTS`), full
screen too, whenever the reader shows a reflowed page, paged or
scrolled, with the bars down, so a spec that leaves the reader open
checks them; each line counts as drawn, cut to the page's scrollport.

The reader's bottom bar follows the reading direction (quire#359; Apple's
HIG flips progress and the next and previous buttons in a right-to-left
context, Material runs a progress bar from the right): the book's
`reading_direction` (`LeftToRight | RightToLeft`, from its spine, matched
with `case+`) is kept by `_direction_set` in `src/reader.bats`, which gives
the bar (`.bot.rtl`) and the scrubber (`.trk.rtl`) their class and swaps
the page-turn buttons' arrows, and every drawing along the reading axis
takes `_drawn_at`: the thumb, the chapters' ticks and the tip are placed
from the right and the fill grows from it, and a drag's x on the track is
turned back into the book's thousandth (`_track_at`). Previous is right
of Next. `expectBarFollows` in `e2e/helpers.js` checks it for a book
whose spine reads right to left, a Hebrew one whose spine does not say so,
a vertical Japanese one, and a left to right one; `vertical.spec.js`
fails first, naming the cause, where no font has Japanese characters
(CI installs `fonts-noto-cjk`).

A bookmarked page shows its mark once the bars hide (#388): a ribbon
(`bookmark-mark`, `.bmk`, clipped by `clip-path`) in the page's top-right
corner, inside the `--page-top` band, in the accent (proven on the ground as
text is, `S_accent_bg`), shown by `.chrome-off .bmk-on`; `annot_star`, the one
place the bookmark's state reaches the screen, matches a `bookmark_state`
(`Marked | Unmarked`) to set the star and the mark together. Kindle and Kobo
draw theirs in that corner; with the bars up the star says it. The bottom bar
has Previous chapter and Next chapter beside the page turns (`chapter-previous`,
`chapter-next`, `reader_chapter_step`), shown where there is a chapter to go
to and not in a fixed-layout book (its chapters are its pages), following the
reading direction as the page turns do (`.bot.rtl` orders): the next chapter is
two taps from the page, three through Contents. `e2e/page-marks.spec.js`.

A book is set vertically as Readium sets it, from its OPF (the book's
CSS is dropped): `vertical-rl` when its spine reads right to left and
its language is Chinese, Japanese or Korean, `vertical-lr` for
Mongolian in its script (mn-Mong) read left to right. `spine_vertical`
in `src/epub_xml.bats` answers a `writing_mode` (`Horizontal |
VerticalRightToLeft | VerticalLeftToRight`), from the spine's
`spine_progression`, and `src/reader.bats` keeps it in `_vertical`.
CSS columns follow the inline axis, which then runs down, so its pages
go down the page: the page's class is `caf vertical` (not `rtl`, whose
`direction` would turn that axis upward), a column and its gap (the
page's top and bottom paddings) are exactly the page's height, and
Latin and digits are turned, the default `text-orientation:mixed` (JLREQ: an English word is rotated 90 degrees; only a short number stands upright, as tate-chu-yoko, usually a number of two digits; no browser supports `text-combine-upright: digits`, and Chromium's `all` needs the run in an element of its own: see Text parts below), and `_page_axis` (`Across`, `AcrossBack`, `Down`) is what counts, finds and
shows pages, by scrollTop for `Down`. Such a book is always paged, one
column a screen, a drag does not follow the finger (a committed one
turns the page), and the settings of the page's layout and of its
words' spacing and breaking are hidden while it is open. A paragraph's
margins are logical (`margin-block`, and the Paragraph spacing setting
as `margin-block-end`), so set vertically the space after it is beside
it and its lines keep their length; that row stays. Taps, keys and
swipes keep the meaning of a book read right to left.

**Text parts (#391).** Set vertically, each run of one or two ASCII digits
in a text (`_tcy_find`: not one in a longer number, not one against a
Latin letter, which is a word, and not a digit of a character reference)
is wrapped by `_tcy_parts` in a *text part*, a span of the class `tcy`
that the stylesheet sets `text-combine-upright: all` (inside
`.caf.vertical` and `.caf.vertical-lr` only, so no horizontal book has the
rule), the text between the runs in parts of their own. A part has the id
`t<number>` and the attribute `data-part` (`_part_add`), and it takes no
content node number: the content node is still one span, `c<N>`, whose
text is the whole text, so a note, a highlight, a place, a search hit and
read aloud keep their node numbers and UTF-16 offsets (the numbering
code in search, read aloud and `_skip_spans` is unchanged, and a search
for "第1章" still matches across the parts). Bridge's `data-part` is
what makes that so: a position in a part is an offset into the text of
its *owner*, the nearest ancestor with no `data-part`, and a click's
target or the element at a point is the owner (bridge's `ownerOf`,
`textPointAt`, `textOffsetOf`; `mark_range`, `select_range`,
`measure_text_offset`, `caret_position_from_point`,
`get_selection_range`, `element_at_point` and an event's target). By
research: JLREQ sets a number of 1-2 digits upright in one cell and a
longer one turned (an English word is turned too); CSS Writing Modes 3
has `text-combine-upright: all` for an element and `digits <n>` which no
browser has (MDN); Manabi Reader normalises a book's legacy
`-webkit-text-combine` the same way; a book's own CSS is dropped here,
so there is none to honour. Not wrapped: a number of 3 or more digits, a
decimal's digits are each a run ("3.5" is two), and a fullwidth digit
is upright already. Chrome scales a run to its cell by the font it was laid out in and does not do it again when the reading face arrives after, so a page opened again looked different from the page it was (`e2e/relaunch.spec.js`): a vertical book switches combining off and on again (`_tcy_refit`, the style `style-tcy`, a layout between) as a chapter is rendered, in `_relayout` and 150 ms after a face arrives (the browser lays text out with the face after the event). `e2e/vertical.spec.js` plays it, and bridge's
`tests/dynamic/decoders` the offsets and targets.

A fixed-layout book (EPUB 3.3 §8.2, `rendition:layout` pre-paginated)
is shown a spine item a page, as Thorium shows it. `src/epub_xml.bats`
reads the OPF's layout (`opf_layout`), each itemref's own
(`itemref_layout_n`: `rendition:layout-pre-paginated` or
`-reflowable` outranks the book's) as a `rendition_layout`
(`Reflowable | PrePaginated`), kept with each chapter in `Chapter`, and
a page's viewport meta (`xhtml_viewport`: a `viewport`, its width and
height 1 to 10000, or `NoViewport`). The reader (`_layout`, `_is_fixed`)
renders a fixed page into a box (`page-box`, `_box_add`, the page's one
child; `_render_into` says which element a chapter's top-level nodes go
into, so its content nodes are numbered as ever), laid out as its
viewport (else the last fixed page's, in `_page_size`, as EPUB RS 3.3
§8.1.2 allows; else the view's) and scaled with CSS `zoom` to fit whole,
letter-boxed (`_fixed_fit`, at every layout, so a resize fits it
again). The page (class `caf fixed`) is then the whole reader view, the
bars over it as over a reflowed page, the box centred in it, so taps
and drags beside a letter-boxed page turn it. It is one page, never
scrolled or in columns, its images fit it (`100cqw`, `100cqh`), and it
is set horizontally whatever the book's `_vertical` (`_writing`). The indicator counts spine items ("page 5 of
24 in book"). It is not restyled: only the theme and what the reader
does (taps, keys, reading aloud, the screen) are offered, with Columns,
which say its spreads (`_rows_set`).
The book's own CSS is dropped as for every book, so text a publisher
placed over art shows in flow.

Fixed pages are shown two at a time, a spread, as the Columns setting
says (Two always, One never) and at Auto as the book's
`rendition:spread` says (`rendition_spread`: `SpreadNone` never,
`SpreadBoth` always, `SpreadLandscape` and `SpreadAuto` when the view
is wider than tall, as Apple Books and Thorium do; `_spreads_wanted`).
Each itemref's `page-spread-*` is kept with its chapter (`page_spread`),
and `book_chapter_slots` places the pages as Apple Books does: a page
takes the side it asks for, else the side after the page before it,
and the first fixed page (or the first after a reflowed one) is alone
on the right (on the left read right to left); a centred page is
alone. `_shape_of` makes the page shown a `spread_shape`: `Single`,
`AloneLeft` or `AloneRight` (the other side blank), or `WithNext` or
`WithPrevious` (a spread of two). Its facing page is rendered into the
other box (`facing-box`, `_facing_open`), its content nodes going on
from the page's, after the page is shown; it cannot be selected
(`.facing`), so what is marked or read aloud is the page's. The two
boxes meet in the middle with no gap (EPUB RS 3.3), each fitted to its
half. A turn moves a spread at a time, and a layout that wants spreads
otherwise (a turned device, the Columns setting) shows the page again.

The back button a jump leaves (to the place jumped from) never stays
up: `ps_cell` in `src/reader.bats` holds the positions it offers, and
its only shown state, `PsShown`, needs a proof `TIMED(g)` that a timeout
numbered g is armed; `_ps_put`, the only code that shows or hides the
button, shows it exactly in that state. `TIMED`'s constructor is local to
`_timed_arm`, which arms the timer, so no other code can make one, and a
proof for one number does not type-check as another's. When the timeout
runs (10 s, `BACK_SHOWN`) the button goes but the positions are kept
(`PsKept`, #384: Apple Books reaches "previous location" from a control
that does not expire, KOReader keeps it until used), unless a later jump
has armed a later timeout. It goes sooner when a page is turned or the
bars are brought up (`_chrome_set`), also keeping them; Contents shows
"Back to <chapter> · page N" (`contents-back`) while a position is kept,
and pressing it pops it as the button does. Opening or closing a book
forgets them (`reader_stack_clear`). The first-book hint (#384) says
both gestures (`gesture`: `TapSides | TapMiddle`, `gesture_hint`), lies
in the band the text keeps clear of (`hint_band`: `TopBand | BottomBand`,
no centre case) and is up for 8 s after the bars first hide.
`tests/static` holds code that must not type-check (a forged `TIMED`,
another timeout's proof, the button with nothing to offer), and code
that must (`_back_offer`); CI runs `tests/static/run.sh`.

A static fixture is a snippet put into one module (`file`, before the
line `before`), and it knows what proof fails when it is built. A reject
fixture's `expect` names the function of its snippet, the line of the
snippet patsopt reports, and patsopt's error word for word (the
constraint left unsolved, the case left out, the type that does not
match); `tests/static/expect.py` passes it only when that is the one
error of the check, in that module, at that line, inside that function.
A substring that another error could also hold is not enough. An accept
fixture must check. Each fixture is put into the app checked whole in
the same job, so only its module is checked again, and what depends on
it when its `#pub` declarations change (bats keeps a module's C while
the `.sats` it staloads has only moved, and each of check's passes keeps
a cache of its own, bats-lang/bats#243), and a reject fixture stops at
its error: a fixture costs about what its snippet changes.

CI runs the static tests and the e2e suite in groups side by side
(`tests/groups.json`), the e2e groups on the app built once (the `build`
job). Every spec and every static fixture is in exactly one group, or
`scripts/ci-groups.py` fails the run: a new one is put in a group, by
area and balanced by time. The `check` job, which main's branch
protection requires, passes only when every group did.

The tests that measure time (the describes of `pathological.spec.js` and
`page-turn.spec.js` with a budget) are tagged `@serial`, and `gen-pwa
test` runs them alone on one worker before the rest of the group, which
then run on half the cores (#499): a budget that is measured beside
another worker's load is flaky, and a flaky budget is relaxed until it
stops catching anything. The two specs are still the `perf` group alone,
and no spec that loads the machine joins it (`stall-capture.spec.js`
spins a page on purpose), for balance: measured on 4 cores (CI's), their
`@serial` tests take 11.0 minutes alone and the rest 1.9 on two workers
(about 3 on one, as the group ran before), so the serial part would
lengthen any group it joined by 11 minutes. Running the rest on two
workers found a test that clicked a bar's control after `showChrome` by
itself, which the bars' 5 s timeout can hide on a loaded machine: a
control is clicked with `clickControl`, which shows the bars and clicks
together until the click lands.
A budget keeps headroom over what a loaded runner has been seen to give
(a turn's animated time against its instant time was 1.27 times once, on
CI, against a quarter's slack), and still fails a turn that costs twice
as much.

Each group runs every project of `playwright.config.js`: `desktop` and
`mobile-portrait` every spec, `narrow` (320 px, WCAG's reflow width),
`mobile-landscape`, `tablet` and `wide` the layout specs, and `android`
every spec (#295): a Pixel-class phone (412 x 915 at 2.625, touch, the
WebView's user agent), its status bar and gesture navigation as the
safe area's insets, and the app's Capacitor played in the page
(`androidApp` in `e2e/fixtures.js`), so bridge takes its Android branch.
`scripts/ci-groups.py` fails the run when the `android` project is
missing or narrowed (a testMatch, testIgnore or grep, in it or over the
configuration, or a --project or --grep on CI's run); a spec that cannot
apply on Android skips itself there, saying why (`test.skip`).
`e2e/icons.spec.js` checks that every icon (a Private Use Area
character) is drawn by the icon face, by drawing it on a canvas, so it
does not hang on the machine's fonts.

Listeners are registered only as one table (`regs` in `src/ui.bats`),
each with its position as its id, so no two share an id, and the
table's length, in its type, is at most 127: the bridge's last slot
(of 128) is the media query listener's (`ui_media_listener`), which
shares the bridge's table, so no listener of the table can take it.
The platform's typed listeners take their slots in the same table:
full screen's (`RFullscreen`), the app's system bars' (`RSystemBars`),
speech's (`RSpeech`), the install
offer's (`RInstallOffer`), the app's links' (`RAppLink`) and the page's
fonts' (`RFonts`), each given its event as bridge decodes it. A
chapter's pages are counted again as it is shown, for 3 s (`_settle`),
and whenever a load of the page's fonts ends (`RFonts`, bridge's
`listen_fonts_loaded`): the reading face can arrive after those 3 s,
and the count made with its fallback would stay. A layout made anew
(those counts, a resize, the type) shows the page of the node the
place is kept by (`_anchor_kept`: the one a jump took the reader to,
else the one at the top of the page they last moved to) and keeps that
node until the reader moves, never the node at the top of the page it
then shows, which can begin before it, so layouts one after another do
not move the place back (quire#305).

The place also survives the app's bars shown or hidden (quire#356). The
app is drawn edge to edge, so full screen changes the reading area
only through `env(safe-area-inset-*)` (the page's paddings): the window
does not resize and no `resize` came, so the chapter was not laid out
again and the page, scrolled by whole pages of the old area, showed text
two paragraphs on. The activity reports the bars at each window insets
dispatch (`batsNative.systemBars`, `RSystemBars`), and when what is
shown changes (`screen_system_bars_changed` answers whether) the
chapter is laid out again once the area settles (`_relayout_for_bars`,
`reader_relayout_for_bars`, which does not hide bars the system brought
back: that is a page turned, not an area changed). What a place is: a
content node and the page that holds it, as an EPUB CFI (Kobo, Apple
Books, Calibre) or a Readium locator names a text position and not a
page, so the paragraph the reader was at stays on the page shown
whichever way the area changes (`e2e/layout.spec.js`, "the place stays
when the reading area changes"); where the page breaks fall is the
layout's, as in Kindle and Books.
Scrolled, a hand scroll within one screenful is a move too (#485): the
place is the node now at the top of what is seen (`reader_scrolled`
clears the node a restore keeps and records the position, when the page
is not where `_show_page_down` last put it: `_scroll_set`), and a layout
made anew shows that node at the top, snapping to the old screen's top
only for the first drawn node to start at or below it (`_show_target`).
`e2e/stability.spec.js` scrolls a part of a screenful, swaps the window
twice and expects the same paragraph on top.

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

## Pathological structure (#423)

KOReader's notes on slow books name the shapes `e2e/pathological.spec.js`
walks (`e2e/pathological-books.js`, each checked by epubcheck): a table
cell of many pages, a single-file book of 5 MB, a thousand nested
elements, ten thousand short paragraphs, a megabyte without a space. The
spec measures a pathological chapter against a plain one of the same
length, in the same page, so a slower machine slows both. What it found:

* **A wide chapter was never shown.** xml-tree's `_parse_nodes` cons-es a
  node onto the list that a call made after it parses, so the stack grows
  by a frame per sibling. Wasm's stack is 1 MiB (the compiler's
  `stack-size`, no package or project sets it), and a body of about 9000
  paragraphs (8800 shows) ran out of it: the overflow wrote into the
  module's data, raised nothing, and the reader stayed blank with no
  banner and no console error. The same 9000 paragraphs in groups of 100
  divs show, so it is the width of one sibling list, not the node count.
  `src/xhtml_parse.bats` is xml-tree's parser copied with one change: a
  list of siblings is collected last first in a tail-recursive loop and
  put in order by another, so the stack holds the document's depth, not
  its width (a thousand nested elements was already fine). It builds
  xml-tree's own trees (freed by its `free_nodes`), and every chapter
  parse (render, facing page, search, note, read aloud) uses it; the OPF
  and SMIL, which are small, still use xml-tree's. Tested with 9000 and
  30,000 paragraphs, not proved (the stack's size is not in the types).
  The change belongs upstream: bats-lang/xml-tree should parse siblings by
  a loop, and this file then goes. Searched for a limit to say in the
  banner instead, and rejected it: truncating a chapter at a guessed
  count would have hidden text that shows today.
* **A run with no break opportunity was clipped.** `.caf` has
  `overflow-wrap: break-word`. By research: MDN says `break-word` and
  `anywhere` break a run the same way, and differ only in that `anywhere`
  counts the breaks in min-content sizes. `anywhere` was tried first and
  `e2e/wide.spec.js` failed: a table whose cell holds a long run no longer
  made the table wider than the column, so it did not scroll inside its
  own container (#413) but wrapped. `break-word` breaks the run at the
  column's width and leaves a table as wide as its content. (No ebook
  reader's stylesheet was found stating its choice; Readium CSS was
  searched for, with no result.)
* **A page turn cost time in proportion to the chapter.** Profiled with a
  DevTools trace (not guessed) on the 5 MB chapter: a key took 200 to
  280 ms in the page's script, and the hit test was not the cost.
  `#bats-root:has(...) .banner`: Blink re-evaluates a `:has()` whose
  subject is an ancestor of every change over the subject's whole subtree,
  and `#bats-root` holds the chapter's 30,000 nodes, so every change to the
  page's chrome (the indicator's text, the footer's) forced a 16 to 27 ms
  style recalculation at the next measure, four times a turn. The banner's
  place is now a class the views set (`banner_place_set` in
  `src/notice.bats`: `BannerAtTop`, `BannerInLibrary`, `BannerUnderBars`,
  set by `_library_shown`, `_show_reader`, `_chrome_set`, `_chrome_set_off`),
  and the stylesheet keys on `.banner.in-library` and `.banner.under-bars`.
  Every later state of the same kind is an attribute set by the layer
  (`data-below`, `data-menu`, `data-veil`), never a `:has()` on the root:
  `tests/static/has_root.py` fails one (#538; #556's two rules were found
  by it when its queue run met them).
  The two remaining `:has()` rules have small subjects (a button, a
  settings row). A key on the 5 MB chapter went from 206 to 276 ms to 21 to
  31 ms of script. What is left of a turn on a chapter of thousands of
  boxes is the browser's: the hover hit test it makes after the scroll
  (190 ms for 10,000 one-line paragraphs, in the PrePaint of the next
  frame), and, when the sheet of the page being left is slid, the
  prepaint of its copy (170 ms more for the same chapter; a megabyte
  without a space, 100 ms more). Neither is the app's to make cheaper
  (`visibility` on the idle sheet is inherited, so moving it, or hiding it
  another way, was tried and costs the same or breaks
  `e2e/page-turn.spec.js`'s check that an idle sheet is not visible), so a
  chapter too big to slide a copy of turns at once, as under
  prefers-reduced-motion (`_chapter_heavy` in `src/reader.bats`: 6000
  content nodes or 600 KB, between the 300 KB chapter of 2100 nodes that
  page-turn.spec.js measures, which stays animated, and the first that is
  late). That is a choice of this project, from these measurements and
  from RAIL's 100 ms to respond (a first frame that late is not an
  animation); the turn is no longer than the reader's own key. Such a chapter
  keeps no copy made ahead either (`_copy_stale`): the clone of its whole DOM
  was 3 s of script for 30,000 nodes, in which the page did not answer; a
  drag, which does lay a copy, makes one then.
* **Close does not wait for the layout, and the layout can outlast a check
  (#522).** Choosing Two on the megabyte word and pressing Escape: the
  dialog's `data-hide` flips within milliseconds of the key (measured with a
  MutationObserver and a longtask observer, then with Chrome's CPU throttled
  25 times: the flip came 6 ms before a single 15.7 s task, the columns' layout,
  which the click made dirty and Chrome does in the next frame). Playwright's
  `toBeHidden` needs the page laid out to say so, so on a loaded runner it
  waited behind that task and failed at 15 s twice (#518, #533). So the
  app's part is asserted by its attribute (`arrange`), the dialog gone from the
  screen waits as long as the layout it follows (`slow`), and a test dispatches
  the click on Two and the Escape in one script, so no frame lies between them,
  and finds the dialog already hidden. The 15 s is not raised: the hide is
  checked with no layout in the way.
* **The anchor is found by search, not by hit test.** `_anchor_now` took the
  element at a point (`elementFromPoint`, then stepping 40 px at a time),
  and then the first of the next 40 nodes to start on the page. A hit test
  in a multicolumn chapter costs in proportion to the fragments it walks
  (and forced the layout the page was waiting on). Content nodes are
  numbered in document order and the text flows in it, so where they start
  grows with the number (down the page, across it, or back across it, as
  `_page_axis` says): `_first_on_or_after` is a binary search of the nodes
  for the first that does not start before the page (undrawn ones,
  a blank between blocks or a ruby's `rp`, are stepped over, at most 64 in
  a row), by `getBoundingClientRect`, which costs 2 microseconds on a
  clean layout in a 5 MB chapter. When no node starts on the page (it is
  wholly inside one carried over), the anchor is the last drawn node
  before the first that starts after it, as the hit test found one inside
  the carried-over node. A fixed page keeps the hit test (`_anchor_hit`):
  it is one spine item, its nodes are few, and a spread's facing page is
  numbered after it, so the numbers are not in order across the two. The
  place's semantics are unchanged (the kept anchor, a layout that does not
  move the place): only how the first node is found. `_show_page_down`
  asks once per page shown (`_record_position` used to ask twice).
* **A giant run of text was drawn in time that grows with the square of
  its columns (the megabyte word, 17 s to open on a phone).** Found by
  profiling and then by taking Chrome alone: the app's own code was
  negligible (a CPU profile of the click on Two: the wasm under 50 ms, 16.9
  s in one PrePaint), and a page of plain HTML with the same text, columns
  and window did the same (30 px text, 1 MB, two columns: 3361 pages, 18 s
  a frame, 0.7 s of it layout; 2017 pages 5.9 s; 1113 pages 1.7 s). The
  cost is Chrome's per inline run across columns: one paragraph of 1 MB is
  one inline formatting context spread over thousands of fragments, and a
  frame is quadratic in them. The same text as 16 paragraphs of 64 KiB took
  1.1 s, as 64 of 16 KiB 0.8 s; a real paragraph of 1 MB with spaces took
  88 s as one. No CSS tried (contain, content-visibility, will-change,
  translateZ, overflow) changed it. So the app does not give Chrome a run
  longer than a piece: the pieces `_text_spans` already cut a text of 64
  KiB or more into (a text op's limit) are class `run`, shown as blocks
  (`.caf .run`), and are cut after the last white space in their last 512
  bytes (`cut_find`, src/cut.bats; a run with no white space is cut at a character, as
  before). Complexity: the frame of a run of n columns was O(n squared)
  and is O(n) in the number of pieces; opening the megabyte word on a
  390 px phone went from 17 s (Two) to 1.5 s, and the opening to 1 s. A
  text node over 64 KiB in mixed content breaks its line at each piece (a
  paragraph break appearing in a 64 KiB run is the price; search counts
  pieces with the same `cut_find`, so its node numbers agree). A stored
  note or highlight in such a text is a piece's content node and a UTF-16
  offset in that piece's text (bridge's `get_selection_range` gives offsets
  into the text of the element with the id, which is the piece), and the cut
  is a function of the text alone, so a place stored by this build is found
  exactly by it again, after a reload, a restored backup and a sync
  (`e2e/giant-text-highlights.spec.js`: highlights at the end of a piece, at
  the start of the next, across a cut and inside a third, paged, scrolled and
  in two columns, with accents and an emoji in the words; a last test restores
  places stored by this build and they must paint the same words, so a
  changed cut fails there). The cut is part of the format of a stored place:
  changing `cut_find` moves the places stored in the pieces after the first
  of a text over 64 KiB (the first starts where the text does) and needs a
  version of the annotations' record to translate by. A place stored by a
  build before #423 (pieces cut at a character, not at white space) is read
  against these pieces and may land up to 512 bytes per piece from where it
  was made, in the second and later pieces of such a text; no version of the
  record says which cut a place was stored with. Making places independent
  of the cut (the pieces as `data-part` parts of one content node, as the
  digits of vertical text are) was weighed and not taken: one content node
  per text would make the reading place, a content node and the page that
  holds it, as coarse as the whole text (a megabyte paragraph one place), and
  search and read aloud would need the UTF-16 length of the pieces before
  one for their offsets (#470). The open budget the spec
  asserts (`expectOpenBudget`): the time from the card's tap to the
  chapter's indicator, and from the choice of Two, Scroll or One to its
  page indicator, is at most 3 times Chrome's own time to lay out and
  draw a copy of that DOM in that window and arrangement (`bareFrameMs`:
  the copy is put beside the page, laid out, drawn for two frames and
  removed, so a slow runner is slow for both), plus 1 s for what is not
  layout. Measured (phone, this machine): the megabyte word opens in 1.0
  s against 0.8, Two in 1.5 against 1.8, 10,000 paragraphs open in 2.3
  against 1.7. No timeout was raised to get there.
* **The cut is a function of the text's cells, proved (#568).** The three
  walks of a chapter's text (render's `_text_spans`, search's `_scan_text`,
  read aloud's `_runs_text`, and the blank or math text each skips with
  `_skip_spans` and `_text_count`) number a text's pieces by one rule,
  `src/cut.bats`, stated over the cells of the array the text is read from
  (array's `cborrow`, whose `cborrow_get` gives `NTH(cs, i, v)` with each
  byte): `BREAKBACK(cs, offset, at, floor, back)` (the cut after the last
  space, tab or line feed at or before a cell, looking back no further than
  a floor), `CUTC(cs, offset, text_len, cut)` (the first piece's length:
  after that white space in the last 512 bytes, else the longest prefix
  that ends before a UTF-8 character's start) and `PIECES(cs, offset,
  text_len, count)` (the text is count pieces, each cut off by `CUTC`).
  Each constructor takes the `NTH` of the cells it was decided from, so
  none is made over cells other than the ones read
  (`tests/static/reject/cut-claimed-over-other-cells`,
  `cut-break-after-a-byte-that-is-not-white`, `cut-break-at-another-cell`,
  `pieces-counted-over-other-cells`, `pieces-forged-cut`), and each is
  functional (`breakback_functional`, `cutc_functional`,
  `pieces_functional`, by induction, with array's `nth_functional`): two
  cuts, or two counts, of the same cells and offset are equal
  (`reject/cut-two-lengths-of-the-same-cells`,
  `pieces-two-counts-of-the-same-cells`, `accept/cut-same-cells-same-count`).
  `cut_find` and `pieces_find` read the cells and return those proofs; the
  walkers take `bytes: !cborrow(l, n, cs)` beside the plain `data: !borrow`,
  and an `<img>`'s over-long alt text is cut by `cut_find` too, so no walk
  steps by another rule (the 65533 step of #568's first part is gone). A
  chapter's piece is lent for this at each load (render, facing page,
  search, the annotations' node count, read aloud): array's `barr_of_arrx`
  gives the cells and keeps the piece's owner, `barr_freeze` the
  `cfrozen`/`cborrow`, `cborrow_view` (array 2026.10.15.3267, array#47) the
  plain borrow of the same bytes that `xhtml_parse`, `_load_images` and the
  page read through, counted in the freeze so `barr_thaw` is refused while
  the view is out (`reject/cut-view-out-at-thaw`), and the view is given
  back, then the cells, before the thaw and `barr_to_arrx`
  (`accept/cut-found-from-the-cells`). `_utf8_start` no longer calls arith's
  `band`: a byte starts a character when it is under 128 or at least 192.
  **Proved**: that the cut, and the count of pieces, that render, search and
  read aloud take are the one relation of the cells they walk, and that two
  walks over the same cells, or the same cborrow, cannot get two. **Tested,
  not proved**: that the three walks read the same bytes. Render, search and
  read aloud each decode the chapter from the compressed entry on their own
  (separate pieces, so separate existential cells `cs`), and nothing in the
  types says that inflate, the CRC check and `_text_of_content` give the same
  bytes each time: that needs inflate (the zip package) and the text
  conversion (`src/text_encoding.bats`) as proved relations of their input
  cells, with functional lemmas, which they are not yet. The proof is owed
  (#608; no trusted primitive is needed or allowed), and until it is proved
  it is tested (`e2e/giant-text-highlights.spec.js`,
  `e2e/pathological.spec.js`, `e2e/search.spec.js`). **Trusted** (array's, tested there): the unsafe
  core of `barr_of_arrx`, `cborrow_view` (an identity on the pointer) and
  `cborrow_get` (reads the byte it says). The functional lemmas and the
  relations are audited by the mutation check (`mutation_check.py`, GMP):
  every statement of `breakback_functional`, `cutc_functional` and
  `pieces_functional` made false is rejected; the two lemmas `white_not_white`
  and `starts_not_continues`, which prove `1 == 0` from a pair that cannot
  both hold (a byte that is white space and is not; one that starts a
  character and continues one), are accepted when mutated to any other
  statement, as every statement is true of an impossible pair, and each of
  their premises is satisfiable alone. `cut.bats` checks in 2 s.
* **The spec's long chapters run without Playwright's trace and
  screenshots** (`heavy` in `e2e/pathological.spec.js`): its snapshotter
  walks every node at every action, 2 to 3 s on a chapter of 30,000, which
  is the harness's cost and made the steps time out. The stall watch
  stays on. `e2e/page-margins.js` now clips a line to the scroll
  containers inside the page (a table is one since #413): a line a table
  holds past its own scrollport is not drawn, so it is not under the
  footer.
* **A table is one box on one page** (#413), so a cell of 200 paragraphs no
  longer spreads over a hundred pages. The spec's old assertion, that the
  chapter with the cell fills about as many pages as the same text in
  plain paragraphs, was true only while a cell was one unbreakable box
  that cut off all but its first column; it is now that the chapter is
  fewer pages than the plain one and the cell scrolls inside its table
  (the table's last paragraph is reached by scrolling it). The threshold
  was wrong, not the code.
## Touch selection (#428)

`e2e/touch-selection.spec.js` plays a long press (Chromium's touch
emulation of the mouse), a handle drag (as the selection it makes: quire
draws no handles, the browser does), a selection across a column gap and
an image, the footnote popup, the toolbar's place, and a tap that ends a
selection. Its header holds the research; the decisions it led to:

* **A selection holds the page.** While text is selected, or was when
  the pointer went down on the page (`_press_selected`; Chrome clears the
  selection on the press), a pan does nothing and a commit puts the page
  back (`_selection_holds`, `_on_gestures`): the finger that drags the
  selection's handles, or one put down on it, never turns the page.
* **A tap that began on a selection only ends it.** `_press_selected` is
  recorded at `pointerdown` on the page; the click that follows turns
  nothing and brings up no bars (the platform's rule for text selection:
  a tap outside clears it and does nothing else; Apple Books, Play Books
  and the Kindle document nothing different).
* **The toolbar is for the chapter's text.** It shows only when the
  selection starts in a content node of the page (`annot_selection_in_page`),
  so text selected in the footnote popup has none: Highlight and Note
  cannot work there, and a control that cannot work is not shown.
* **The toolbar lies over neither the text nor the handles.** It is
  placed from the selection's rectangle on every `selectionchange`
  (`_toolbar_place`, `ui_toolbar_at`, which writes only two numbers as
  the custom properties `--seltb-top` and `--seltb-height`): above the
  selection with an 8 px gap (Flutter's `TextSelectionToolbar` anchors
  above and falls below only where there is no room), else below the end
  handle with 20 px clearance (Firefox for Android moves its floating
  toolbar 20dp off the selection so it does not lie over the bottom
  handles). The stylesheet's `.seltb` clamps the top to the window and the
  safe area. Above is chosen only where it clears the safe area's top: wasm
  cannot read the inset, so a hidden probe (`selection-toolbar-floor`,
  `.seltbfloor`) is as tall as `max(8px, var(--safe-top))` and is measured.
* **Edge of the page.** A selection stops at the page: the page does not
  turn while a handle is held at its edge (Moon+ Reader scrolls on, Kindle
  and Google Books reportedly flip; nothing found documents Apple Books or
  Play Books; a quire page is a CSS column and a selection is one range, so
  a highlight across two pages is two highlights).
* **Tapping a highlight selects it** (`annot_tap_select`, the page's
  click in `src/bin/quire.bats`; bridge's `select_range`, `clear_selection`
  and `selection_available`). A tap between the sides' zones (the side
  zones keep turning the page) finds the highlight of the chapter shown
  that holds the tapped point (the tapped content node and the caret's
  offset there, `caret_position_from_point`), makes its range the selection,
  so the one selection toolbar is up with it, and remembers it by its
  chapter, start node and offset (never by index, which an insertion
  moves). Research: Apple Books and the Kindle apps show a highlight's menu
  on a tap on it (Apple Books: idownloadblog.com/2020/01/22/highlights-notes-apple-books-app/;
  Kindle: tomsguide.com/how-to/how-to-highlight-text-and-make-notes-on-your-kindle);
  a Kobo offers handles on the highlight, which its users call terrible,
  since they will not move while the menu is up
  (mobileread.com/forums/showthread.php?p=3803381). Quire has one toolbar,
  so the tap makes the highlight the selection and the handles are the
  browser's. Highlight, Orange and Underline then replace that annotation's
  range when the selection still overlaps it (else the selection is a new
  highlight, as when a handle was taken elsewhere): `_reshape` deletes and
  adds, so sync passes on a deletion and a new annotation, and the note is
  kept; `undo_offer(HighlightRangeChanged())` puts the old range, its text
  and the kind back (found by the range it has by then). Note on a tapped
  highlight changes the range the same way and opens that highlight's note,
  which cancelling does not delete. The remembered highlight is let go when
  the selection ends. After Highlight, Orange and Underline the selection is
  cleared (`annot_selection_end`), so the text is not left selected under
  the page. A `select_range` that is refused or finds no element is said
  (`HighlightNotSelected`), and a selection that cannot be cleared too
  (`SelectionNotEnded`): every constructor of both atoms is matched.

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
