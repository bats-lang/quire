#!/bin/sh
# Static tests: every element id made at one place and every id named
# made (ids.py); every match a case+ (case_plus.py); code that must
# type-check, and code that must not.
# What they test is private to a module (a dataprop's constructor, a
# cell's states), so a fixture is not a package of its own: it is a
# snippet (snippet.bats) that is put into a copy of this checkout, in the
# file named in its `file`, before the line equal to its `before`.
# Each fixture under tests/static/accept/ must then pass `bats check`;
# each under tests/static/reject/ must fail it, with the message in its
# `expect` file (so it is rejected for the right reason).
#
# With members named, it runs only those (CI's static groups, in
# tests/groups.json, each run by a job of its own): `checkers` (ids.py and
# case_plus.py, with their fixtures), and fixtures, `accept/<name>` or
# `reject/<name>`. With none, it runs the checkers and every fixture.
# Before any fixture, the app itself must pass bats check: that also
# fills the build cache each fixture's copy starts from, which halves a
# fixture's time (a reject fixture 1.6 min instead of 3, an accept one 6
# instead of 11, on CI's runners).
#
# usage: tests/static/run.sh <repository-dir> [<member> ...]
#        (bats must be on PATH)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
repository=$1
shift
all=yes
[ $# -eq 0 ] || all=no
named() { # member -> 0 when it is to run
  [ $all = yes ] && return 0
  for member in $selected; do [ "$member" = "$1" ] && return 0; done
  return 1
}
selected="$*"
for member in $selected; do
  case $member in
    checkers) ;;
    accept/*|reject/*) [ -d "$ROOT/tests/static/$member" ] || { echo "no fixture $member"; exit 2; } ;;
    *) echo "not a member: $member"; exit 2 ;;
  esac
done

fail=0

# The app itself, before any fixture (it fills the build cache)
fixtures=$all
for member in $selected; do case $member in accept/*|reject/*) fixtures=yes ;; esac; done
if [ $fixtures = yes ]; then
  if (cd "$ROOT" && bats check --repository "$repository") > "$TMP/app.log" 2>&1; then echo "ok   bats check of the app"
  else echo "FAIL bats check of the app:"; cat "$TMP/app.log"; exit 1; fi
fi

check() { # fixture dir -> 0 when bats check passes; log in $TMP/<name>.log
  n=$(basename "$1")
  w="$TMP/w-$n"
  mkdir -p "$w"
  # the checkout, with its fetched modules and build cache (so only what
  # the snippet changes is compiled again), but not the outputs
  (cd "$ROOT" && tar cf - --exclude=./node_modules --exclude=./dist \
    --exclude=./test-results --exclude=./.git .) | (cd "$w" && tar xf -)
  f="$w/$(cat "$1/file")"
  before=$(cat "$1/before")
  if ! grep -qxF -- "$before" "$f"; then
    echo "no line \"$before\" in $(cat "$1/file")" > "$TMP/$n.log"
    return 2
  fi
  awk -v before="$before" -v snip="$1/snippet.bats" '
    $0 == before && !done { while ((getline l < snip) > 0) print l; print ""; done = 1 }
    { print }' "$f" > "$f.new" && mv "$f.new" "$f"
  (cd "$w" && bats check --repository "$2") > "$TMP/$n.log" 2>&1
}

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
fi

for d in "$ROOT"/tests/static/accept/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  named "accept/$n" || continue
  if check "$d" "$repository"; then echo "ok   accept/$n"
  else echo "FAIL accept/$n: should type-check"; grep -E 'error|no line' "$TMP/$n.log" | head -5; fail=1; fi
done

for d in "$ROOT"/tests/static/reject/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  named "reject/$n" || continue
  if check "$d" "$repository"; then echo "FAIL reject/$n: should be rejected"; fail=1
  elif grep -qF -- "$(cat "$d/expect")" "$TMP/$n.log"; then echo "ok   reject/$n"
  else echo "FAIL reject/$n: rejected, but not with: $(cat "$d/expect")"; grep -E 'error|no line' "$TMP/$n.log" | head -5; fail=1; fi
done
exit $fail
