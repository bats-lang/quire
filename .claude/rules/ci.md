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
job passed. **No key is relied on for correctness**: the key is a locator,
`quire-<name>@<pins>-<sha>` (a GitHub cache is immutable, so each save needs a new key), and a
restore takes the newest cache of the name and pins (`restore-keys` `quire-<name>@<pins>-`; the
`@` ends a name, so `static` never finds `static-memo-rest@...`). It names no runner image, lock,
`bats.toml`, source hash or version a developer bumps, so a new input needs no new key part and
a wrong key can only restore less useful files.

* **The pins stay in the key** (`<pins>` = a digest of `.github/bats-version`, which holds the
  ATS2 pin, and of the commit of bats's setup action) until bats-lang/bats#316 (a missing
  toolchain root gives a shorter listing and no error) is fixed, the freshness audit (bats#317)
  is done, and quire's pin contains bats#305's fix (77e60a55; a patsopt or toolchain directory
  that is a symbolic link, changed in place, was not seen). Until then a `build/` restored from
  another ATS2 install could pass the stamp and have its C and objects reused.
* **bats judges what a restore holds** (bats's CLAUDE.md is the record): `build/.bats_stamp`
  (bats's inputs, patsopt's toolchain, the C compiler's version, flags, target) drops a `build/`
  made by another toolchain, naming what differs (bats#273); freshness is by content hash, never
  time (bats#254, #293), and in check mode by what patsopt read for the module (#298); a
  relocked package's files, or a restore that gives every file the restore's time, change nothing.
* **The fixtures' memo** (bats#303): `bats fixtures` keeps each static fixture's result, keyed by
  the toolchain's stamp, the snippet, the module with it in and every file patsopt reads for
  the module, and serves it only when all are as they were. `--cold` (run.sh's first argument,
  not `BATS_COLD`, which would also make every check cold) serves none and audits what it would
  have served.
* **Paths**: bats takes the checkout's path out of the C (bats#250), so a cache is valid
  anywhere. `QUIRE_STATIC_WORK` (CI: `$RUNNER_TEMP/quire-static`) is only the directory
  `tests/static/run.sh` works in and the static jobs cache (`app/build`, `memo`).
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
  inputs because the tool computes them; quire's keys do not try to, bats does.
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
  when); `qsweep` cancels what slips through.
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
* Not done: the `build` and `android` jobs still run for every PR.
