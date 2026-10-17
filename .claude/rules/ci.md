---
paths:
  - .github/**
  - scripts/**
  - tests/**
  - bats.lock
  - bats.toml
  - package.json
  - package-lock.json
  - playwright.config.js
---

# Quire CI and its pipeline

## Pipeline and tooling improvements belong in bats or pwa

Anything a second app would copy is built where the apps share it, and
quire calls it: the compiler's build, cache and fixture runner, and the
setup of the toolchain, are bats's (bats-lang/bats); the Android project
and its release, test running (Playwright, its install and browsers), the
emulator job and the pages beside the app are pwa's (bats-lang/pwa). Quire's
own CI holds what is about quire: its specs and fixtures, which job runs
which (`tests/groups.json`), its books and its proofs. Before a workflow or
script of quire is changed, ask whether an alarm clock built the same way
would copy the change; if it would, the change is a ticket in bats or pwa
first (quire#623 is the list of what already is one), and quire's change is
only the call.

A stopgap in quire is allowed only when waiting would cost more than the
move (a flake that removes a merge queue entry each time it happens), and
then the ticket that moves it is written first, the stopgap says so in its
comment, and it is deleted when the move lands (quire#635's retries and
cache, moved by quire#637). A stopgap with no ticket for its move is not a
fix.

**We do not write shell scripts (or any non-bats code of our own) unless
all other avenues are exhausted.** We self-host in bats, implement in
bats, build tooling in bats; dependencies on other tools are fine; only
what is impossible in bats (like getting bats to run) is not bats. A PR
that adds non-bats code of ours names the avenue it exhausted (quire#646).

## CI is pinned

Every input to CI is pinned in the source (#203), so a commit that
passes keeps passing: the packages by the committed `bats.lock`, the
compiler by its commit in `.github/bats-version`, and pwa's Android
workflow by its commit (`android.yml@<sha>` in `check.yml`). CI never
runs `bats lock`: `bats check` and `bats build` fetch exactly the locked
versions, and fail when a locked one is missing or the lock does not
match the project (a package used but not locked, or locked but not
used).

The runner label is pinned too (#667): every job runs on `ubuntu-24.04`,
written in each job's `runs-on` in `.github/workflows` (quire has no
reusable workflow of its own to write it once in). `ubuntu-latest` is not
used, since it moves with GitHub's default: the runner-images README says
`ubuntu-latest` is `ubuntu-24.04` today. The label moves by hand, in a PR
of its own, when GitHub announces its successor (as bridge's CLAUDE.md
says); the build cache's key names it (`runner-image` in
`.github/actions/build-cache`, passed by each call), so that move starts a
new cache.

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
* Staleness. A build/ records what made it (#622, bats-lang/bats#273):
  `build/.bats_stamp` holds the bats's own inputs' digest, patsopt's
  toolchain, the C compiler's version, the flags and the target, and bats
  drops a build/ whose stamp is not the one it would write, so the key does
  not name the compiler pin, the ATS2 pin or the runner image any more (they
  were `.github/bats-version`, the ATS2 pin and the image). It names
  `bats.lock`, `bats.toml`, the runner label (`runner-image`, #667, passed by
  each call: the label the job's `runs-on` writes), the system and
  architecture, which the stamp does not cover, and the commit of bats's setup action (ATS2 and the compiler's
  build are in it; read from the workflows by `.github/actions/build-cache`,
  so a workflow edit that leaves the pin alone keeps the cache). The sources are the key's end, so an exact hit is the same
  sources, and a prefix hit is the incremental build the compiler does on a
  developer's machine: a changed module is re-emitted by its hash (its
  `.dats` is then newer than its C), a changed `.sats` rebuilds every
  module that staloads it. A cache is saved only by a job that passed
  (`actions/cache` saves on success only), so it holds no failed build, and a
  module that failed to emit has an empty `.src` and is never fresh. The
  residual risk is a bug of that incremental logic, so main never restores:
  a push to main (and a dispatched relock, and the nightly run) builds and
  checks from nothing, then (the push) saves for the pull requests and the
  queue (GitHub gives a pull request and a merge group its base branch's
  caches, and a pull request's own are readable only by that pull request:
  same repository, no cross-fork writes). The required check on a pull
  request and the merge queue's group is incremental (#586: the queue's group
  was cold at first, 13 minutes of build before the e2e jobs could start, in
  a 60-minute window; by decision of 2026-10-15 it restores main's cache,
  its build job then taking about 3), main's is cold, so a stale hit that
  passes the queue shows on main at the latest, in the push run that follows
  the merge (and in the nightly run `check.yml` makes of main from nothing,
  whose runner image and packages are the day's).
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

The static groups were rebalanced from measured times (#618). Measured on the
cold run of main's push of b88d218 (run 38895874813; `ok accept/<name> (N s)`
lines of each job's log): every group pays about 8.6 minutes (set-up and the
app's cold check) and then its members; a reject costs 17 to 29 s (one in
`sheet-scrolls-over-share` 128 s), an accept 81 to 89 s (`sheet-scrolls-most`
179 s), `solver` 3.7 minutes and `checkers` 25 s. Members: 64.3 minutes of
fixtures and 4.1 of `solver` and `checkers`, in three groups: `accepts`
43.0 minutes wall (34.1 of members), `app` 28.6, `accepts-data` 24.1. The
same members on a pull request with the build cache (run 38893313385) took
0.78 of that. Six groups of about 11.4 minutes each (`accepts` 11.3,
`accepts-reader` 11.3, `rejects` 11.4, `app` 11.2, `accepts-data` 10.9,
`rest` 12.2 minutes of members, by those cold times) put the cold critical
path at about 8.6 + 12.2 = 21 minutes, from 43. Six, not five, because the
issue asks for about 12 minutes of members (five would be 13.7); each group
costs about 9 minutes of a runner for its check. The new numbers are to be
read from the first run of this change.

What happened on 2026-10-15, and the rules it gave:

* Five entries at once (#609, #611, #612, #613, #616) wanted more runners than
  the pool has, so groups finished after their 60 minutes, and each removal
  made GitHub rebuild the groups behind it and leave the earlier runs
  `queued`: six stale runs, each with a dozen jobs, kept the pool full, so the
  next entries timed out too. Nothing merged for 3.5 hours.
* **At most two entries in the queue at a time** (at the current settings);
  the next goes in when one has merged or been removed.
* **Superseded runs are cancelled**: a queue run that is not the newest of its
  pull request is stale (GitHub does not cancel it). `check.yml` listens for
  the merge group's `destroyed` event (undocumented, delivered; community
  discussion 137976, Chapel's merge workflow) and cancels that group's run by
  its concurrency group (the queue ref), the destroyed run itself skipping
  every job (#586); `qsweep` still cancels the ones that slip through
  (`CANCELLED STALE QUEUE RUN`). `supersede.yml` (#620) covers the case the
  `destroyed` event does not: on each `checks_requested` it cancels the queued
  or running `check.yml` runs of the same pull request (its number from the
  queue ref `gh-readonly-queue/main/pr-N-<sha>`) whose commit is another, and
  which were created before the requested group's own run. A group with the
  same commit is kept, and so is a later one; a run of another pull request is
  never touched. Its one step is a few lines of `gh` and `jq` (the avenues:
  a concurrency key per pull request needs the number, which the expression
  language cannot take out of the ref; a job in `check.yml` queues for a runner
  like every other job; bats has no HTTP client). It holds `actions: write` and
  nothing else, and needs a runner, so under full pressure it waits its turn; the
  `destroyed` path needs none (its jobs are skipped). Read the pull request's timeline
  (`added_to_merge_queue`, `removed_from_merge_queue`) for where an entry is:
  `auto_merge` empty means enqueued or removed, not one or the other.
* A change that makes its own group longer than about 45 minutes does not
  wait in the queue's window: it is sharded first (the mutation check, #594:
  a change to the checker selects a smoke set, a change to the ATS2 pin all
  shards, none over about 25 minutes).
* Open (#586): the queue's own settings (how many groups build at once, the
  window) and balancing the static groups so that none is the long pole.

### Node's packages (#637)

The two jobs that use Node install it by pwa's `e2e-setup` action
(`bats-lang/pwa/.github/actions/e2e-setup@<commit>`, called by commit as
`android.yml` is, bats-lang/pwa#99): exactly `package-lock.json` by `npm ci`,
retried when the connection to the registry drops (one `ECONNRESET` in an e2e
job's `npm install` removed a merge queue entry after 35 minutes, #635),
npm's downloads cached on the lock, the Playwright version checked against
`playwright-minimum` (1.58), and the browsers in one directory cached on the
Playwright version. Quire holds no install logic of its own (CLAUDE.md,
"Pipeline and tooling improvements belong in bats or pwa").

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
  change to the solver, its pin (bats's setup action, a changed line in a workflow that names `bats-lang/bats/.github/actions/setup@`) or its fixtures
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
  bats's setup action) under it, so a runaway proof fails with its module named.

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

### Only the groups a change can affect run (#619)

A pull request that changed CLAUDE.md paid the whole check (the e2e groups,
14 to 18 minutes each, and the static groups). Now the `plan` job decides,
once, from the pull request's own diff (`git diff --no-renames` of the merge
checkout's first parent against it), which e2e groups and which static
*members* the change can affect (`scripts/ci-groups.py plan <base>`, the rule
in `scripts/affected.py`), prints the reason of every path in its summary and
hands the selection to the groups. A group with nothing selected is a job that
runs and ends after its first step, so it passes as itself and `check` is
unchanged (it prints the selection beside the results): not a job skipped
(`check` rejects a skipped job), and not a workflow path filter, which GitHub's
troubleshooting page for required status checks says leaves the check "Pending"
for ever ("Waiting for status to be reported") and tells not to use on a required
workflow. A job skipped by a condition reports Success there; the step-level
skip keeps one meaning for `check`: every job ran, or was shown unaffected.

* **The table** (`RULES` in `scripts/affected.py`, first match wins; a path no
  rule names selects everything, an empty diff too, a deletion under `e2e/`
  too). The CI's files (`check.yml`, the composite actions, `tests/groups.json`,
  `tests/static/run.sh`, `expect.py`, the two scripts), the pins (`bats.lock`,
  `bats.toml`, `.github/bats-version`, `repository-version`, `package*.json`,
  `playwright.config.js`), `src/`, `assets/` and `scripts/sync-clients.*`:
  everything. CLAUDE.md and the other notes, `ux-review/`, `reports/`, the
  workflows that are runs of their own (`deploy`, `mutation`, `relock`,
  `sync-*`), the build job's tests (`test/*.js`, `tests/codec`, `tests/css-size`,
  `tests/version`): nothing. `homepage/`: every e2e group, no static member.
  `test/fixtures/*.epub`: the specs that spell the name. `e2e/**.js`: the specs
  that reach it through `import`, `import()` or `require` (the books and helpers
  of one area select its specs and `epubcheck.spec.js`, which imports every
  books module), and `checkers` (they read `e2e/`); a module no spec reaches
  (`global-setup.js`) selects every spec; an asset (a font, an mp3, a JSON)
  selects the specs reaching a module that names it or its directory, else
  every spec. `tests/static/{accept,reject}/<name>/`: that fixture alone;
  `tests/static/*.py` and their fixture directories: `checkers`; `solver`: its
  member. A group is selected when one of its specs is (and runs all of them),
  a static group runs only the members selected, so a spec-only change runs
  one e2e group and the checkers (python, no compiler: `bats` is not set up
  for a group that selected nothing else), not the 60 fixtures and the app's
  check.
* **Soundness.** A skipped member's inputs are the base's, which was tested
  whole (main is checked cold on every push), and a merge queue's group, a
  push, the nightly run and a dispatch run every e2e and static group, so a
  mistake in the table can leave a pull request's feedback incomplete and
  cannot put a red change on main. The mutation groups keep their own rule
  (#594), asked with the group's base in the queue too. It fails closed: a
  path nothing names, a diff that cannot be read (the plan job is red then,
  and so is `check`), an empty diff. **Tested, not proved**
  (`tests/static/affected_test.py`, in `checkers`): the import graph on a tree
  built for it, `tests/static/affected/cases.json` on the real groups (docs
  only, a spec only, a books module, a fixture only, `src/` only, each CI file
  and pin, an unknown path, an empty diff, a deletion), that every spec and every
  fixture is selected by a change to itself, and that each rule that selects
  nothing of a kind is named by nothing that could read the path (the text of
  the e2e suite and `playwright.config.js` without their comments, the static
  checkers and the app's `staload`s; a scan with a reader in the home page's
  case, so it is not vacuous). What it cannot see: a spec that builds a path
  from pieces, or reads a file by a name no module spells.
* **By research** (the issue's comment): Nx marks every project affected when
  a lockfile changes ("a failsafe in case Nx misses a project", "the safest
  option but may result in unnecessary CI work"), maps files to projects by a
  graph and adds dependents; dorny/paths-filter detects changes against the pull
  request's base and leaves the selection to the workflow's outputs; Bazel's
  bazel-diff and Aspect's `cache diff` compare against a baseline and fail
  closed where the evidence is incomplete. Taken: a graph where one can be
  built (the e2e imports), a fail-closed default everywhere else.
* **Not done** (the follow-up of #619): the `build` and `android` jobs still
  run for every pull request (the build is cached, 3 minutes; `android` needs
  it), though a change that selects no e2e group needs neither, and the merge
  queue's group runs whole by decision, though the rule is sound there too
  (`plan <base> full` in `check.yml`'s plan job).
  The rule is Python in `scripts/` (#646): it runs in the plan job, before any
  compiler exists, which is what it saves building.

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
together until the click lands. Every raw pointer event of a spec (Playwright's mouse: a
click, move, press or wheel) goes through `rawMouse` in `e2e/helpers.js`,
which calls `releaseClick` first before a click, double click or move made
with no button held (quire#630: a timed-out locator click can leave
Playwright's interceptor, which swallows the next raw event). The guard is
by construction, not by a text search: `refuseRawMouse` in `e2e/fixtures.js`
replaces each test's page's own `mouse` with an object whose methods throw
("use rawMouse (e2e/helpers.js)"), and keeps the real mouse in helpers.js's
module-private map, which only `rawMouse` reads (`keepRealMouse` writes it), so
a raw call fails the test at run time, however it is written (a computed key,
an alias). Pages a spec makes itself are not guarded (a page's `mouse` there is
still the real one), and `scripts/*.mjs` probes are not e2e tests.
`releaseClick` is a trial hover, which moves the pointer to the viewport's
centre (Playwright 1.58.2 runs the move and only blocks the page from the
events), so it is never made between a move and the press, wheel or release
that depend on the pointer's place.
A budget keeps headroom over what a loaded runner has been seen to give
(a turn's animated time against its instant time was 1.27 times once, on
CI, against a quarter's slack), and still fails a turn that costs twice
as much.

A test never waits in real time for a moment of the app's own (#657; the
bars' 5 s, the back button's 10 s, a toast's 2 s, the Nextcloud sign-in's 3 s
poll). It installs the fake clock before the page opens (`page.clock.install()`;
time still flows as real time, and `runFor` adds to it, firing every timer
due, those a timer sets too; the network, IndexedDB and fonts are not the
clock's) and runs it to the moment: `expectMoment` (`e2e/helpers.js`)
asserts the thing is still there 1.5 s before the moment's end and gone 1.5 s
after (so a timer that never fires, or fires at once, fails; the first is
left out when a loaded machine has let the real flow carry the clock to within
0.5 s of the end), `runUntil` runs the clock on in steps until an answer that
comes in real time has come, and `settled` and `rested` in `e2e/relaunch.js`
do it for the relaunch and stability specs. What keeps real time, and says
why: the `@serial` budgets, the stall watch (Node's timers), media playback
and anything that waits for a font or the network.

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
