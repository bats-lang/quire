#!/bin/sh
# Static tests: code that must type-check, and code that must not.
# What they test is private to a module (a dataprop's constructor, a
# cell's states), so a fixture is not a package of its own: it is a
# snippet (snippet.bats) that is put into a copy of this checkout, in the
# file named in its `file`, before the line equal to its `before`.
# Each fixture under tests/static/accept/ must then pass `bats check`;
# each under tests/static/reject/ must fail it, with the message in its
# `expect` file (so it is rejected for the right reason).
#
# usage: tests/static/run.sh <repository-dir>   (bats must be on PATH)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
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

for d in "$ROOT"/tests/static/accept/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if check "$d" "$1"; then echo "ok   accept/$n"
  else echo "FAIL accept/$n: should type-check"; grep -E 'error|no line' "$TMP/$n.log" | head -5; fail=1; fi
done

for d in "$ROOT"/tests/static/reject/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if check "$d" "$1"; then echo "FAIL reject/$n: should be rejected"; fail=1
  elif grep -qF -- "$(cat "$d/expect")" "$TMP/$n.log"; then echo "ok   reject/$n"
  else echo "FAIL reject/$n: rejected, but not with: $(cat "$d/expect")"; grep -E 'error|no line' "$TMP/$n.log" | head -5; fail=1; fi
done
exit $fail
