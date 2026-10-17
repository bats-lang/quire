# Orchestration: the standing rules of the session that runs the workers

This file is for the orchestrator (the session that spawns workers, reviews and merges), not for the workers: it is not under `.claude/rules/` or `.claude/skills/`, so nothing loads it by itself. The orchestrator rereads it at the start of every session and after every compaction. The owner's words are the authority; when a rule here and the owner's last word differ, the owner's last word wins and this file is changed the same day.

## Priorities (owner, 2026-10-16 and 2026-10-17)

* **p0:** anything that makes CI faster or more reliable, or makes development faster or more reliable (a wrong cache is p0: it is what makes people run a clean "just in case"; a cost of the agent sessions that lowers what the work costs is p0). All open p0s, in flight or not, come before any p1.
* **p1:** correctness.
* **p2:** quire's user-visible features and the developer experience of other bats app developers (shell tools count).
* **p3:** everything else; a session may file p3 issues and does not work on them.
* No downgrades without the owner's word. An issue's priority is the owner's call; a worker that thinks it is wrong says so on the issue.

## Workers and slots

* The ledger is `slots` (`/usr/local/bin/slots`: `slots`, `slots set SLOT AGENT TASK`, `slots free SLOT`); `qsweep` ends with it. Slots now: one sonnet and one haiku (the owner's word, quota, 2026-10-17); it changes only when the owner says.
* Every agent, haiku included, takes the highest-priority, oldest ticket it can fix. A haiku takes the oldest p0 when unsure; it is never asked whether it can. Judge by the outcome: a diff that is totally off, or a worker that stops midway, is enough to decide it cannot; then the ticket goes to a sonnet and the haiku takes the next p0. A haiku takes a p1 or lower only when no p0 exists that it can accomplish (a p0 that would touch the files of an open PR is not available: no stacked PRs).
* **A slot is never left empty.** In the same turn as a hand-back or a merge that frees one: record it with `slots set` and start the next worker (the ledger saying EMPTY SLOT and the turn ending is the failure that happened twice). Starting a worker means calling Agent; setting the ledger does not start one.
* A brief names the ticket, the files and docs to read, the repository's own rules, the kind of change, the check before pushing, and says: finish inside the turn (foreground loops, Bash timeout up to 600000 ms), do not merge, do not write the review.
* Reviewers are separate agents, one at a time (quota), briefed with the repository's own rules, the issue's goal and the kind of change. No invented threat models. Never say "human review".

## Pushing and merging

* Before any push or merge: `qsweep pressure` (prints one line, exits 0 only on `runner pressure: none`). Under pressure, hold and wait; do not push.
* At most 2 merge-queue entries. Cancel superseded runs (the queue's `supersede.yml` does it). No stacked PRs. No hooks. Many small PRs (repins) go in batches of about six with a pressure check before each; avoid bursts: CI capacity is the constraint.
* A PR merges only after an independent review comment for its head. Gated repositories (bridge, pwa, capacitor-plugins) need the exact form their CLAUDE.md gives; a push, an update-branch or a merge of main voids an approval. Use merge, not squash. quire merges through the queue (`enable_pr_auto_merge` MERGE); the others by `merge_pull_request`.
* A PR that adopts new package versions runs `bats lock --repository <dir>` and commits `bats.lock`.

## How decisions are made

* Research before design: what comparable software does, written down where it is decided (CLAUDE.md "Decisions are made by research").
* Stop inventing threat models; trust is not a problem the project has. A cache that can be wrong is a correctness bug whoever caused the change.
* A proof is a proof: static, from types and lemmas; say "tested" when only tested. No runtime checks standing in for proofs.
* No mtimes in freshness. We write bats, not shell (quire#646). The bootstrap/c regenerate-and-compare check catches a forgotten update; it is not a security check.
* Report outcomes faithfully (what was not verified, what was not done); do not claim more than was measured.
* The owner's preferences in the system prompt apply to every message (no analogies unless they help, no "makes you wonder", search before factual claims).

## What the session carries besides these rules

The task list (one task per issue or PR), the `slots` ledger, and the hourly reminder `trig_01W82XHQWQSUdpaNpSf5zuWP` (fills empty slots by the rules above). The open p0s: `gh api "repos/bats-lang/REPO/issues?labels=p0&state=open"` for quire, bats, bridge, pwa, repository-prototype, sha256, builder, and the rest.
