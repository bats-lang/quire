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
  `build/` with the C compiler's version, so a build made on another image is dropped (#622).
* A publish never turns main red: until a lock names a package release, quire does not use
  it, so package releases publish first and the quire PR with the new lock follows.
* GITHUB_TOKEN cannot change workflow files, so the relock PR lists pwa's `android.yml` pin
  as not moved (no `RELOCK_TOKEN`): move it in a PR of its own.

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
    its closure key below, `build/.sats_changed`, and each object by the sha256 of its C and its
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
  * the system headers the C includes (bats#338): the stamp's `cc` line is clang's version,
    target and environment, not the headers;
  * the system libraries that patsopt and the native link load, libgmp among them (the stamp's
    `patsopt` line is the cksum of `bin/patsopt`, not of the libraries it loads; bats#380);
  * `bats.toml`: the rules name only its version and constraints (`lock.md`), its unsafe flag
    (validation records) and its dependencies (the listing of `bats_modules`); no rule says what
    else in it reaches the build.
  A new runner image is judged only through what is listed here: clang's version, target and
  environment are stamped, its headers and libraries are not.
* **The fixtures' memo** (bats#303): `bats fixtures` keeps each static fixture's result, keyed by
  the toolchain's stamp, the snippet, the module with it in and every file patsopt reads for
  the module, and serves it only when all are as they were. `--cold` (run.sh's first argument,
  not `BATS_COLD`, which would also make every check cold) serves none and audits what it would
  have served.
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
  the previous build. Each static group saves the `static` build under one key; the second to
  finish gets a warning, not a failure. Caches are immutable, 10 GB per repository, evicted
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

### The merge queue (#586)

A PR in the queue is tested as a group (a commit of main plus the PR and the
entries ahead; `check.yml` on `merge_group`) and is **removed when the run has
not finished within 60 minutes**, even if it passes a minute later. The group
restores main's build cache; the long pole is the slowest static group. A
change that would make its own group longer than about 45 minutes is sharded
first (the mutation check is, below).

* **At most two entries in the queue at a time**; the next goes in when one has
  merged or been removed (five at once wanted more runners than the pool has,
  and nothing merged for 3.5 hours).
* **Superseded runs are cancelled**: GitHub rebuilds the groups behind a
  removed entry and leaves the old runs queued. `check.yml` cancels a group's
  run on the group's `destroyed` event, and `supersede.yml` (#620) cancels the
  older runs of the same PR on `checks_requested` (the file's header says
  when).
* Where an entry is: the PR timeline (`added_to_merge_queue`,
  `removed_from_merge_queue`); `auto_merge` empty means enqueued or removed.

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

### The mutation check in CI (#594)

The nine proof modules in `tests/static/mutation_modules.txt` are hours of
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
  diff, a deletion under `e2e/` select everything (so do `.claude/**` files for
  now, #680). A merge queue's group, a push, the nightly run and a dispatch run
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
  `gen-pwa test -- <spec>`); what it cannot run is left to CI and said in the PR. Playwright
  1.58 or later is required (`.claude/rules/e2e.md`).
