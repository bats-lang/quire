# Orchestration: the standing rules of the session that runs the workers

This file is for the orchestrator (the session that spawns workers, reviews and merges), not for the workers: it is not under `.claude/rules/` or `.claude/skills/`, so nothing loads it by itself. The orchestrator rereads it at the start of every session and after every compaction. The owner's words are the authority; when a rule here and the owner's last word differ, the owner's last word wins and this file is changed the same day.

## Priorities

The priorities (p0 to p3), the order of work, the owner's rule on downgrades and the Android-release hold are defined once, in quire's `CLAUDE.md`, section "Priorities". This file does not restate them. The orchestrator works tickets in that order.

## Agents and slots

* **At most two agents run at any time, reviewers included** (owner, 2026-10-18). A review takes a slot like any work. Never a third agent beside two busy slots.
* **A queued review of a finished PR comes first.** When a slot frees, a PR whose author is done and is waiting for its review takes the slot before any new ticket, because the review unblocks a merge.
* **A reviewer for a PR in progress is the last resort.** A PR whose author is still working is reviewed only when no review is queued and no ticket fits the free slot. A ticket always comes before it.
* The ledger is the `slots` command (`slots`, `slots set SLOT AGENT TASK`, `slots free SLOT`); `qsweep` ends with it. Slots now: one sonnet and one haiku (the owner's word, quota, 2026-10-17); it changes only when the owner says.
* **Never an empty slot** (owner, hard rule). Never, under any circumstances, is an empty worker slot acceptable. The moment a slot frees (a worker hands back, a reviewer finishes), the next piece of work starts in it in the same turn: a queued review of a finished PR first, else the oldest fitting p0, else p1, else p2, else (only if nothing else exists) a reviewer for a PR in progress. "Nothing fits" is not an answer: break a ticket up, take a conflicted PR, or take a p1/p2. Record it with `slots set` and start the worker; setting the ledger does not start one, calling Agent does. A scheduled hourly slot check fills any empty slot by these rules.
* Every agent, haiku included, takes the highest-priority, oldest ticket it can fix. A haiku takes the oldest p0 when unsure; it is never asked whether it can. Judge by the outcome: a diff that is totally off, or a worker that stops midway, is enough to decide it cannot; then the ticket goes to a sonnet and the haiku takes the next p0. A haiku takes a p1 or lower only when no p0 exists that it can accomplish (a p0 that would touch the files of an open PR is not available: no stacked PRs).
* Reviewers are separate agents from the author, one at a time, briefed with the repository's own rules, the issue's goal and the kind of change. No invented threat models. Never say "human review".

## Merge conflicts

* **A PR with a merge conflict is a PR in progress** (owner, 2026-10-18). It comes before any new ticket, in the same order as an unreviewed or red PR: it does not stop a worker that is running, but it is next in line for the next free slot.
* Most conflicts are haiku-level: merge main in, resolve, regenerate lockfiles or `bootstrap/c` with the repository's own tooling, check, push. Merge, never rebase or force-push. A conflict where both sides changed the same logic goes to a sonnet.
* Every sweep lists the open PRs whose mergeable state is dirty or conflicting.

## Tickets

* **A ticket that should be several is broken up BEFORE work starts** (owner, 2026-10-18). An agent that finds a ticket holding more than one piece of work files one ticket per piece, taken from the steps already in the ticket (not new scope), closes the original with a comment "Broken into #a, #b, #c", and then works the pieces in the order planned. A piece that depends on another says so in its body ("This ticket cannot be worked on until #n is resolved"). The new tickets inherit the priority and labels of the ticket they break. An umbrella whose pieces all exist as tickets is closed the same way. Every worker brief carries this rule.
* **A flake ticket is closed only when the work was already done** (owner, 2026-10-18): the cause found and fixed, or the instruments and analysis built so the next failure arrives with data. Never closed in place of work. With no known cause, root-cause it first with the instruments built for it (stall capture, gdb on crashes and hangs, diagnostics, a lab loop); where the capture is not enough, the ticket's action is "add the data capture". With a known cause, fix it. A ticket whose only content is "wait and see" is closed at once; no "watch" ticket stands in for work. If a closure was a misreading, reopen it with the actionable item.

## Briefs and the machine

* A brief names the ticket, the files and docs to read, the repository's own rules, the kind of change, the check before pushing, and the rules above that apply. It says: finish inside the turn (foreground loops, Bash timeout up to 600000 ms), do not merge, do not write the review.
* **"This machine lacks X" is never an excuse** (owner, 2026-10-18), unless fixing it is physically impossible. If CI has a tool, package, browser, voice, font or setting a test needs, the worker installs it on its machine (apt as root, a scratch HOME for per-user things), runs the real thing, and documents the setup in quire's "Check locally" section. A report that says "did not run: the machine lacks" is sent back.
* **`/dev` is never touched by a worker** (owner, 2026-10-18, after two workers damaged `/dev/null`). Never create, move, link or delete anything under `/dev`, and never redirect output to `/dev/null`. A brief says so.
* **Disk is a shared allowance** (it hit 100 MB and killed a worker's build). After a PR merges or is closed, the orchestrator deletes its worker clone and build directories (`rm -rf` of that directory only). A worker deletes its own build directories when done. Keep the shared browsers directory and the GMP ATS2 install.

## Pushing and merging

* Before any push or merge: `qsweep pressure` (prints one line, exits 0 only on `runner pressure: none`). Under pressure, hold and wait; do not push.
* At most 2 merge-queue entries. Cancel superseded runs (the queue's `supersede.yml` does it). No stacked PRs. No hooks. Many small PRs (repins) go in batches of about six with a pressure check before each; avoid bursts: CI capacity is the constraint.
* A PR merges only after an independent review comment for its head. Gated repositories (bridge, pwa, capacitor-plugins) need the exact form their CLAUDE.md gives; a push, an update-branch or a merge of main voids an approval. Use merge, not squash. quire merges through the queue (`enable_pr_auto_merge` MERGE); the others by `merge_pull_request`.
* A PR that adopts new package versions runs `bats lock --repository <dir>` and commits `bats.lock`.

## Published APIs

* **API changes are additive** (owner, 2026-10-19). A change to a published package's API keeps the old signatures and adds the new ones beside them, named in words. Dependents move one at a time, in PRs of their own, under their normal CI; removal of the old form is a separate ticket once every dependent has moved. No lockstep publish, and no archive built outside a dependent's CI. Reason: process#62 replaced `spawn*`, pwa's published archive then failed repository-prototype `verify` in #359, and the fix was process#65, which is additive.
* **Breaking changes have at least one version of overlap** (owner, standing rule). A breaking change to a published API is made in at least two published versions: the first adds the new form beside the old one (both work), and a later one removes the old form once no dependent uses it. No single version may leave a dependent's newest archive unable to type-check. Every brief that touches a published package says so.

## How decisions are made

* Research before design: what comparable software does, written down where it is decided (CLAUDE.md "Decisions are made by research").
* Stop inventing threat models; trust is not a problem the project has. A cache that can be wrong is a correctness bug whoever caused the change.
* A proof is a proof: static, from types and lemmas; say "tested" when only tested. No runtime checks standing in for proofs.
* No mtimes in freshness. We write bats, not shell (quire#646). The bootstrap/c regenerate-and-compare check catches a forgotten update; it is not a security check.
* Report outcomes faithfully: what was not verified, what was not done. Do not claim more than was measured.
* The owner's preferences in the system prompt apply to every message (no analogies unless they help, no "makes you wonder", search before factual claims).

## Open work

The open p0s: `gh api "repos/bats-lang/REPO/issues?labels=p0&state=open"` for quire, bats, bridge, pwa, repository-prototype, sha256, builder, and the rest. One task per issue or PR.
