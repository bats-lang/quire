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

# Quire CI

## CI is pinned

The pins and the relock are in CLAUDE.md. Specifics:

* **The runner label** (#667): every job runs on `ubuntu-24.04`, written in each
  job's `runs-on` (quire has no reusable workflow to write it once in);
  `ubuntu-latest` moves with GitHub's default. The label moves by hand, in a PR of its own,
  when GitHub announces its successor. The build cache's key does not name it: bats stamps a
  `build/` with the C compiler's version, so a build made with another clang is dropped; an
  image's headers and libraries are not judged (bats#394, which holds bats#338 and bats#380; "Not judged yet" below) (#622).
* A publish never turns main red: until a lock names a package release, quire does not use
  it, so package releases publish first and the quire PR with the new lock follows.
* The relock moves a workflow pin with `RELOCK_TOKEN` (set in quire) and lists it as not
  moved without one. It moves each pin's `uses:` line, and with `pin-copies` in `relock.yml`
  (`bats-lang/pwa/.github/workflows/android.yml pwa-ref` and `.../play-release.yml pwa-ref`, area
  pwa-ref, #851) every `pwa-ref:` line of the files that call the pin to the same commit. `pwa-ref` repeats the pin because a reusable workflow
  cannot read its own ref, and pwa's workflows check pwa out at it; two copies of one commit
  drift at every relock unless one tool writes both (#821). So every `pwa-ref:` of `check.yml`
  equals the commit of its `android.yml@` pin and of its `play-release.yml@` pin (`play-internal`'s), and a `pwa-ref` line
  is a plain 40-hex value (a quoted or computed one is refused by the relock).
  `play-release.yml` is in `workflow-pins` and in `pin-copies` beside `android.yml`: both pins are
  pwa's main, so one relock moves them to one commit (before #851 it was called at its own commit,
  and its pwa-ref was `android.yml`'s, so the Play release ran two pwa commits). `e2e-setup` has
  no `pwa-ref` and is moved whole. The relock test that fails when pins of one repository drift is the `skew` job of repository-prototype's
  `relock-pins-test.yml` (keyword: relock heads, #494; `skew_check` on `tests/relock-pins/skew`: two pins of one
  repository and a `pwa-ref` copy for both, a stand-in `git` whose `ls-remote` answer differs at every call, one call
  required for each repository). The fixtures `tests/relock-pins/copies` test the rewrite of one pin's copies.

### The Android project's lock (keyword: android lock, #735)

`gen-pwa` writes the Android project with pwa's `create_android_locked`, whose `build-android.sh`
refuses to run without a `pnpm-lock.yaml` beside it and installs with `pnpm install
--frozen-lockfile`. The lock is quire's, `scripts/android/pnpm-lock.yaml`; `check.yml`'s `build`
job copies it to `dist/android/` after `gen-pwa`, and the `android` job's install fails when it
and the generated `package.json` disagree.

* **Moving it.** The plugin versions and commits come from bridge's table (the locked bridge
  version), so a PR that changes `bats.lock` or what `gen-pwa` writes into `package.json`
  regenerates the lock in the same PR, and runs the same CI. In a clean directory holding
  `dist/android/package.json` and a `pnpm-workspace.yaml` of `nodeLinker: hoisted`, with the pnpm
  of `dist/android/fetch-pnpm.sh`: `corepack pnpm@<its version> install --lockfile-only`. Commit the
  file it writes, unedited.

### The compiler's cache (#460, #622)

A pull request's jobs restore what bats kept in the newest earlier run
(`.github/actions/build-cache`, `actions/cache` pinned by commit) and save theirs once the
job passed. **The key is a locator, not a judgement.** It is `quire-<name>@<commit>` (a GitHub
cache is immutable, so each save needs a new key), and a restore takes the newest cache of the
name (`restore-keys` `quire-<name>@`; the `@` ends a name, so `static` never finds
`static-memo-rest@...`). It names no pin, no runner image, no hash of `bats.lock`, `bats.toml`
or the sources, and no number a developer bumps. What a restored `build/` is trusted for is
bats's judgement, by the mechanisms below.

* **What bats judges** (bats's CLAUDE.md and `.claude/rules/`, by mechanism):
  * `build/.bats_stamp` (`stamp.md`): bats's own inputs, patsopt's toolchain (the cksum listing
    of `bin/patsopt`, `prelude`, `libats`, `share`, `ccomp`), the C compiler's version, target
    and the environment clang reads, the flags, and the target and mode. A `build/` whose stamp
    differs is dropped at start, with a line saying what differs.
  * Each module in build mode (`build-freshness.md`): its `.bats` source by sha256 (`<dats>.src`),
    its closure key (the files patsopt read, as in check mode, `check-memo.md`), `build/.sats_changed`, and each object by the sha256 of its C and its
    profile.
  * Each module in check mode (`check-memo.md`): the files patsopt read for it, by size and
    sha256, and the names of the `.sats` and `.hats` under `build/`. Nothing is judged by time.
  * `bats_modules` (`lock.md`): a package copy is held only when its `.bats-version` stamp gives
    the locked version and archive sha256; a mismatch is fetched again. The closures above see
    the files of those packages.
  * Validation records (`validated.md`): keyed by each file's sha256, bats's inputs, the listing
    of `bats_modules`, the package's unsafe flag, and, for `#use` records, the file's bytes.
* **Not judged yet.** A change to one of these is not noticed by any stamp, key or record above,
  so a restored `build/` keeps what it made from the old one:
  * the system headers the C includes (bats#338, closed on 2026-10-20 as broken into bats#394, still open; none of the pieces is in the pin 2ea56e1 or in bats main d3c0791): the stamp's `cc` line is clang's version,
    target and environment, not the headers;
  * the system libraries that patsopt and the native link load, libgmp among them (the stamp's
    `patsopt` line is the cksum of `bin/patsopt`, not of the libraries it loads; bats#380, closed as broken into bats#394 the same way);
  * `bats.toml`: the rules name only its version and constraints (`lock.md`), its unsafe flag
    (validation records) and its dependencies (the listing of `bats_modules`); no rule says what
    else in it reaches the build (bats#381).
  A new runner image is judged only through what is listed here: clang's version, target and
  environment are stamped, its headers and libraries are not.
* **The fixtures' memo** (bats#303): `bats fixtures` keeps each static fixture's result, keyed by
  the toolchain's stamp, the snippet, the module with it in and every file patsopt reads for
  the module, and serves it only when all are as they were. `--cold` (run.sh's first argument,
  not `BATS_COLD`, which would also make every check cold) serves none and audits what it would
  have served. A snippet is never kept when it names `load` or `include` (it may read a file):
  `reject/export-unmatched` does, inside `ExportedByDownload`, so it runs in every restored job
  until the pin has bats#433 (bats#432).
* **Paths**: bats takes the checkout's path out of the C (bats#250), so a cache is valid
  anywhere. `QUIRE_STATIC_WORK` (CI: `$RUNNER_TEMP/quire-static`) is the directory
  `tests/static/run.sh` works in. It stays a fixed directory because the save step names the
  directory it keeps (`app/build`, `memo`), and a `mktemp` one has no name the save can know.
* **What is cached**: the `build` job caches `build/`. A static job caches the app's `build/`
  under the one name `static` (every group checks the same app) and its memo under
  `static-memo-<group>`. `check` and `build` never share a `build/` (check is mode 2 and 3,
  build 0 and 1).
* **Who restores**: a pull request and the merge queue's group (#586: restoring main's cache
  keeps its build job near 3 minutes, where cold it took 13 of a 60-minute window). Main's push,
  the nightly run and a dispatched relock restore nothing (the static jobs pass `--cold`), so
  every state of main is checked from nothing and is the base the pull requests' caches
  start from (GitHub gives a pull request and a merge group its base branch's caches; a pull
  request's own are readable only by it). A bug of bats's incremental logic that passes a PR
  therefore shows on main or in the nightly run at the latest. A cache is saved only by a job
  that passed.
* **Sharing**: jobs of one run start together, so none sees what another saves; the gain is from
  the previous build. A key is a name plus the commit and a save of it is immutable, so one name
  is saved by one job: the `static` build (every group restores it) only by the `app` group, and
  each group saves its own `static-memo-<group>`. Two jobs saving one key print
  `Cache save failed` (seen in the run of #750). Caches are immutable, 10 GB per repository, evicted
  by last access and after 7 days.
* **Research** (what others do): Swatinem/rust-cache, ccache, sccache and Bazel key on the
  inputs because the tool computes them. Keying on the lock is the common choice where the tool
  does not see a dependency's content; bats does, so quire's key does not.
* `BATS_CACHE_DIR` (bats#250) is not used in CI (#499): a PR's `build/` restore already holds
  what it would hit, cc still runs for every module on a cache of patsopt's C (a checked tree at
  another path took 229 s against 355 s cold), and it would only speed up main, which is cold on
  purpose.

### Static fixtures

A fixture is a snippet put into one module (`file`, before the line `before`) of a copy of the
app that was checked whole; `bats fixtures` runs it. A reject fixture's `expect` names the
function, the snippet line patsopt reports and patsopt's error word for word, and passes only when
that is the one error, in that module, at that line, inside that function; an accept must check.
A fixture whose memo entry is unchanged costs nothing, else about what its snippet changes (a
changed `#pub` declaration re-checks what depends on it).

### The solver fixtures written from the sources (keyword: solver fixtures, #837 to #841, pieces of #594)

`tests/static/solver.py` runs the files of `tests/static/solver/{accept,reject}/` with the machine's
patsopt (CI's is the infinite-precision build). A reject fixture has a `.expect` beside it, one block for
each error patsopt prints (`line`, `function`, the error with its variable numbers as `_`), and passes
only when the errors are exactly those; one without it fails. `solver.py --record` writes the files to
read and commit. patsopt reports the first unsolved constraint of a file only, so a fixture holds one
false claim.

* **Written from the text, not retyped.** `tests/static/proof_sources.py` reads the declarations of
  `src/*.bats` and of the locked packages' archives (array, arith, css: `PROVIDERS`) and writes a
  declaration with what it uses as a `.dats` needing the prelude only. Four generators use it, each
  with `--check` (run by `run.sh`'s `solver` member): it writes the fixtures again and fails when a
  committed one differs, is missing, or belongs to nothing, so a changed lemma, dataprop or constant
  changes its fixture or fails the check. Each writes the unchanged text to `accept/` as the control, so a
  rejection is the change's and not a typo of the copy.
  * `gen_luminance.py`: the `prval L_<rrggbb>` constants of `src/palette_proofs.bats` (60), the low
    and the high bound of each plus one.
  * `gen_lemmas.py`: the lemmas that conclude `FALSEP()`, an `EQFD`, a tuple or a bare existential, which
    `mutation_check.py` makes no mutant of: the lemma under a statement that is false (a guard shifted
    so that the premises can both hold, or the conclusion changed).
  * `gen_guards.py`: each atom of the guard of each dataprop constructor of `src/`, shifted by one
    in a probe that states the constructor under the weaker guard (`--list` prints them), a probe that the
    guards hold of some values (also css's HUE, SATNEAR and CONTRAST), and an accept control for each
    dataprop. FALSEP's constructor, whose two atoms exclude each other, is `falsep-made-at-*`.
  * `gen_vacuity.py`: the contexts `proofs_audit.py` flags (below).
* **The audit's verdicts** (`tests/static/proofs_audit_verdicts.txt`). Each HIGH row of
  `proofs_audit.py` over `src/` and over the locked packages (`--lock bats.lock --repository`) is
  keyed by scope, file, the declaration it is in and its kind, and names the reject fixtures that put a
  false claim in its context. `--fail-on high` fails for a HIGH row with no verdict, a fixture that is
  not there, or a malformed line, and `run.sh` runs it (`checkers`); `proofs_audit_test.py` injects
  the row. A relock that adds a HIGH row to a package fails there until its verdict is written: the
  verdict is the decision that the new context was looked at. A proof construct is a line that begins a proof
  and the lines it holds (a `prval` in a function body no longer makes the rest of the function
  proof). The reasons a fixture shows a context is not contradictory: a probe `[t == t + 1] void` in the
  branch (the division terms and the hypotheses are in the context), the proof's result one more
  (rejected at the cast, which has every division of the body in it), or, for a function with no copy
  (`implement`, `fun`), the same claims written by hand (`vacuity-by-hand-*`).
  A guard written as a `stadef` (sha256's `cube_fraction_*`, `sqrt_fraction*`) is not unfolded where its arguments are
  variables, only where they are literals, so its fixtures call the guard at the literal word of the first constant
  (accept) and at the word one off (reject); the array `iarr_*` rows are the int range, with a `[1 == 2]` probe and the
  largest int plus one (#876).
* Python, as every `tests/static` checker: they extend and import `proofs_audit.py`, `mutation_check.py`
  and `solver.py`, which read text and run patsopt, before any bats program is built.

### The merge queue (#586)

A PR in the queue is tested as a group (a commit of main plus the PR and the
entries ahead; `check.yml` on `merge_group`) and is **removed when the run has
not finished within 60 minutes**, even if it passes a minute later. The group
restores main's build cache; the long pole is the slowest static group. A
change that would make its own group longer than about 45 minutes is sharded
first (the mutation check is, below).

* **No more than two entries in the queue at a time**; the next goes in when one has
  merged or been removed (five at once wanted more runners than the pool has,
  and nothing merged for 3.5 hours).
* **Superseded runs are cancelled**: GitHub rebuilds the groups behind a
  removed entry and leaves the old runs queued. `check.yml` cancels a group's
  run on the group's `destroyed` event, and `supersede.yml` (#620) cancels the
  older runs of the same PR on `checks_requested` (the file's header says
  when).
* Where an entry is: the PR timeline (`added_to_merge_queue`,
  `removed_from_merge_queue`); `auto_merge` empty means enqueued or removed.

**Why a merge-queue entry is removed (keyword: queue-removal).** An entry leaves the queue for one of two
causes, and the `merge_group` runs that read `skipped` or `cancelled` beside a removal are never the cause:

* The `destroyed` merge_group event. GitHub sends it for a group it throws away (an entry removed, a group
  rebuilt). `check.yml` listens for it (`types: [checks_requested, destroyed]`) only so that its run joins the
  concurrency group of the run it ends and cancels it. Every job of that run carries the false `if`
  `github.event.action != 'destroyed'`, so the whole run reads `skipped`, `plan` included. A `skipped` queue run
  is therefore the end of a group, and the run it cancelled reads `cancelled`: neither says why the entry was
  removed.
* The 60-minute window. The queue removes an entry whose required checks have not all passed 60 minutes after
  it was added (the queue's checks timeout, 60 minutes by default). The timeline shows it as about 60 minutes
  between `added_to_merge_queue` and `removed_from_merge_queue`, with `auto_merge` empty after.
  A group whose jobs waited for runners, or a push run of main that took the runners for the commit the queue
  had just tested, spends the window.

Read the cause from the PR timeline first: the minutes between the two events (about 60 is the window), then the
failed job of the group's run (`failure` in `check`). A removal with another cause is a ticket of its own.

The static groups (`tests/groups.json`) are balanced by measured time (#618):
every group pays the app's cold check and then its members (a reject is
seconds, an accept a minute or more). A new fixture goes in the group with the
least member time; `scripts/ci-groups.py` fails a spec or fixture in no group
(or two), so a new one that is not in a group fails CI instead of never
running.

### Node's packages (#637)

Both jobs that use Node install it with pwa's `e2e-setup` action (called by
commit; `npm ci`, retried on a dropped connection, Playwright checked against
`playwright-minimum`). Quire holds no install logic of its own (CLAUDE.md, "Pipeline and tooling improvements belong in bats or pwa").

The owner ruled that every pin moves from the relock and that no bot opens a pull request (CLAUDE.md, "CI is pinned"); #996 moves these two to the relock and deletes `.github/dependabot.yml`. Until it does, which tool moves which pin here (#760; CLAUDE.md, "CI is pinned"): Dependabot
(`.github/dependabot.yml`, weekly, `cooldown` 7 days) moves the npm versions and `package-lock.json`
of the root `package.json`.

One pull request for every update (#795; the first run had opened eight at once, each a whole
`check` run, and `qsweep pressure` held every push and merge): the file defines one top-level
`multi-ecosystem-groups` group, `dependencies` (weekly, `patterns: ["*"]`), and the `npm` and
`github-actions` entries join it with `multi-ecosystem-group: dependencies`; the `cooldown` and the
`bats-lang/*` ignore stay on their entries. The docs: a plain `groups` rule is per ecosystem ("You
must configure groups per individual package ecosystem",
https://docs.github.com/en/code-security/tutorials/secure-your-dependencies/optimizing-pr-creation-version-updates),
and `multi-ecosystem-groups` is the key to "Define groups that span multiple package ecosystems to
get a single Dependabot pull request"; "Updates across multiple package ecosystems in the same group
are combined into a single pull request", and it "Require[s] the `patterns` key", `["*"]` meaning all
dependencies (https://docs.github.com/en/code-security/concepts/supply-chain-security/multi-ecosystem-updates,
https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference).
The docs' examples are docker and terraform and name no npm and github-actions pair, so that one PR
holds both is shown by the Dependabot run after the config merges (the readings are on #795), not by
the docs. If it opens two, the fallback is `open-pull-requests-limit: 0` in each entry and the
updates carried by the relock PR (a ticket in repository-prototype first).

That is the only `package.json` in quire: `ux-review/` has none, and its
Playwright config runs on the root's install. A Playwright bump brings the Chromium its version
needs. The docs: "Each version of Playwright needs specific versions of browser binaries to
operate." (playwright.dev/docs/browsers), so the browser moves with `@playwright/test` and no
browser is pinned by hand in CI. A bump is a pull request like any other and runs the whole e2e
suite; a pixel or timing difference it shows is a finding to fix, not a test to relax. The floor
`playwright-minimum` (1.58, the fake clock) stays where it is. Dependabot's documentation names
`.github/workflows` and the root `action.yml` for github-actions, and not the local composite actions
(`.github/actions/build-cache`, which pins `actions/cache`): whether those are read is
shown by the first Dependabot run, not by the docs. The hand-pinned Chromium of `ux-review/` is #761.

### The mutation check in CI (#594)

The fourteen proof modules in `tests/static/mutation_modules.txt` are hours of
mutants, too long for the required `check` and for a merge queue window. So:

* **No mutation job over about 25 minutes on an idle pool.** A module is split
  into parts (`mutation/crc-part2of5`, listed in `mutation_modules.txt`, read
  by `scripts/ci-groups.py` and `run.sh`): `mutation_check.py --shard I/N`
  takes the I-th of N parts of the selected lemmas, balanced by mutant count
  and the same on every machine.
* **A PR selects by its diff** (`scripts/ci-groups.py affected <group> <base>`;
  a job with nothing ends after its first step). `QUIRE_MUTATION_BASE` makes
  `run.sh` pass `--diff`: only the lemmas the diff touches, those that mention
  a name a changed line declares, and every lemma of a module whose diff is
  outside all its lemmas. A push to main and a dispatch run none of it.
* **A change to the solver, its pin (bats's setup action) or its fixtures
  selects everything**, sharded. **A change to the checker alone**
  (`mutation_check.py`, `mutation_test.py`, `mutation_modules.txt`,
  `mutation_known.txt`, `proofs_audit.py`) selects the modules marked `smoke`,
  whole. Groups, workflows and notes select nothing.
* **Nightly, in full** (`.github/workflows/mutation.yml`, on main, from
  nothing, an issue opened when a group fails): it has what a diff cannot see
  (a relocked package whose lemmas a proof calls, a compiler move). A vacuous
  lemma that gets in is found within a day, not on a red main.
* Diff on pull requests, full on a schedule is what Stryker's incremental
  mode, PIT and cargo-mutants' `--in-diff` do (all say a diff is not a
  substitute for a full run).
* `timeout-minutes` 120 (the nightly's 150) is a backstop under the patsopt
  caps, so a runaway proof fails with its module named.

### Only the groups a change can affect run (#619)

The `plan` job decides, once, from the PR's diff, which e2e groups and static
members the change can affect (`scripts/ci-groups.py plan <base>`, the table
`RULES` in `scripts/affected.py`, first match wins; its docstring says what
each kind selects) and prints each path's reason in its summary. Rules:

* **A group with nothing selected is a job that runs and ends after its first
  step**, so `check` is unchanged (it rejects a skipped job). Not a workflow
  path filter: GitHub leaves a required check "Pending" for ever then.
* **Fail closed**: a path no rule names, a diff that cannot be read, an empty
  diff, a deletion under `e2e/` select everything. The guideline files (`CLAUDE.md`,
  `.claude/**`, and `text-lint.yml`, which the test of the lint reads) select the `checkers` group only (`tests/static/guidelines.py` reads them,
  #751), and nothing else. A merge queue's group, a push, the nightly run and a dispatch run
  every group; the mutation groups keep their own rule.
* A new path, spec or fixture kind needs its rule: `tests/static/affected_test.py`
  (in `checkers`) tests the table on `tests/static/affected/cases.json`, that
  every spec and fixture is selected by a change to itself, and that a rule
  selecting nothing is named by nothing that could read the path. Tested, not
  proved: a spec that builds a path from pieces is not seen.
* The rule is Python in `scripts/` because it runs in the plan job, before any
  compiler exists.
* **`build` and `android` run for every PR, by decision (#656).** The plan has no
  entry for them and they read none, so a missing or malformed entry cannot
  skip them. `android` is a call of pwa's reusable workflow, and a skipped
  caller starts none of that workflow's jobs: the required contexts
  `android / build-android` and `android / smoke-test` would never be
  reported and the PR would wait for ever (GitHub's troubleshooting page: a job
  skipped by a condition reports success, but "avoid requiring workflows that
  can be skipped"; community discussion 29825 has the nested context left
  unfulfilled). `android` needs the `build` artifact, so `build` runs too.
  Skipping them waits for the required checks to be `check` alone, and for
  `check` to need `android` (today it needs `plan`, `build`, `static` and
  `e2e`; only `play-internal` needs `android`), a change of the branch
  protection that is an admin's;
  tested: `Workflow` in `tests/static/affected_test.py`.
* **A draft PR runs no job (#939, keyword: draft).** `check.yml` has `types: [opened,
  synchronize, reopened, ready_for_review]` (GitHub's default three plus the transition to ready,
  so marking ready runs the check on the head) and `plan`, `build` and `check` carry
  `github.event_name != 'pull_request' || !github.event.pull_request.draft`; `static`, `e2e` and
  `android` need them and are skipped with them. `check` is skipped, which a required check
  counts as passed, so it is reported, not missing; the draft cannot merge in any case, and
  the ready run reports every context (`android / ...` included, which #656 keeps unskipped
  for a ready PR). Push, `workflow_dispatch`, `schedule` and `merge_group` are unchanged.
  Libraries: the condition is repository-prototype#525, their callers' types the tickets of #939.
* **The merge queue's group runs everything, by decision (#656).** Its diff
  (against `HEAD^1`) is one PR's, so a selection by it would be the PR's own
  and would miss what two PRs do together, which is what the queue is for
  (the "not rocket science" rule: what reaches main passed the whole suite,
  as rust-lang's bors runs the full suite on the merge commit and a limited
  one on the PR, rustc-dev-guide, "Continuous integration"). GitHub also needs
  the required checks to report on `merge_group` (it does). The cost is the
  queue's 60 minutes, which the groups' balance keeps (#618); the PR's run is
  where the selection saves.

## Checking locally before a push

A session sets up the compiler in its own environment: what bats's composite action does
(`bats-lang/bats/.github/actions/setup`, called by commit from `check.yml`, `mutation.yml` and
`deploy.yml`; quire keeps no copy of it). That is ATS2's `patsopt` from the tarball it names
(the gmp build, whose solver computes in infinite precision, with libgmp-dev; the -int build's
solver computes in C `int` and accepts false statements, #594, so a check made with it proves
less than CI's), `lld`, the compiler built from the commit in `.github/bats-version` (its
`bootstrap/c`, `make release/bats`), and a clone of bats-lang/repository-prototype at the
commit `.github/repository-version` names. Locally run `bats check --repository <the clone>`,
or with `BATS_REPOSITORY=<the clone>` and no flag (the flag wins).

* **The command** (quire#751): in the checkout that stays, `bats with-env ~/quire.env bats check`,
  where the env file sets `BATS_SLOTS=1` (never 2), `BATS_LOCK_DIR`, `BATS_CACHE_DIR` and
  `BATS_REPOSITORY`. No `timeout` wrapper: the Bash tool's own cap of 600000 ms ends a foreground
  command, and a wrapper below it kills a cold check for nothing. The first build of a new checkout
  runs with `run_in_background` and its log is read until it ends, in the same turn. A push is
  `qsweep push <arguments>`, which holds when `qsweep pressure` does not say `runner pressure: none`.
* **A run over a population is a sample** (quire#751): about 10 minutes, the members drawn at random
  with a seed that is printed (`python3 -c 'import random; r = random.Random(SEED); ...'`), and the
  PR says the sample, its seed and size and why it suffices; the whole population is CI's.
* Two bats in one checkout take turns (a lock on `bats.toml`). Two checkouts take turns by
  bats's opt-in machine-wide slots: with `BATS_SLOTS=N` (1 to 64) `check`, `build`, `test` and
  `run`'s build each hold one of N `flock` files in `BATS_LOCK_DIR`. `gen-pwa test` uses the
  same files for `PWA_TEST_SLOTS` in `PWA_TEST_LOCK_DIR`; one directory for both makes builds
  and e2e runs one pool. A machine shared by sessions sets `BATS_SLOTS=1`, `BATS_LOCK_DIR` and
  `PWA_TEST_LOCK_DIR` (one directory), `PWA_TEST_SLOTS=1`, `BATS_CACHE_DIR` and
  `BATS_REPOSITORY` in the shell's profile.
* A shell that reads no profile (an agent's) gets the same from an env file that is not in the
  repo (say `~/quire.env`) through `bats with-env <env-file> <command> [args...]` (bats#277):
  it adds the file's variables and runs the command exactly as given, e.g. `bats with-env
  ~/quire.env bats check`.
* `BATS_CACHE_DIR=<dir>` keeps patsopt's C in that directory, keyed by what patsopt reads,
  shared by every checkout of the machine (#499). Set it in the profile.
* The e2e suite runs through the app's generator, `./dist/debug/gen-pwa test [--timings
  <dir>] [-- <playwright args> <spec>...]` (pwa's `test_run`, bats-lang/pwa#82), after `bats
  build`, `./dist/debug/gen-pwa`, `scripts/sync-clients.sh dist/pwa` and `cp -R homepage
  dist/pwa/homepage` (`e2e/about.spec.js` reads the home page). It serves `dist/pwa` at a port
  the kernel picks, takes a slot, checks that `PLAYWRIGHT_BROWSERS_PATH` holds the headless
  Chromium this Playwright expects (it never downloads one), and runs the `@serial` tests alone
  and then the others. A `--grep` or `--workers` of the caller's makes it one run. A change to
  a spec or a static fixture runs that group too where the machine can (`tests/static/run.sh`,
  `gen-pwa test -- <spec>`); the rest of the population is CI's. Playwright
  1.58 or later is required (`.claude/rules/e2e.md`).
  **The tight loop** (keyword: e2e loop): to edit, build and test again, gen-pwa is not rebuilt (it
  changes only with `src/bin/gen-pwa.bats` or the way the pwa is assembled): `bats build --only debug
  --only wasm`, then `cp dist/debug/quire.wasm dist/pwa/app.wasm` (the two are byte-identical), then
  `./dist/debug/gen-pwa test -- <spec>`. The full build, gen-pwa and `scripts/sync-clients.sh` are for
  the final evidence, when the Done-when names it.

## Running the e2e flight recorder on a local machine: tracefs and a non-root user (quire#765)

The flight recorder reads the kernel's tracing filesystem and runs its root steps through
`sudo -n`, as CI does on its runner: in `e2e/flight-recorder.js` the ring's `asRoot` (line 46)
runs `sudo -n` on `ROOT_SCRIPT`, which is `e2e/flight-tracefs.js` (line 23 of
`e2e/flight-recorder.js`); line 296 is the `sudo -n` spawn of `e2e/flight-watchdog.js`
(`WATCHDOG_SCRIPT`, line 286), not a ring step; and `e2e/preflight.js` checks `sudo -n true`
at line 116. The watchdog (`e2e/flight-watchdog.js`) makes no `sudo` call; it gives its output to
the user `sudo` ran for (`SUDO_UID`, line 34). `flight-tracefs.js` sets
`TRACEFS = /sys/kernel/tracing`. Where that directory is not a mounted tracefs, the recorder
reports `the kernel ring did not start (no tracefs, or sudo refused: see the run's first lines)`
(`e2e/flight-recorder.js` line 89).

* **The mount.** The command is `mount -t tracefs nodev /sys/kernel/tracing`, run as uid 0. Run
  on 2026-10-21 in a container where tracefs was not yet mounted, it printed `rc=0` and the line
  `nodev /sys/kernel/tracing tracefs rw,relatime 0 0` in `/proc/mounts` (quire#765's ticket body).
  Run again on 2026-10-22 where it was already mounted, it failed with exit 32:

  ```
  $ mount -t tracefs nodev /sys/kernel/tracing; echo rc=$?
  mount: /sys/kernel/tracing: nodev already mounted on /sys/kernel/tracing.
  rc=32
  $ grep tracefs /proc/mounts
  nodev /sys/kernel/tracing tracefs rw,relatime 0 0
  ```

  A setup script must therefore mount only when the line is missing. Its line, tested here
  on the already-mounted path (exit 0 and no second mount), is
  `grep -q tracefs /proc/mounts || mount -t tracefs nodev /sys/kernel/tracing`.
* **Does the mount survive a container restart (quire#958).** It does not: tracefs is a mount, and
  `/proc/mounts` is per boot. Observed after the restart of 2026-10-27/28: the boot was at
  2026-10-27 23:56:40 UTC (`uptime -s`), `grep tracefs /proc/mounts` printed nothing until the
  orchestrator ran the allowed command by hand, and the preflight failed with `PREFLIGHT FAILED:
  kernel ring: no tracefs instances directory`. Why it was unmounted (the environment's setup script
  did not run at the restart, or ran and failed) is not established, and an agent in the container
  cannot establish it: the container's logs hold nothing after the boot that the script would leave
  (no apt or dpkg entry since 2026-10-21, no shell history, and the mount line leaves no trace when
  it runs). It is quire#965, for the owner. The rule does not depend on the answer: a worker on a
  container that was restarted, or whose preflight prints that message, runs once, as root, the
  allowed command `grep -q tracefs /proc/mounts || mount -t tracefs nodev /sys/kernel/tracing`
  (the compound form `.claude/settings.json` allows on line 9; it does nothing where tracefs is
  mounted), checks `grep tracefs /proc/mounts`, and runs the spec again. The preflight's message
  (`e2e/flight-tracefs.js`), `worker.md` and the worker brief (`.claude/orchestration.md`, "Briefs
  and the machine") carry the same command. No other `mount` is run.
* **Who runs the specs.** As uid 0, the specs run without any `sudo`. A run as another user
  (comment 6329897260 ran as user `quireci`, `sudo -u quireci -H env CI=true ...`) needs a user
  and a `sudo -n` grant. The ticket records no `useradd` and no `sudoers.d` command for that user,
  so neither is given here; in this container `getent passwd quireci` is empty and
  `/etc/sudoers.d` holds only its `README`. The run of comment 6325792780 passed as `quireci` with an env file that user read, so the file
  must be readable by that user.
* **The four specs that passed** (root; each command is `CI=true bats with-env <env> ./dist/debug/gen-pwa test -- <spec>`,
  shown in the comment that holds the run, for example 6325766934; `.claude/rules/e2e.md` has no
  `CI=true`):
  `e2e/evidence.spec.js` 34 passed, 62 skipped; `e2e/evidence-real.spec.js` 25 passed and the
  serial test passed; `e2e/stall-capture.spec.js` 64 passed (its comment holds only the last 150 lines, so the serial
  line is not shown there);
  `e2e/sanitizer.spec.js` against the AddressSanitizer build of Chromium, 9 passed. The raw outputs
  are on quire#765 (comments 6325766934, 6325769509, 6325792430 and 6325769875).
* **A non-root run** (`sudo -u <user> -H env CI=true ...` with the worktree owned by `<user>`):
  `e2e/evidence.spec.js` passed with 34 passed, 62 skipped (comment 6325792780);
  `e2e/stall-capture.spec.js` passed with 64 passed and the serial test passed (comment
  6329897260); `e2e/evidence-real.spec.js` failed on `EACCES` until the root-owned output directory was
  removed, then passed with 25 passed and the serial test (quire#767's body). Two defects came from those runs and are filed as p0: a root run leaves
  `test-results/**/watchdog/` owned by root, and the next run as the user fails to unlink it with
  `EACCES` (quire#767); and `PWA_TEST_LOCK_DIR` on the machine was root-owned, so the run printed
  `a lock file in PWA_TEST_LOCK_DIR could not be opened: running without the machine's lock`
  (quire#768).
* **The ASan browser** for `e2e/sanitizer.spec.js` is the archive `check.yml` names, checked against
  the SHA-256 `check.yml` pins (`.github/workflows/check.yml` lines 430 to 434, the install):

  ```
  curl -fsSL --retry 5 --retry-all-errors -o "$RUNNER_TEMP/asan.zip" https://storage.googleapis.com/chromium-browser-asan/linux-release/asan-linux-release-1625077.zip
  echo "1e4744f206e8a2eca53b3184ff673e1dbed7cdcad146a0f2efc42bdde65749bc  $RUNNER_TEMP/asan.zip" | sha256sum -c -
  unzip -q "$RUNNER_TEMP/asan.zip" -d "$RUNNER_TEMP/asan" chrome '*.pak' icudtl.dat '*.bin' '*.so' libvulkan.so.1 'locales/*' chrome_crashpad_handler vk_swiftshader_icd.json
  rm "$RUNNER_TEMP/asan.zip"
  sudo apt-get install -y -q libpci3
  ```

  Its central directory records mode 0755 for `chrome` and `chrome_crashpad_handler`, and `unzip`
  (what `check.yml` uses) restores that mode. A `bsdtar` extraction on the machine gave 0664
  instead (quire#765, comment 6325973318), and that run needed `chmod 0755` on the two before it
  could spawn them (comment 6325769875). The extracted browser is about 4.4 GB.
