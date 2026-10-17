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

The runner label is pinned too (#667): every job runs on `ubuntu-24.04`,
written in each job's `runs-on` in `.github/workflows` (quire has no
reusable workflow of its own to write it once in). `ubuntu-latest` is not
used, since it moves with GitHub's default: the runner-images README says
`ubuntu-latest` is `ubuntu-24.04` today. The label moves by hand, in a PR
of its own, when GitHub announces its successor (as bridge's CLAUDE.md
says); the build cache's key names it (`runner-image` in
`.github/actions/build-cache`, passed by each call), so that move starts a
new cache.


A publish never turns main red: until a lock names it, quire does not use it,
so package releases publish first and the quire PR with the new lock follows.
The daily `relock.yml` (the shared `relock-pins.yml`, called by commit) pushes
`relock/<date>` and opens a PR listing what moved. GITHUB_TOKEN cannot change
workflow files, so that PR lists pwa's `android.yml` pin as not moved (no
`RELOCK_TOKEN`): move it in a PR of its own.

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
