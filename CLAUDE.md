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

## Comments name their area by keyword

A comment states its reason in one line and names the area by keyword; the detail lives in `.claude/rules/*.md`: search them for the keyword before changing the code.

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
run) is not bats. Our own code is bats; the only non-bats code is what is impossible in
bats, a dependency's own format, or a third-party tool used as it is. A workflow `run:`
step that does more than call one bats subcommand or one third-party tool is code we
wrote. A PR that adds non-bats code of ours names the avenue it exhausted, and the
reviewer rejects it without that (quire#646, quire#731).

**No mtimes in freshness.** Nothing that decides whether an output is fresh (a build, a
cache, a memo, a test selection) reads a file's time: it compares content hashes (bats#254).

## Breaking changes keep at least one published version of overlap (#762)

The owner's standing rule (2026-10-19T03:28:04Z, transcript line 46303): "OK. I'm not sure where this should be but it is a standing rule for the session: breaking changes must have *at least* one version of overlap." The full text, with the owner's quotes and their transcript lines, is in repository-prototype's CLAUDE.md, under "Publishing Packages" (https://github.com/bats-lang/repository-prototype/blob/20f15c0/CLAUDE.md, bats-lang/repository-prototype#381 and #384). The four, each with its transcript line:

* 2026-10-19T03:28:04Z (transcript line 46303): "OK. I'm not sure where this should be but it is a standing rule for the session: breaking changes must have *at least* one version of overlap."
* 2026-10-20T05:35:29Z (transcript line 51253), on a pull request that changed the word helpers' public signatures: "THERE ARE RULES ABOUT BREAKING CHANGES"
* 2026-10-21T16:56:11Z (transcript line 64376): "NEVER DEPRECATE IN ONE GO WE HAVE THIS DOCUMENTED CHECK THE HISTORY"
* 2026-10-21T16:57:11Z (transcript line 64396): "I have said this like five times in the conversation. If it's not somewhere you keep add it NOW."


A pull request that changes a published signature (of a package, in its repository) does what that section's rule says: a breaking change to a published signature is made in two steps, never one. The new form is added beside the old one, named by what it adds (as `_proved` is); the old one is marked deprecated in a one-line comment that names its area by keyword and its removal ticket; a test calls the old form, so an edit cannot drop it. One published version holds both. The ticket that removes the old form is filed with the change, as p2: removing an old form is cleanup, not a correctness defect, and a higher priority would put it ahead of every p2 feature.

The review of such a pull request checks both steps, each one: the old form is still there, beside the new one; a test calls the old form; the old form has a deprecation comment that names the area by keyword and the removal ticket; the removal ticket exists, is p2, and was filed before the change. A pull request that changes a published signature in place gets `Verdict: changes needed`. The brief templates carry the line (`.claude/orchestration.md`, "Briefs and the machine"), and `tests/static/guidelines.py` refuses a brief or a review of a signature change that lacks it.

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

Which tool moves which pin (`.github/dependabot.yml`, weekly, a 7-day cooldown, one pull request
for all the updates of both ecosystems, from one `multi-ecosystem-groups` group with `patterns:
["*"]`: "Define groups that span multiple package ecosystems to get a single Dependabot pull
request", https://docs.github.com/en/code-security/concepts/supply-chain-security/multi-ecosystem-updates;
#760, #795, the detail in `.claude/rules/ci.md`, "Node's packages"): the daily relock moves
the compiler, the package repository and the workflow pins it names. Dependabot moves quire's
actions by commit with their release comments, except the `bats-lang/*` ones, and the npm versions
and `package-lock.json` of the root `package.json`, which carries `@playwright/test` and so the
Chromium it runs. The bats setup action's commit and the runner label are moved by hand, each in a
pull request of its own.

## No cache key is relied on for correctness (#622)

A restored `build/` or fixtures memo is judged by bats, never by the key that found it: bats
drops a `build/` whose stamp (its own inputs, ATS2, the C compiler, the flags, the target)
differs and says so on stderr, rebuilds a module by the content hash of its sources and of the
files patsopt read, and serves a fixture's memo only when every file it read is unchanged
(bats's CLAUDE.md and its `stamp`, `build-freshness`, `check-memo` and `fixtures-memo` notes).
Quire's key is `quire-<name>@<commit>`, only a locator for the newest earlier cache; it names
no pin, image, lock or source hash and carries no number to bump, so a new input needs no key
edit. What bats does not yet judge is listed in `.claude/rules/ci.md`.

## Check locally before every push

Run `bats check` before every push, so a push that does not type-check never reaches CI. The
check runs in a checkout that stays (the next ticket is a new branch in it, and nobody
deletes it or its `build/`; under disk pressure `qsweep clean` removes only an older worktree whose
pull request merged, never the one that merged last, a ticket in flight, or the orchestrator's
checkout), so it is incremental; only the first build of a new checkout is
cold (10 to 15 minutes), and that one runs in the background and is waited for in the same
turn. Every local run takes about 10 minutes: a run over a population (the static fixtures,
the e2e specs, the mutation lemmas) is a random sample of it, drawn with a seed that is
printed, with the sample and why it suffices written in the PR; CI runs the whole
population. Run the groups a change touches this way, and a fix pushed after a red CI is
checked the same way first. How (the compiler, the machine's slots and env file, the cache,
the e2e run): `.claude/rules/ci.md`.

## Evidence, red tests and CI

The author posts the evidence for every claim of a PR and every item of the ticket's
Done-when in the PR body: the command and its raw output. A claim is never weakened to match
the logs; the code is changed until the output shows it. The Done-when as written is the
standard: nobody narrows a ticket in a brief, in a review or in a PR.

A test that went red is root-caused, or the test is made robust against the cause that was
found: `it passed again`, `it passes alone` and `contention` are not causes. A class of
failure a change says it covers has a case that fails when the class occurs, shown by
injecting it. The author owns CI until it is green (push, report the head, finish; never
wait on a run); any author may take over a red, or a merge conflict. A reviewer runs
nothing and starts only when every required check is finished and green on the exact head.
The rules for the agents are in `.claude/agents/worker.md`, `.claude/agents/reviewer.md` and
`.claude/orchestration.md`, and `tests/static/guidelines.py` (the `checkers` group) refuses
the phrases that made these mistakes come back (quire#751).

## The version is the commit's

Quire's version is the date of the commit it is built from, never of the build: the same
commit always gives the same version (#219). How it is made and shown: `.claude/rules/release.md`.

## Play release

A push to main that passes the whole check is released to Google Play's internal testing
track by `check.yml`'s `play-internal` job; production is a promotion in the Play Console
(details: `.claude/rules/release.md`).
