---
name: sweep
description: One look at every open PR of quire and the library repositories, the runner pressure, stray checkouts and the slot ledger. Use at a check-in, after a push, before filling a free agent slot, or when a notification says a check failed.
---

`qsweep` and `slots` are STOPGAPS kept here (quire#751). The move into bats is bats-lang/bats#435; bats#431 moves the text lint they sit beside. quire#573 (p3) keeps them in the repository as a skill; its comments name pitboss, a Python package in dev-skill-up/pitboss, which is not bats and is not this move. They are non-bats code: bats has no program today that calls the GitHub REST API and reads worktrees, and the avenue exhausted is named in each file's header.

Install on a machine (the running copy is a copy of these files): `install -m 755 .claude/skills/sweep/qsweep .claude/skills/sweep/slots /usr/local/bin/`.

## qsweep

* `qsweep` (no argument): each open quire PR on one line: `[mergeable_state]`, `checks=` (the number of check-runs on the head), `pending=`, `fails=[...]`, `statuses-red=[...]` (commit statuses `text-lint` and the like that failed), `review=` (the newest trusted review comment, matched on its first line only: `approved` or `changes-needed`, `-this-head` or `-older-head`), and one of:
  * `FIX-NEEDED`: a check or status of the head is red, the PR has a merge conflict (`dirty`), or the newest review names this head and says changes needed;
  * `WAIT-FOR-CI`: no check-run yet, one not finished, or the aggregate `check` not green. No reviewer starts;
  * `READY-FOR-REVIEW`: at least one check-run, all finished, `check` green, no red status, no review of this head. A reviewer starts;
  * `REVIEWED-approved`.
  Then `NEXT FOR A FREE SLOT`: a fix for the PRs above, else a review, else the oldest ticket of the highest priority (pitboss `rules.md`, "Agents and slots").
* The library PRs, of the repositories `qsweep repositories` prints (the one list the sweep reads; this file does not copy it), with their checks, the review and the gate's own status with its reason. The `NEXT FOR A FREE SLOT` line orders each category oldest first by the PR's creation date across quire and all of them.
* `STRAY-WORK`: the orchestrator's checkout (`/home/user/<repo>`) that is off main or not clean; `STRAGGLER`: work that exists only on this machine; `REUSABLE WORKTREE`: a finished worktree for the next ticket's branch.
* `qsweep pressure`: prints `runner pressure: none` and exits 0, or a hold line and exits 1.
* `qsweep push <git push arguments>`: the pressure check and the push in one command.
* `qsweep clean`: prune worktrees; at 90 percent disk remove a worktree whose pull request merged and whose tip is in `origin/main`, never the persistent checkout (the one that merged last), a ticket in flight, or the orchestrator's checkout (the orchestrator's own working rule, not the owner's).

## slots

`slots` prints a hand-kept ledger with a row for each agent that runs. Only an explicit instruction from the owner changes the rows. It is a note, never the state of the agents: `ListAgents` is. `slots set SLOT AGENT TASK`, `slots free SLOT`, `slots check N` (exits 1 when N is above the number of rows).
