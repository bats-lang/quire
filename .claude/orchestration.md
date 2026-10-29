# Orchestration: what is quire's, bats's or pwa's in the standing rules of the session that runs the workers

The technology-independent standing rules of the orchestrator (agents and slots, merge conflicts, tickets, plan first, briefs and workers, reviews, pushing and merging, published APIs, checkouts and disk, how decisions are made) are in pitboss's reference, https://github.com/dev-skill-up/pitboss/blob/main/plugins/pitboss/skills/sweep/references/rules.md (`plugins/pitboss/skills/sweep/references/rules.md` of dev-skill-up/pitboss). Read it first, at the start of every session and after every compaction. This file holds only what names quire's, bats's or pwa's tools, queue, CI or files, and no rule that the reference holds. Nothing loads this file by itself (it is not under `.claude/rules/` or `.claude/skills/`). A marker `(owner, <timestamp>)` here carries the owner's words verbatim in quotation marks, as the reference says; `tests/static/guidelines.py` finds a marker that does not.

## Priorities

The priorities (p0 to p3), the order of work, the owner's rule on downgrades and the Android-release hold are defined once, in quire's `CLAUDE.md`, section "Priorities". This file does not restate them. The orchestrator works tickets in that order.

## Agents and slots

* `qsweep`'s `NEXT FOR A FREE SLOT` line orders each category by the PR's creation date, oldest first, across quire and every library repository; `qsweep` prints `READY-FOR-REVIEW` for a PR green on its exact head. Record a spawn with `slots set` after calling Agent (setting the ledger starts nothing).
* The ledger is `/tmp/claude-0/slots.tsv`, the `slots` command (`slots`, `slots set SLOT AGENT TASK`, `slots free SLOT`); `qsweep` ends with it. `slots check N` compares N, the agents `ListAgents` shows, with the number of rows and exits 1 above it.
* **bats's `src/` is the one exception to no predictive scheduling**: a pull request that changes it regenerates `bootstrap/c`, so only one is open at a time and the others wait for it to be merged (owner, 2026-10-23T21:08:02Z: "That's the only exception to the "don't do predictive scheduling" that I'm willing to live with, because there merges cost a lot of extra churn, locally, not just CI, in regenerating"); the next one starts only when the one before is "*DONE DONE*" (owner, 2026-10-24T04:19:13Z: "ONLY WHEN 481 is *DONE DONE* otherwise dirty"). One of them is always in flight, being worked on, reviewed or in CI, so the bats pull requests are not batched (owner, 2026-10-24T22:42:40Z, transcript line 90839: "let's make sure there's always a pr in flight (worked on, reviewed, or Ci) so we don't end up batching them"; 2026-10-28T11:40:05Z, line 126572: "Always have a bats in flight is also a rule"); when none exists, the row works another repository (owner, 2026-10-28T11:39:23Z, line 126553: "Why are you working only in quire issues? That's a sure way to starve runners").

## Plan first

* The pause label of the plan-first rule is `paused-owner`.

## Briefs and the machine

* Before the Agent call, run `python3 tests/static/guidelines.py --brief <brief> --ticket <ticket body>` (the ticket body: `gh api repos/bats-lang/quire/issues/N --jq .body`); a finding is fixed before the brief is sent.
* **A brief for a change to a published signature carries the line** `Overlap: the old form stays beside the new one, with a deprecation comment (area keyword and removal ticket) and a test that calls it; one published version holds both; the p2 removal ticket is filed with the change (CLAUDE.md, "Breaking changes keep at least one published version of overlap").` **A reviewer brief for it carries that line and this one** `Overlap check: the old form is still there beside the new one; a test calls it; it has a deprecation comment naming the area by keyword and the removal ticket; the removal ticket exists, is p2, and is cited in the deprecation comment; a signature changed in place is Verdict: changes needed.` The lint refuses a brief that names a change to a published signature and lacks the matching line (`guidelines.py --brief`), and a review of one that lacks the check (`--review`).
* **A worker brief carries these lines**, each beginning with its label, and `guidelines.py --brief` refuses a brief that names `worker.md` and lacks one: `Design check:`, `Push:`, `Sample:`, `No split:` and `Compiler:` (their text is in the reference, "Briefs and workers"), and the line that is bats's:
  * `Expects: write reject expects with bats fixtures --bless (bats#522) after the last edit of a module, never by hand or by repeated population runs; until bats#522 merges, from the observed error of one run of each changed snippet.`
* **A worker brief that runs an e2e spec carries the line** `Tracefs: after a container restart tracefs may be missing; when the preflight says "no tracefs instances directory", run once grep -q tracefs /proc/mounts || mount -t tracefs nodev /sys/kernel/tracing (the allowed command, ci.md, quire#765, quire#958) and run the spec again; run no other mount.`
* A worker documents the setup of a tool its machine lacked in quire's "Check locally" section. A command the harness refuses is answered by an allow rule in `.claude/settings.json`, in the PR that needs it.
* `python3 tests/static/guidelines.py --text <hand-back>` finds the phrases of a hand-back that is no hand-back.

## Pushing and merging

* A conflict in `bootstrap/c` is resolved by regenerating it with the repository's own tooling.
* `qsweep push <git push arguments>` is the pressure check and the push in one command, and workers push with it; `qsweep pressure` prints one line and exits 0 only on `runner pressure: none`.
* **Quire CI-triggering actions are 15 minutes apart** (orchestrator, 2026-10-28, the owner's ruling of that date). A push to a non-draft quire PR and a merge into quire's main are each at least 15 minutes after the previous one, and each is held while `qsweep pressure` reports pressure.
* **bats PRs that touch `src/` are serialized** (orchestrator, 2026-10-28, the owner's ruling of that date): exactly one is in flight in bats-lang/bats, no more and no less. When it merges, the next is already in hand.
* At most 2 merge-queue entries. Cancel superseded runs (the queue's `supersede.yml` does it).
* Gated repositories (bridge, pwa, capacitor-plugins) need the exact form their CLAUDE.md gives. Use merge, not squash. quire merges through the queue (`enable_pr_auto_merge` MERGE); the others by `merge_pull_request`.
* A PR that adopts new package versions runs `bats lock --repository <dir>` and commits `bats.lock`.

## Checkouts

The checkouts the agents load (`/home/user/<repo>` for each repository: quire, bats, pwa, bridge, dom, gestures, arith, array, zip, sha256, capacitor-plugins, repository-prototype; the 14 files an agent loads are those 12 repositories' CLAUDE.md and the `.claude/rules/bats.md` of bats and of dom) stay on `main` with a clean tree, so the CLAUDE.md an agent reads is the merged one (quire#732); `qsweep` prints `STRAY-WORK` for one that is off main or not clean. Keep the shared browsers directory and the GMP ATS2 install. Under pressure `qsweep` lists the stragglers, the work that exists only on this machine; the cleaning does not wait for 90 percent when the disk is the reason a container restarts. Only when the disk is at 90 percent does `qsweep clean` remove another worktree, and only one whose pull request is merged and whose tip is in `origin/main`; `qsweep` reports a worktree of a finished ticket as reusable. The number is the orchestrator's. The orchestrator fast-forwards each one (`git fetch origin main && git checkout main && git merge --ff-only origin/main`).

## The orchestrator's own working rules (not the owner's)

* `.claude/skills/sweep/` holds `qsweep` and `slots` (quire#751): stopgaps until they move into bats (bats-lang/bats#435). quire#573 (p3) keeps them in the repository as a skill; the Python package its comments name (pitboss, in dev-skill-up/pitboss) is not bats and is not that move.

## How decisions are made

* A proof is a proof: static, from types and lemmas; say "tested" when only tested. No runtime checks standing in for proofs.
* No mtimes in freshness. We write bats, not shell (quire#646). The bootstrap/c regenerate-and-compare check catches a forgotten update; it is not a security check.

## Open work

The open p0s: `gh api "repos/bats-lang/REPO/issues?labels=p0&state=open"` for quire, bats, bridge, pwa, repository-prototype, sha256, builder, and the rest. One task per issue or PR.
