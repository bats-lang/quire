#!/bin/bash
# PROPOSAL (quire#751, rows 5 and 12): the owner's stop hook, ~/.claude/stop-hook-git-check.sh, as it should be. Install: quire#754 (human only).
# Non-bats code of ours (quire#646). The avenue exhausted: a Claude Code hook is a command line the harness runs, with the stop
# event's JSON on stdin, and the owner's configuration under ~/.claude is not a bats package. A bats program can be that command line once a
# bats binary is installed where the hook runs, and how a bats program reads the stdin JSON is open. The move is bats-lang/bats#436.

# Read the JSON input from stdin
input=$(cat)

# Check if stop hook is already active (recursion prevention)
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active')
if [[ "$stop_hook_active" = "true" ]]; then
  exit 0
fi

# Check if we're in a git repository - bail if not
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# Bail if there's no remote to push to. Every error path below asks the user
# to "push to the remote branch" — meaningless without a remote, and
# unsatisfiable if signing also requires a source. This case arises when CCR
# was launched against a local repo with no github remote (sources=[]) and
# the container's cwd has a leftover .git from a cached resume.
if [[ -z "$(git remote)" ]]; then
  exit 0
fi

# PROPOSAL (quire#751, rows 5 and 12), for the owner to install as ~/.claude/stop-hook-git-check.sh (the ticket has the steps).
# This hook runs in the directory of the session that stops. Workers used to work in that directory (the loaded checkout),
# so the hook fired on work an agent was still doing. A worker now writes, once, when it starts in a checkout:
#   printf '%s\t%s\n' "<agent name>" "<session URL>" > "$(git rev-parse --git-dir)/agent-holder"
# (inside the git directory, so it is never tracked). This hook then checks only this session's own checkout:
# a checkout that names a holder whose session is not this one is skipped, and the hook says which agent holds it.
holder_file="$(git rev-parse --git-dir)/agent-holder"
if [[ -f "$holder_file" ]]; then
  session_id=$(echo "$input" | jq -r '.session_id // empty')
  holder_name=$(cut -f1 "$holder_file")
  holder_session=$(cut -f2 "$holder_file")
  if [[ -z "$session_id" || "$holder_session" != *"$session_id"* ]]; then
    echo "Skipped: this checkout ($(pwd)) is held by agent '$holder_name' (session $holder_session), not by this session; its work is not checked here." >&2
    exit 0
  fi
fi

# Check for uncommitted changes (both staged and unstaged)
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "There are uncommitted changes in the repository. Please commit and push these changes to the remote branch." >&2
  exit 2
fi

# Check for untracked files that might be important
untracked_files=$(git ls-files --others --exclude-standard)
if [[ -n "$untracked_files" ]]; then
  echo "There are untracked files in the repository. Please commit and push these changes to the remote branch." >&2
  exit 2
fi

current_branch=$(git branch --show-current)
if [[ -n "$current_branch" ]]; then
  if git rev-parse "origin/$current_branch" >/dev/null 2>&1; then
    upstream="origin/$current_branch"
  else
    upstream="origin/HEAD"
  fi

  # Check for local commits that GitHub will show as "Unverified": either no
  # signature at all, or a committer email other than noreply@anthropic.com
  # (the identity CCR's signing key is registered to). Only run when commit
  # signing is configured.
  #
  # Signature presence is tested via the raw gpgsig/gpgsig-sha256 header,
  # NOT %G?. CCR/BYOC configure SSH signing (gpg.format=ssh, /tmp/code-sign;
  # byoc.go:754-758) but never set gpg.ssh.allowedSignersFile, so %G?
  # reports 'N' for correctly SSH-signed commits — see
  # api-go/ccr/e2e/byoc/scenario_sign_commit_test.go:117 and
  # antique/cmd/aq/git.go listUnsignedCommits for the same rationale.
  #
  # Scope to commits that are on NO remote ref ($upstream..HEAD would sweep
  # in teammates' already-published commits whenever this branch was cut
  # from a feature branch and has no same-named remote yet —
  # github.com/anthropics/claude-code#69586). Only run when
  # origin/$current_branch resolves (env-manager managed flow:
  # createLocalBranch → UpdateRemoteTrackingBranch, git.go:2496). Not
  # origin/HEAD: a single-branch/shallow clone onto a non-default branch
  # has origin/HEAD but no ref covering the agent's branch's base, so
  # 'HEAD --not --remotes' would sweep in teammates' published commits.
  # Env-manager's SHA-pinned init+fetch checkouts (git.go:2079-2081)
  # don't set origin/$current_branch either, and a later 'git fetch
  # origin main' doesn't set it, so those shapes skip (previously
  # \$upstream=origin/HEAD failed to resolve there and this block
  # silently no-op'd — preserve that). This also skips agent-created
  # branches ('git checkout -b fix-xyz') in full clones — a deliberate
  # false-negative window, traded for never re-introducing an origin/HEAD
  # fallback whose destructive rewrite advice on shallow/single-branch
  # clones is the bug this gate fixes (#69586).
  if [[ "$(git config --type=bool commit.gpgsign 2>/dev/null)" == "true" ]] &&
     git rev-parse -q --verify "origin/$current_branch" >/dev/null 2>&1; then
    local_count="$(git rev-list HEAD --not --remotes --count 2>/dev/null)"
    if [[ -n "$local_count" && "$local_count" -gt 0 ]]; then
      unverifiable=""
      while read -r sha ce; do
        if [[ "$ce" != "noreply@anthropic.com" ]] ||
           ! git cat-file commit "$sha" 2>/dev/null | sed '/^$/q' | grep -qE '^gpgsig(-sha256)? '; then
          unverifiable+="${sha:0:7} $ce"$'\n'
        fi
      done < <(git log --format='%H %ce' HEAD --not --remotes 2>/dev/null)
      if [[ -n "$unverifiable" ]]; then
        # Derive a safe rebase boundary: the parent of the oldest local-only
        # commit, falling back to --root when it has none. Only advise the
        # range rebase when local-only history is a linear chain on top of
        # the boundary — rebase replays the whole <boundary>..HEAD range,
        # not the 'on no remote' set, so a non-linear graph (e.g. after
        # 'git merge origin/main') would replay+reset-author the published
        # commits brought in by the merge.
        oldest_local="$(git rev-list HEAD --not --remotes 2>/dev/null | tail -1)"
        if git rev-parse -q --verify "$oldest_local^" >/dev/null 2>&1; then
          rebase_onto="$oldest_local^"
          range_count="$(git rev-list "$rebase_onto..HEAD" --count 2>/dev/null)"
        else
          rebase_onto="--root"
          range_count="$(git rev-list HEAD --count 2>/dev/null)"
        fi
        echo "There are commit(s) on branch '$current_branch' that GitHub will show as Unverified (missing signature, or committer email is not noreply@anthropic.com):" >&2
        printf '%s' "$unverifiable" >&2
        if [[ "$range_count" == "$local_count" ]]; then
          echo "Please run 'git config user.email noreply@anthropic.com && git config user.name Claude', then 'git commit --amend --no-edit --reset-author' for the tip commit, or 'git rebase --exec \"git commit --amend --no-edit --reset-author\" $rebase_onto' for earlier commits, then push." >&2
        else
          echo "Please run 'git config user.email noreply@anthropic.com && git config user.name Claude', then 'git commit --amend --no-edit --reset-author' for each listed commit (local history is non-linear, so a range rebase would rewrite published commits), then push." >&2
        fi
        exit 2
      fi
    fi
  fi

  unpushed=$(git rev-list "$upstream..HEAD" --count 2>/dev/null) || unpushed=0
  if [[ "$unpushed" -gt 0 ]]; then
    if [[ "$upstream" == "origin/$current_branch" ]]; then
      echo "There are $unpushed unpushed commit(s) on branch '$current_branch'. Please push these changes to the remote repository." >&2
    else
      echo "Branch '$current_branch' has $unpushed unpushed commit(s) and no remote branch. Please push these changes to the remote repository." >&2
    fi
    exit 2
  fi
fi

exit 0
