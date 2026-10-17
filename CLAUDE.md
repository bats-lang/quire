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

## CI is pinned

Every input to CI is pinned in the source (#203), so a commit that passes keeps
passing: the packages by the committed `bats.lock`, the compiler by its commit in
`.github/bats-version`, pwa's Android workflow by its commit (`android.yml@<sha>`
in `check.yml`), and the runner image by its label. CI never runs `bats lock`:
`bats check` and `bats build` fetch exactly the locked versions and fail when a
lock is missing or does not match the project. A quire PR that adopts new package
versions runs `bats lock --repository <dir>` and commits `bats.lock` with the
change that needs them. Pins move only through a reviewed PR that runs the same
CI; the daily relock is one such PR. The build cache and its key, the merge queue,
the Node packages and the pipeline rules are in `.claude/rules/ci.md`, which loads
when CI files are touched.

## Check locally before every push

A session sets up the compiler in its own environment and runs `bats
check` before it pushes, so a push that does not type-check never
reaches CI (#350's first push failed on a comparison and a free that
`bats check` rejects in a few minutes; CI took 15 to learn it). Setup is
what bats's composite action does (`bats-lang/bats/.github/actions/setup`,
called by commit from `check.yml`, `mutation.yml` and `deploy.yml`, bats#280;
quire has no copy of it, since a second app would copy it, #623): ATS2 (`patsopt` from the
tarball it names: the gmp build, whose constraint solver computes in
infinite precision, with libgmp-dev; the -int build's solver computes in
C `int` and accepts false statements, #594, so a check made with it
proves less than CI's), `lld`, the compiler built from the commit in
`.github/bats-version` (its `bootstrap/c`, `make release/bats`), and a
clone of bats-lang/repository-prototype at the commit
`.github/repository-version` names (the relock moves it, with
`.github/bats-version` and the action's own pin); the action sets
`BATS_REPOSITORY`, `BATS_COMMIT` and the patsopt caps for the later steps, so
CI passes `--repository` nowhere; then `bats check --repository
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
`~/quire.env`, holding those variables), through bats's `scripts/with-env
<env-file> <command> [args...]` (bats-lang/bats#277, a script of the bats
checkout, tested there): it sources the file (every variable exported) and
`exec`s the command exactly as given, so its arguments and exit status are
the command's own: `<bats checkout>/scripts/with-env ~/quire.env bats
check`, `<bats checkout>/scripts/with-env ~/quire.env ./dist/debug/gen-pwa
test -- <spec>`.

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
`package-lock.json` pins 1.58.2, and the jobs that install it pass
`playwright-minimum: "1.58"` to pwa's `e2e-setup` action, which fails below
it; `gen-pwa test` refuses it too, pwa#92): before 1.58 its fake clock can
set the time back after a `page.clock.fastForward` (a `_runTo` already in flight
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
head (`BATS_COMMIT`, set by bats's setup action for every later step: the
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
Play's internal testing track by `check.yml`'s `play-internal` job, which
calls pwa's reusable workflow `play-release.yml` by commit (bats-lang/pwa#90,
pwa#101; the script, its stub of Play and its test live there, moved by
quire#623, and this repository keeps none): the run's own `release-aab`,
the commit's first line as its notes, committed with `ERROR_IF_IN_REVIEW`.
The caller passes the same commit twice, as `uses:` and as `pwa-ref` (a
reusable workflow cannot read the commit it was called at), and its public
names (package, Workload Identity provider, service account) as `with:`
inputs in `check.yml`. It signs in by Workload Identity Federation, whose
provider admits only a push to main of this repository, so no key exists
and no other run can release. Production is a promotion in the Play
Console; ANDROID.md says how.
