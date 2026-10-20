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
* **p3:** everything else; a session may file p3 issues but does not work on
  them.

Order: p0 first, then p1, then p2, and within a priority the oldest
opened ticket first, so none starves. All open p0s, in flight or not, come
before any p1: a p1 is not started while a p0 is open, whether or not a
worker has the p0 in hand. Within one priority, a PR already started finishes
before a new one is started, so a started p1 PR finishes, and no new p1 starts
while a p0 is open.

No downgrades without the owner's word. Downgrading a ticket to p3 on
judgement (minor impact, high cost), or to any other priority, needs the
owner's approval; the tickets that are p3 today are approved. An issue's
priority is the owner's call: a worker that thinks it is wrong says so on the
issue, and does not change the label.

The Android release is not a priority. Priority is the order in which tickets
are worked, and p2 means user-visible features and developer experience, not
"held for the release". If the owner holds the Android release for an issue,
that hold is a rule on top of the order: it is recorded on the issue, and it
does not move the issue to another priority.


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

Run `bats check` before every push, so a push that does not type-check never reaches CI. A
cold check takes 10 to 15 minutes: run it in the background and wait for it, never push on
the hope that it passes. Run the e2e or static groups a change touches where the machine can,
and a fix pushed after a red CI is checked the same way first. How (the compiler, the
machine's slots and env file, the cache, the e2e run): `.claude/rules/ci.md`.

## The version is the commit's

Quire's version is the date of the commit it is built from, never of the build: the same
commit always gives the same version (#219). How it is made and shown: `.claude/rules/release.md`.

## Play release

A push to main that passes the whole check is released to Google Play's internal testing
track by `check.yml`'s `play-internal` job; production is a promotion in the Play Console
(details: `.claude/rules/release.md`).
