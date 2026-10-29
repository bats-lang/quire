# quire

## Pitboss's sweep skill

The rules of the process that hold for any project (research before design, a proof is a proof, comments name their area by keyword, names are words, the priorities and the order of work, no shell of our own and no mtimes in freshness, breaking changes with one version of overlap, CI pinned, no cache key relied on, check before a push, evidence, red tests and CI, the version is the commit's, and the standing rules of the orchestrator, the worker and the reviewer) are in pitboss's sweep skill, `plugins/pitboss/skills/sweep/` of dev-skill-up/pitboss: `references/rules.md`, `references/engineering.md`, `references/ci.md` and `references/adversarial-review.md`. Quire's copy is a manual copy at pitboss commit 71ffe84, paths changed; this file and `.claude/` hold only what is quire's, bats's or pwa's. When the copy moves, this commit is changed in the same pull request.

## Decisions are made by research, not left to the human

The quality rules below (the proofs, the static tests, the e2e suite) still hold: when a choice would break one, choose another that keeps it.

## A proof is a proof

Trusted primitives live in the one package that owns the platform, state what they assume, and are tested there; nothing in quire uses `praxi`, `assume` or `$UNSAFE` to skip a proof. Where the proof system cannot reach (the array package had no model of an array's contents), the tool is extended (a content-indexed array API in the array package), not worked around at runtime.

## Names are words

Element ids and numbered-id prefixes (up to 16 bytes) are named in words too: `search-close`, `toc-row12`, not `qsrz`. Terse names collide (a rename of the id `qn` once also hit a query length of the same name).

## Priorities

The priorities (p0 to p3) and the order of work are in the reference, `rules.md`, "Tickets" and "Agents and slots". Quire's own rule on top of them:

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
is not a fix. The rule against shell and other non-bats code of our own (quire#646, quire#731) is in the reference, `engineering.md` and `ci.md`.

## Breaking changes keep at least one published version of overlap (#762)

The rule is in the reference (`rules.md`, "Published APIs") and in repository-prototype's CLAUDE.md, under "Publishing Packages" (https://github.com/bats-lang/repository-prototype/blob/20f15c0/CLAUDE.md, bats-lang/repository-prototype#381 and #384). The brief templates carry the line (`.claude/orchestration.md`, "Briefs and the machine"), and `tests/static/guidelines.py` refuses a brief or a review of a signature change that lacks it.

## CI is pinned

Every input to CI is pinned in the source (#203), so a commit that passes keeps passing:
the packages by the committed `bats.lock`, the compiler by its commit in
`.github/bats-version`, pwa's Android workflow by its commit (`android.yml@<sha>` in
`check.yml`), and the runner image by its label. A quire PR that adopts new package
versions runs `bats lock --repository <dir>` and commits `bats.lock` with the change that
needs them. The build cache and its key, the merge queue, the Node packages, the mutation
check and which groups a change runs are in `.claude/rules/ci.md`, which loads when CI files
are touched.

Quire still has `.github/dependabot.yml`, which #996 removes once quire's `relock.yml` uses the relock's moves of actions, npm packages and the Gradle wrapper (repository-prototype#392, #414 to #416). Until then, which tool moves which pin (`.github/dependabot.yml`, weekly, a 7-day cooldown, one pull request
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

Bats drops a `build/` whose stamp (its own inputs, ATS2, the C compiler, the flags, the target)
differs and says so on stderr, rebuilds a module by the content hash of its sources and of the
files patsopt read, and serves a fixture's memo only when every file it read is unchanged
(bats's CLAUDE.md and its `stamp`, `build-freshness`, `check-memo` and `fixtures-memo` notes).
Quire's key is `quire-<name>@<commit>`, only a locator for the newest earlier cache; it names
no pin, image, lock or source hash and carries no number to bump, so a new input needs no key
edit. What bats does not yet judge is listed in `.claude/rules/ci.md`.

## Check locally before every push

Run `bats check` before every push, so a push that does not type-check never reaches CI. Only
the first build of a new checkout is cold (10 to 15 minutes), and that one runs in the
background and is waited for in the same turn. Under disk pressure `qsweep clean` removes only
an older worktree whose pull request merged, never the one that merged last, a ticket in
flight, or the orchestrator's checkout. How (the compiler, the machine's slots and env file,
the cache, the e2e run): `.claude/rules/ci.md`.

## Evidence, red tests and CI

The rules for the agents are in `.claude/agents/worker.md`, `.claude/agents/reviewer.md` and
`.claude/orchestration.md`, and `tests/static/guidelines.py` (the `checkers` group) refuses
the phrases that made these mistakes come back (quire#751).

## The version is the commit's

How quire's version is made and shown: `.claude/rules/release.md`.

## Play release

A push to main that passes the whole check is released to Google Play's internal testing
track by `check.yml`'s `play-internal` job; production is a promotion in the Play Console
(details: `.claude/rules/release.md`).
