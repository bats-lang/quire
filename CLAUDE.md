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
  what the work costs. A speed ticket is p0 only at a better big O or a factor of two
  or more (owner, 2026-10-23T13:12:21Z, transcript line 78273: "For a ticket to count as p0 for Ci speed it should be either big o or a factor of two or more. Otherwise, there's infinite work on p0"); a smaller gain is p2. Correctness is never
  gated on speed (owner, 2026-10-22T10:28:07Z, line 70965: "correctness can never be gated on speed"), so no
  correctness ticket, brief or review carries a timing measurement, a speed budget or a net-cost clause.
* **p1: correctness.** Missing proofs, tests or coverage, wrong behaviour, audit
  gaps, violations of the safety rules, and a statement that is no longer true
  (owner, 2026-10-22T13:55:25Z, line 71648: "Stale is correctness").
* **p2:** quire's user-visible features, and the developer experience of other
  bats app developers. Shell tools count under this rule, since changing them
  means scripting shell instead of implementing bats. Moving a pin automatically is
  developer experience (owner, 2026-10-20T13:44:43Z, line 55321: "It's p2, because it's devex (pinning itself is p0, but automatically repinning is devex)");
  so is removing an old form kept for compatibility, and a ticket that only comments on a
  measurement is no ticket (owner, 2026-10-22T22:02:54Z, line 73778: "I don't need tickets that comment on something with measurement.").
* **p3:** everything else; a session may file p3 issues but does not work on
  them.

Order of work. The owner's words (owner, 2026-10-22T11:51:04Z, transcript line 71275): "Worker in progress first", "Open pr second", then "P0", "P1", "P2", and "Within a category, oldest wins." So:

1. A worker in progress is never stopped for a new priority, unless it is an emergency (owner, 2026-10-20T00:50:04Z, line 47690: "If a worker works on it, unless it's an emergency, it should be allowed to finish.") "Prioritize" means jump the queue, not interrupt, unless the owner says to stop a worker (owner, 2026-10-22T02:13:24Z, line 68885: "unless I explicitly say to stop a worker, "prioritize" means jump the queue, not interrupt").
2. An open pull request is finished, whatever its priority (owner, 2026-10-20T00:50:04Z, line 47690: "If a PR is open and no worker is working on it, and it's still relevant, regardless of priority, it should be finished."), oldest first, with nothing else ranking them: a fix does not come before an older review (owner, 2026-10-26T13:57:38Z, line 105684: "No, among them oldest first."). A pull request that is neither green nor red cannot be worked on (owner, 2026-10-26T14:05:11Z, line 105788: "if it is not green and not red, it can't be worked on").
3. A pull request that is ready to merge is merged before anything else, still within the pressure rules (owner, 2026-10-26T19:34:21Z, line 109484: "merging PRs that are ready to be merged takes priority over everything else"; 2026-10-26T19:37:01Z, line 109557: "first, but still respectful of pressure rules").
4. Then tickets: p0, then p1, then p2, oldest opened first. A p1 is not started while a p0 can be worked; a p0 that a worker has in hand, or that is blocked, cannot be, and an agent row is never left empty for the order (owner, 2026-10-26T03:03:00Z, line 100831: "THE RULES SAY SLOTS ARE NEVER EMPTY"; 2026-10-21T10:45:34Z, line 61554: "I said explicitly that PRs in flight trump everything else").
5. A blocked ticket has no priority while it is blocked, and its blockers inherit its priority and its age (owner, 2026-10-22T11:52:56Z, line 71296: "A blocker inherits age from what it blocks."; 2026-10-26T04:49:16Z, line 103163: "while it's blocked, it has NO priority. Something from 120BCE with priority 0 is not worked on if it has blockers. The blockers inherit the priority."). A blocked ticket is not started, not even for a piece of it (owner, 2026-10-24T04:51:42Z, line 82652: "DON'T START THE AGENT").

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


A pull request that changes a published signature (of a package, in its repository) does what that section's rule says: a breaking change to a published signature is made in two steps, never one. The new form is added beside the old one, named by what it adds (as `_proved` is); the old one is marked deprecated in a one-line comment that names its area by keyword and its removal ticket; a test calls the old form, so an edit cannot drop it. One published version holds both. The ticket that removes the old form is filed with the change, as p2, with a p2 ticket for each dependent's move to the new form, and the removal is blocked on them (owner, 2026-10-27T15:31:29Z, transcript line 119703: "File the tickets against the dependents as p2 right now though, and mark it blocked on them"): removing an old form is cleanup, not a correctness defect, and a higher priority would put it ahead of every p2 feature. When it was filed is never a finding (owner, 2026-10-25T05:27:02Z, transcript line 92487: "it wasn't even a rule, it was being "fence around the torah" for no good reason"; 2026-10-25T00:11:51Z, line 91136: "Who cares when it was filed").

The review of such a pull request checks both steps, each one: the old form is still there, beside the new one; a test calls the old form; the old form has a deprecation comment that names the area by keyword and the removal ticket; the removal ticket exists, is p2, and is cited in the deprecation comment. A pull request that changes a published signature in place gets `Verdict: changes needed`. The brief templates carry the line (`.claude/orchestration.md`, "Briefs and the machine"), and `tests/static/guidelines.py` refuses a brief or a review of a signature change that lacks it.

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

The owner's ruling is that pins move from the relock alone and that no bot opens a pull request (owner, 2026-10-23T01:15:16Z, transcript line 74799: "I don't want these bots opening PRs. I want to do everything from relock"); the relock moves actions, npm packages and the Gradle wrapper from the command line (repository-prototype#392, #414 to #416). Quire still has `.github/dependabot.yml`, which #996 removes once quire's `relock.yml` uses those moves. Until then, which tool moves which pin (`.github/dependabot.yml`, weekly, a 7-day cooldown, one pull request
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
checkout), so it is incremental. Short jobs run locally and CI runs the rest (the owner's words, as
quoted in quire#911, filed 2026-10-26T17:49:33Z: "I said "no long jobs", not "try to find clever ways to run them". Short jobs
locally, CI for the rest"): a check that takes more than a few minutes locally, the first
build of a new checkout included, is left to CI and not started here (foreground or background, whole or
split); the worker commits, pushes when the push rule allows, and CI is the evidence, named
in the PR body as CI's; nothing is left running at hand-back. A run over a population (the
static fixtures, the e2e specs, the mutation lemmas) is a random sample of it that fits in a
few minutes, drawn with a seed that is printed, with the sample and why it suffices written
in the PR; CI runs the whole population. A fix pushed after a red CI is checked the same way
first. How (the compiler, the machine's slots and env file, the cache,
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
