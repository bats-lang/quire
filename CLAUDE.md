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

Element ids, numbered-id prefixes (up to 16 bytes), variables, static indices and
functions are named by what they are, in words: `search-close`, `toc-row12`, `query`,
`query_len`, not `qsrz`, `qe`, `q`, `qn`. Nothing is short of bytes, and terse names
collide (a rename of the id `qn` once also hit a query length of the same name). A loop
index (`i`, `j`) or a conventional pair (`l` and `n` for an array's location and size)
may stay short within a few lines.

## Priorities

* **p0:** anything that makes CI faster or more reliable, or makes development
  faster or more reliable. A wrong cache is p0: it is what makes people run a
  clean build "just in case". So is a cost of the agent sessions that lowers
  what the work costs.
* **p1: correctness.** Missing proofs, tests or coverage, wrong behaviour, audit
  gaps, violations of the safety rules.
* **p2:** quire's user-visible features, and the developer experience of other
  bats app developers. Shell tools count under this rule, since changing them
  means scripting shell instead of implementing bats.
* **p3:** everything else; not held for. A session may file p3 issues but does
  not work on them.

Order: p0 first, then p1, then p2, and within a priority the oldest
opened ticket first, so none starves. A PR already started finishes
before a new one is started. Downgrading a ticket to p3 on judgement
(minor impact, high cost) needs the owner's approval; the tickets that
are p3 today are approved.


## Pipeline and tooling improvements belong in bats or pwa

Anything a second app would copy is built where the apps share it, and quire calls it:
the compiler's build, cache and fixture runner, and the setup of the toolchain, are bats's
(bats-lang/bats); the Android project and its release, test running (Playwright, its
install and browsers), the emulator job and the pages beside the app are pwa's
(bats-lang/pwa). Quire's own CI holds what is about quire: its specs and fixtures, which
job runs which (`tests/groups.json`), its books and its proofs. Before a workflow or
script of quire is changed, ask whether an alarm clock built the same way would copy the
change; if it would, the change is a ticket in bats or pwa first (quire#623 is the list of
what already is one), and quire's change is only the call.

A stopgap in quire is allowed only when waiting would cost more than the move (a flake that
removes a merge queue entry each time it happens), and then the ticket that moves it is
written first, the stopgap says so in its comment, and it is deleted when the move lands
(quire#635's retries and cache, moved by quire#637). A stopgap with no ticket for its move
is not a fix.

**We do not write shell scripts (or any non-bats code of our own) unless all other avenues
are exhausted.** We self-host in bats, implement in bats, build tooling in bats;
dependencies on other tools are fine; only what is impossible in bats (like getting bats to
run) is not bats. A PR that adds non-bats code of ours names the avenue it exhausted
(quire#646).

**No mtimes in freshness.** Nothing that decides whether an output is fresh (a build, a
cache, a memo, a test selection) reads a file's time: it compares content hashes (bats#254).

## CI is pinned

Every input to CI is pinned in the source (#203), so a commit that passes keeps passing:
the packages by the committed `bats.lock`, the compiler by its commit in
`.github/bats-version`, pwa's Android workflow by its commit (`android.yml@<sha>` in
`check.yml`), and the runner image by its label. CI never runs `bats lock`: `bats check` and
`bats build` fetch exactly the locked versions and fail when a lock is missing or does not
match the project. A quire PR that adopts new package versions runs `bats lock --repository
<dir>` and commits `bats.lock` with the change that needs them. Pins move only through a
reviewed PR that runs the same CI; the daily relock is one such PR. The build cache and its
key, the merge queue, the Node packages, the mutation check and which groups a change runs
are in `.claude/rules/ci.md`, which loads when CI files are touched.

## Check locally before every push

A session sets up the compiler in its own environment and runs `bats check` before it
pushes, so a push that does not type-check never reaches CI. Setup is what bats's composite
action does (`bats-lang/bats/.github/actions/setup`, called by commit from `check.yml`,
`mutation.yml` and `deploy.yml`; quire has no copy of it): ATS2's `patsopt` from the tarball
it names (the gmp build, whose solver computes in infinite precision, with libgmp-dev; the
-int build's solver computes in C `int` and accepts false statements, #594, so a check made
with it proves less than CI's), `lld`, the compiler built from the commit in
`.github/bats-version` (its `bootstrap/c`, `make release/bats`), and a clone of
bats-lang/repository-prototype at the commit `.github/repository-version` names. The action
sets `BATS_REPOSITORY`, `BATS_COMMIT` and the patsopt caps for later steps; locally run `bats
check --repository <the clone>`, or with `BATS_REPOSITORY=<the clone>` and no flag (the flag
wins). A check takes 10 to 15 minutes on a cold build: run it in the background and wait for
it, never push on the hope that it passes.

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
  Chromium this Playwright expects (it never downloads one), runs the `@serial` tests alone
  and then the others. A `--grep` or `--workers` of the caller's makes it one run. It needs
  Playwright 1.58 or later (`.claude/rules/e2e.md`). A change to a spec or a static fixture
  runs that group too where the machine can (`tests/static/run.sh`, `gen-pwa test --
  <spec>`); what it cannot run is left to CI and said in the PR. A fix pushed after a red CI
  is checked the same way first.

## The version is the commit's

Quire's version is the date of the commit it is built from, never of the build, so the same
commit always gives the same version (#219): the committer date in UTC,
`YEAR.MONTH.DAY.SECONDS` (seconds since midnight), and the short SHA, `2026.10.2.61373
(f95ce82)`. bats writes the commit's facts as a module (`build/src/_bats_facts`, from the
commit `BATS_COMMIT` names, else HEAD) and `src/version.bats` words them (`quire_version`,
`quire_commit_short`, `quire_version_text`, `quire_version_code`). The app and gen-pwa compile
them in: About shows the text, a backup records it (`appVersion`), and gen-pwa appends it to
the Android project's `android-release.gradle` as `versionName`, with `versionCode` the same
time in minutes since 2025. CI names a pull request's own head (`BATS_COMMIT`, set by bats's
setup action: the merge's second parent, hence `fetch-depth: 2`) and for a merge group the
group's own commit (`github.sha`). Outside a git repository a build fails and says so;
`tests/static/run.sh` points git at the checkout's repository (`GIT_DIR`).
`tests/version/same.sh` checks that the facts are the same in other time zones, name the
commit, and that the Android project carries the version and its code.

## Main goes to Play's internal testing (#308)

Every push to main that passes the whole check is released to Google Play's internal testing
track by `check.yml`'s `play-internal` job, which calls pwa's reusable workflow
`play-release.yml` by commit (the script, its stub of Play and its test live in pwa): the
run's own `release-aab`, the commit's first line as its notes. The caller passes the same
commit twice, as `uses:` and as `pwa-ref`, and its public names as `with:` inputs. It signs in
by Workload Identity Federation, whose provider admits only a push to main of this
repository, so no key exists and no other run can release. Production is a promotion in the
Play Console; ANDROID.md says how.
