#!/bin/sh
# Static tests: every element id made at one place and every id named
# made (ids.py); every match a case+ (case_plus.py); code that must
# type-check, and code that must not.
# What they test is private to a module (a dataprop's constructor, a
# cell's states), so a fixture is not a package of its own: it is a
# snippet (snippet.bats) that is put into a copy of this checkout, in the
# file named in its `file`, before the line equal to its `before`.
# Each fixture under tests/static/accept/ must then pass `bats check`;
# each under tests/static/reject/ must fail it, exactly as its `expect`
# says (below).
#
# With members named, it runs only those (CI's static groups, in
# tests/groups.json, each run by a job of its own): `check` (bats check of
# the app itself), `checkers` (ids.py, case_plus.py, groups.py, with their
# fixtures, affected_test.py, and guidelines.py with its test), `solver`, `mutation/<module>`, and fixtures, `accept/<name>` or `reject/<name>`. With none,
# it runs the checkers and every fixture (the mutation members, which take
# minutes a module, only when named: mutation/<module>, see below).
#
# A fixture knows what proof fails when it is built. A reject fixture's
# `expect` names the function of its snippet, the line of the snippet
# patsopt reports, and patsopt's error word for word:
#
#   function <name>
#   line <n>
#   <the error, after "error(N): ", and the lines patsopt adds to it>
#
# and passes only when that is what the check fails with and nothing else:
# in the module the snippet is in, at that line, in that function. A
# substring another error could also hold is not enough.
#
# The fixtures are run by `bats fixtures` (bats-lang/bats#267, quire#598),
# not by this script: it copies the checkout to <work>/app, checks it whole
# first (the fixtures mean nothing if the app does not check), and puts each
# snippet into that copy with its build as the check left it, so only the
# module the snippet is in is checked again. It keeps the result of each
# fixture in a memo (<work>/memo), served only when every file patsopt reads
# for the module is unchanged, so a typical group re-runs the fixtures a
# change can reach. --cold (first argument) is its --cold: no memo is
# served, and one that would have been is audited against the cold result
# (CI's push to main, the nightly run). It is not BATS_COLD, which would also
# make every check cold: 3 to 5 minutes a fixture. Which compiler, ATS2, C compiler or
# flags made a build/ is bats's to judge (its stamp): nothing here does.
#
# (A pull request restores the newest earlier cache whatever made it: a restore
# of another bats, ATS2 or C compiler is dropped by bats's stamp, #622.)
# usage: tests/static/run.sh [--cold] <repository-dir> [<member> ...]
#        (bats must be on PATH)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# QUIRE_STATIC_WORK names the working directory (CI, #460): kept at the end,
# so that a cache can save what bats keeps there (app/build, memo) and a later
# job restore it before the run. It need not be at the same path (bats strips
# the checkout's path from what it keeps, bats-lang/bats#250). Otherwise a
# temporary one.
if [ -n "${QUIRE_STATIC_WORK:-}" ]; then
  TMP=$QUIRE_STATIC_WORK
  mkdir -p "$TMP"
else
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
fi
cold=""
if [ "${1:-}" = --cold ]; then cold=--cold; shift; fi
repository=$1
shift
all=yes
[ $# -eq 0 ] || all=no
named() { # member -> 0 when it is to run
  [ $all = yes ] && [ "$1" != check ] && return 0
  for member in $selected; do [ "$member" = "$1" ] && return 0; done
  return 1
}
selected="$*"
for member in $selected; do
  case $member in
    check|checkers|solver) ;;
    mutation/*) python3 "$ROOT/tests/static/mutation_check.py" --list --root "$ROOT" --member "$member" >/dev/null 2>&1 || { echo "no proof module $member"; exit 2; } ;;
    accept/*|reject/*) [ -d "$ROOT/tests/static/$member" ] || { echo "no fixture $member"; exit 2; } ;;
    *) echo "not a member: $member"; exit 2 ;;
  esac
done

# The fixtures to run, as accept/<name> and reject/<name>
fixtures=""
# The proof modules to mutate: members mutation/<module> or
# mutation/<module>-part<i>of<n> (tests/static/mutation_modules.txt)
mutation_members=""
for member in $selected; do
  case $member in mutation/*) mutation_members="$mutation_members $member" ;; esac
done
# With QUIRE_MUTATION_BASE (a git revision: CI's pull requests), only the lemmas
# the change since it can have made vacuous (mutation_check.py --diff); a member
# with none needs no compiled app
mutation_diff=""
[ -z "${QUIRE_MUTATION_BASE:-}" ] || mutation_diff="--diff $QUIRE_MUTATION_BASE"
mutation_run=""
for member in $mutation_members; do
  if python3 "$ROOT/tests/static/mutation_check.py" --list --root "$ROOT" $mutation_diff --member "$member" | grep -q '^control'; then
    mutation_run="$mutation_run $member"
  else
    echo "ok   $member: no lemma to mutate (the change since ${QUIRE_MUTATION_BASE:-the start} touches none, or the part has none)"
  fi
done
for verdict in accept reject; do
  for d in "$ROOT"/tests/static/$verdict/*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    if named "$verdict/$n"; then fixtures="$fixtures $verdict/$n"; fi
  done
done

fail=0

# The app itself, checked whole in a copy of the checkout (with its
# fetched modules, not its outputs): as `check`, and as what the mutation
# members start from
app="$TMP/app"
# The copy has no .git, and bats writes the commit's facts (the version,
# src/version.bats) from git: it reads the checkout's repository
GIT_DIR=$(git -C "$ROOT" rev-parse --absolute-git-dir)
export GIT_DIR
if named check || [ -n "$mutation_run" ]; then
  mkdir -p "$app"
  (cd "$ROOT" && tar cf - --exclude=./node_modules --exclude=./dist \
    --exclude=./build --exclude=./test-results --exclude=./.git .) | (cd "$app" && tar xf -)
  if (cd "$app" && bats check --repository "$repository") > "$TMP/app.log" 2>&1; then
    if named check; then echo "ok   check"; fi
  elif named check; then echo "FAIL check:"; cat "$TMP/app.log"; fail=1
  else echo "FAIL check (the app, which the mutation members start from):"; cat "$TMP/app.log"; fail=1; fi
fi

# Element ids (ids.py): the app's own, and the checker's fixtures, each
# a src.bats that must pass it or (reject/) fail it with its `expect`
if named checkers; then
if python3 "$ROOT/tests/static/ids.py" "$ROOT/src" > "$TMP/ids.log" 2>&1; then echo "ok   ids: $(tail -1 "$TMP/ids.log")"
else echo "FAIL ids:"; cat "$TMP/ids.log"; fail=1; fi
for d in "$ROOT"/tests/static/ids/accept/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if python3 "$ROOT/tests/static/ids.py" "$d" > "$TMP/ids-$n.log" 2>&1; then echo "ok   ids/accept/$n"
  else echo "FAIL ids/accept/$n: should pass"; cat "$TMP/ids-$n.log"; fail=1; fi
done
for d in "$ROOT"/tests/static/ids/reject/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if python3 "$ROOT/tests/static/ids.py" "$d" > "$TMP/ids-$n.log" 2>&1; then echo "FAIL ids/reject/$n: should be rejected"; fail=1
  elif grep -qF -- "$(cat "$d/expect")" "$TMP/ids-$n.log"; then echo "ok   ids/reject/$n"
  else echo "FAIL ids/reject/$n: rejected, but not with: $(cat "$d/expect")"; cat "$TMP/ids-$n.log"; fail=1; fi
done

# The mutation checker, on lemmas whose verdict is known (mutation_test.py,
# quire#594): the operators, the edit of a recursive lemma, the choice of
# lemmas by a diff, and that a vacuous lemma is flagged
if python3 "$ROOT/tests/static/mutation_test.py" > "$TMP/mutation_test.log" 2>&1; then echo "ok   mutation_test: $(tail -1 "$TMP/mutation_test.log")"
else echo "FAIL mutation_test:"; cat "$TMP/mutation_test.log"; fail=1; fi

# Which groups a change can affect (scripts/affected.py, quire#619): the
# rule's cases, the e2e import graph, and the claim of each rule that selects
# nothing, checked against the text of what could read the path
if python3 "$ROOT/tests/static/affected_test.py" > "$TMP/affected_test.log" 2>&1; then echo "ok   affected_test: $(tail -1 "$TMP/affected_test.log")"
else echo "FAIL affected_test:"; cat "$TMP/affected_test.log"; fail=1; fi

# The agents' guidelines and the phrases and form of what they write
# (guidelines.py, quire#751): the guideline files hold no exit clause, no rule
# the owner never wrote and no contradiction; the checker's own cases
if python3 "$ROOT/tests/static/guidelines.py" "$ROOT" > "$TMP/guidelines.log" 2>&1; then echo "ok   guidelines: $(tail -1 "$TMP/guidelines.log")"
else echo "FAIL guidelines:"; cat "$TMP/guidelines.log"; fail=1; fi
if python3 "$ROOT/tests/static/guidelines_test.py" > "$TMP/guidelines_test.log" 2>&1; then echo "ok   guidelines_test: $(tail -1 "$TMP/guidelines_test.log")"
else echo "FAIL guidelines_test:"; cat "$TMP/guidelines_test.log"; fail=1; fi

# A fixture anchors on a marker line, not on a comment's prose (anchors.py,
# quire#983): the fixtures here, and the checker's own, each a tree of
# fixtures that must pass it (accept/) or fail it with its `expect` (reject/)
if python3 "$ROOT/tests/static/anchors.py" "$ROOT/tests/static" "$ROOT" > "$TMP/anchors.log" 2>&1; then echo "ok   anchors: $(tail -1 "$TMP/anchors.log")"
else echo "FAIL anchors:"; cat "$TMP/anchors.log"; fail=1; fi
for d in "$ROOT"/tests/static/anchors/accept/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if python3 "$ROOT/tests/static/anchors.py" "$d" > "$TMP/anchors-$n.log" 2>&1; then echo "ok   anchors/accept/$n"
  else echo "FAIL anchors/accept/$n: should pass"; cat "$TMP/anchors-$n.log"; fail=1; fi
done
for d in "$ROOT"/tests/static/anchors/reject/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if python3 "$ROOT/tests/static/anchors.py" "$d" > "$TMP/anchors-$n.log" 2>&1; then echo "FAIL anchors/reject/$n: should be rejected"; fail=1
  elif grep -qF -- "$(cat "$d/expect")" "$TMP/anchors-$n.log"; then echo "ok   anchors/reject/$n"
  else echo "FAIL anchors/reject/$n: rejected, but not with: $(cat "$d/expect")"; cat "$TMP/anchors-$n.log"; fail=1; fi
done

# The solver's 32 bits (literals.py) and the library's keys (keys.py)
if python3 "$ROOT/tests/static/literals.py" "$ROOT/src" > "$TMP/literals.log" 2>&1; then echo "ok   literals: $(tail -1 "$TMP/literals.log")"
else echo "FAIL literals:"; cat "$TMP/literals.log"; fail=1; fi
if python3 "$ROOT/tests/static/keys.py" "$ROOT/src" > "$TMP/keys.log" 2>&1; then echo "ok   keys: $(tail -1 "$TMP/keys.log")"
else echo "FAIL keys:"; cat "$TMP/keys.log"; fail=1; fi

# The HIGH rows of the proofs audit each have a verdict, and the verdict's fixtures are there (proofs_audit.py,
# quire#840 over src/ and #841 over the locked packages); the audit's own cases, a row injected without a
# verdict among them
if python3 "$ROOT/tests/static/proofs_audit_test.py" > "$TMP/proofs_audit_test.log" 2>&1; then echo "ok   proofs_audit_test: $(tail -1 "$TMP/proofs_audit_test.log")"
else echo "FAIL proofs_audit_test:"; cat "$TMP/proofs_audit_test.log"; fail=1; fi
if python3 "$ROOT/tests/static/proofs_audit.py" --fail-on high "$ROOT/src" > "$TMP/proofs_audit.log" 2>&1; then echo "ok   proofs_audit src: $(tail -1 "$TMP/proofs_audit.log")"
else echo "FAIL proofs_audit src:"; grep -E '^(NO|BAD) VERDICT' "$TMP/proofs_audit.log"; fail=1; fi
if python3 "$ROOT/tests/static/proofs_audit.py" --fail-on high --lock "$ROOT/bats.lock" --repository "$repository" > "$TMP/proofs_audit_lock.log" 2>&1; then echo "ok   proofs_audit lock: $(tail -1 "$TMP/proofs_audit_lock.log")"
else echo "FAIL proofs_audit lock:"; grep -E '^(NO|BAD) VERDICT' "$TMP/proofs_audit_lock.log"; fail=1; fi

# A group added to the records is "added", with the library of the table
# before it (groups.py, quire#515): the app's own, and the checker's fixtures,
# each a checkout's scripts/record_tables.py and e2e/old-library.spec.js
# that must fail it with its `expect`
if python3 "$ROOT/tests/static/groups.py" "$ROOT" > "$TMP/groups.log" 2>&1; then echo "ok   groups: $(tail -1 "$TMP/groups.log")"
else echo "FAIL groups:"; cat "$TMP/groups.log"; fail=1; fi
for d in "$ROOT"/tests/static/groups/reject/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if python3 "$ROOT/tests/static/groups.py" "$d" > "$TMP/groups-$n.log" 2>&1; then echo "FAIL groups/reject/$n: should be rejected"; fail=1
  elif grep -qF -- "$(cat "$d/expect")" "$TMP/groups-$n.log"; then echo "ok   groups/reject/$n"
  else echo "FAIL groups/reject/$n: rejected, but not with: $(cat "$d/expect")"; cat "$TMP/groups-$n.log"; fail=1; fi
done

# Every match a case+ (case_plus.py): the app's own, and the checker's
# fixtures, each a src.bats that must fail it with its `expect`
if python3 "$ROOT/tests/static/case_plus.py" "$ROOT/src" > "$TMP/case.log" 2>&1; then echo "ok   case+: $(tail -1 "$TMP/case.log")"
else echo "FAIL case+:"; cat "$TMP/case.log"; fail=1; fi
for d in "$ROOT"/tests/static/case/reject/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if python3 "$ROOT/tests/static/case_plus.py" "$d" > "$TMP/case-$n.log" 2>&1; then echo "FAIL case/reject/$n: should be rejected"; fail=1
  elif grep -qF -- "$(cat "$d/expect")" "$TMP/case-$n.log"; then echo "ok   case/reject/$n"
  else echo "FAIL case/reject/$n: rejected, but not with: $(cat "$d/expect")"; cat "$TMP/case-$n.log"; fail=1; fi
done

# No button's text holds the chevron (glyphs.py, quire#361): the app's
# own, and the checker's fixtures, each a src.bats that must fail it
# with its `expect`
if python3 "$ROOT/tests/static/glyphs.py" "$ROOT/src" > "$TMP/glyphs.log" 2>&1; then echo "ok   glyphs: $(tail -1 "$TMP/glyphs.log")"
else echo "FAIL glyphs:"; cat "$TMP/glyphs.log"; fail=1; fi
for d in "$ROOT"/tests/static/glyphs/reject/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if python3 "$ROOT/tests/static/glyphs.py" "$d" > "$TMP/glyphs-$n.log" 2>&1; then echo "FAIL glyphs/reject/$n: should be rejected"; fail=1
  elif grep -qF -- "$(cat "$d/expect")" "$TMP/glyphs-$n.log"; then echo "ok   glyphs/reject/$n"
  else echo "FAIL glyphs/reject/$n: rejected, but not with: $(cat "$d/expect")"; cat "$TMP/glyphs-$n.log"; fail=1; fi
done

# No :has() on an ancestor of the chapter (has_root.py, quire#538): the
# app's own, and the checker's fixtures
if python3 "$ROOT/tests/static/has_root.py" "$ROOT/src" > "$TMP/has_root.log" 2>&1; then echo "ok   has_root: $(tail -1 "$TMP/has_root.log")"
else echo "FAIL has_root:"; cat "$TMP/has_root.log"; fail=1; fi
for d in "$ROOT"/tests/static/has_root/reject/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if python3 "$ROOT/tests/static/has_root.py" "$d" > "$TMP/has_root-$n.log" 2>&1; then echo "FAIL has_root/reject/$n: should be rejected"; fail=1
  elif grep -qF -- "$(cat "$d/expect")" "$TMP/has_root-$n.log"; then echo "ok   has_root/reject/$n"
  else echo "FAIL has_root/reject/$n: rejected, but not with: $(cat "$d/expect")"; cat "$TMP/has_root-$n.log"; fail=1; fi
done

# A choice of more than three is not cycled by a button (next.py,
# quire#377): the app's own, and the checker's fixtures
if python3 "$ROOT/tests/static/next.py" "$ROOT/src" > "$TMP/next.log" 2>&1; then echo "ok   next: $(tail -1 "$TMP/next.log")"
else echo "FAIL next:"; cat "$TMP/next.log"; fail=1; fi
for d in "$ROOT"/tests/static/next/reject/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if python3 "$ROOT/tests/static/next.py" "$d" > "$TMP/next-$n.log" 2>&1; then echo "FAIL next/reject/$n: should be rejected"; fail=1
  elif grep -qF -- "$(cat "$d/expect")" "$TMP/next-$n.log"; then echo "ok   next/reject/$n"
  else echo "FAIL next/reject/$n: rejected, but not with: $(cat "$d/expect")"; cat "$TMP/next-$n.log"; fail=1; fi
done

# The error banner is said from a failure (notice.py, quire#360): the
# app's own, and the checker's fixtures, each a src.bats that must fail
# it with its `expect`
if python3 "$ROOT/tests/static/notice.py" "$ROOT/src" > "$TMP/notice.log" 2>&1; then echo "ok   notice: $(tail -1 "$TMP/notice.log")"
else echo "FAIL notice:"; cat "$TMP/notice.log"; fail=1; fi
for d in "$ROOT"/tests/static/notice/reject/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if python3 "$ROOT/tests/static/notice.py" "$d" > "$TMP/notice-$n.log" 2>&1; then echo "FAIL notice/reject/$n: should be rejected"; fail=1
  elif grep -qF -- "$(cat "$d/expect")" "$TMP/notice-$n.log"; then echo "ok   notice/reject/$n"
  else echo "FAIL notice/reject/$n: rejected, but not with: $(cat "$d/expect")"; cat "$TMP/notice-$n.log"; fail=1; fi
done
fi

# The solver's own fixtures (solver.py, quire#594): true and false statements
# of the shapes the proofs use, run by the patsopt on the machine (CI's is the
# infinite-precision build; the -int build is known to accept 5 of the false
# ones), so a move back to a solver that cannot be trusted fails here. Each reject fixture says how it is
# rejected (its .expect). The fixtures written from the sources (quire#837 to #841: the palette's luminance
# constants, the lemmas no mutation reaches, the guard of each dataprop constructor, the contexts the audit
# flags) are written again from the modules and the locked packages and must be what is committed
if named solver; then
  if python3 "$ROOT/tests/static/solver.py" > "$TMP/solver.log" 2>&1; then echo "ok   solver: $(tail -1 "$TMP/solver.log")"
  else echo "FAIL solver:"; grep -v '^ok' "$TMP/solver.log"; fail=1; fi
  for generator in gen_luminance gen_lemmas gen_guards gen_vacuity; do
    if python3 "$ROOT/tests/static/solver/$generator.py" --check --lock "$ROOT/bats.lock" --repository "$repository" > "$TMP/$generator.log" 2>&1; then echo "ok   solver/$generator: $(tail -1 "$TMP/$generator.log")"
    else echo "FAIL solver/$generator:"; cat "$TMP/$generator.log"; fail=1; fi
  done
fi

# The fixtures (bats-lang/bats#267): `bats fixtures` copies the checkout to
# $TMP/app, which the check above left its build in, and keeps its memo in
# $TMP/memo. With none named, every fixture
if [ -n "$fixtures" ]; then
  only=""
  if [ $all = no ]; then
    for member in $fixtures; do only="$only --only $member"; done
  fi
  if (cd "$ROOT" && bats fixtures tests/static $only $cold --work "$TMP" --memo "$TMP/memo" \
        --repository "$repository"); then :
  else fail=1; fi
fi
# Every lemma of the proof modules has its false variant rejected
# (mutation_check.py, quire#594): a mutant the compiler accepts is a lemma
# whose context is contradictory. Runs in the checked copy after the
# fixtures (it leaves its build changed) and puts each module back.
for member in $mutation_run; do
  if (cd "$app" && BATS_CHECK="bats check --repository $repository" python3 "$ROOT/tests/static/mutation_check.py" \
        --run "$app" --root "$ROOT" $mutation_diff --known "$ROOT/tests/static/mutation_known.txt" \
        --member "$member") > "$TMP/mutation.log" 2>&1; then echo "ok   $member: $(tail -1 "$TMP/mutation.log")"
  else echo "FAIL $member:"; cat "$TMP/mutation.log"; fail=1; fi
done
exit $fail
