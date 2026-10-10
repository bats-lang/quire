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
# the app itself), `checkers` (ids.py and case_plus.py, with their
# fixtures), and fixtures, `accept/<name>` or `reject/<name>`. With none,
# it runs the checkers and every fixture.
#
# A fixture knows what proof fails when it is built. A reject fixture's
# `expect` names the function of its snippet, the line of the snippet
# patsopt reports, and patsopt's error word for word:
#
#   function <name>
#   line <n>
#   <the error, after "error(N): ", and the lines patsopt adds to it>
#
# and expect.py passes it only when that is what the check fails with
# and nothing else: in the module the snippet is in, at that line, in
# that function. A substring another error could also hold is not
# enough.
#
# The fixtures start from the app checked whole: the app is checked first
# (as `check`, or for the fixtures alone) in a copy of the checkout, and
# each fixture is put into that copy with its build as the check left
# it (each of check's passes keeps a cache of its own), so only the
# module its snippet is in is checked again, and a reject fixture stops
# at its error. A snippet adds private code, which only moves the #pub
# declarations after it to other lines of its module's .sats, and bats
# checks the modules that staload a .sats again only when more than that
# changed (bats-lang/bats#243). patsopt names C symbols by the absolute
# path of their files, so every fixture is checked at the same path, one
# after another. The app must check for its fixtures to mean anything,
# so a fixture run fails when the app does.
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
  [ $all = yes ] && [ "$1" != check ] && return 0
  for member in $selected; do [ "$member" = "$1" ] && return 0; done
  return 1
}
selected="$*"
for member in $selected; do
  case $member in
    check|checkers) ;;
    accept/*|reject/*) [ -d "$ROOT/tests/static/$member" ] || { echo "no fixture $member"; exit 2; } ;;
    *) echo "not a member: $member"; exit 2 ;;
  esac
done

# The fixtures to run, as accept/<name> and reject/<name>
fixtures=""
for verdict in accept reject; do
  for d in "$ROOT"/tests/static/$verdict/*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    if named "$verdict/$n"; then fixtures="$fixtures $verdict/$n"; fi
  done
done

fail=0

# The app itself, checked whole in a copy of the checkout (with its
# fetched modules, not its outputs): as `check`, and as what the fixtures
# start from, its build kept aside to be put back after each
app="$TMP/app"
if named check || [ -n "$fixtures" ]; then
  mkdir -p "$app"
  (cd "$ROOT" && tar cf - --exclude=./node_modules --exclude=./dist \
    --exclude=./build --exclude=./test-results --exclude=./.git .) | (cd "$app" && tar xf -)
  if (cd "$app" && bats check --repository "$repository") > "$TMP/app.log" 2>&1; then
    if named check; then echo "ok   check"; fi
  elif named check; then echo "FAIL check:"; cat "$TMP/app.log"; fail=1
  else echo "FAIL check (the app, which the fixtures start from):"; cat "$TMP/app.log"; fail=1; fi
  [ -z "$fixtures" ] || cp -a "$app/build" "$TMP/build-checked"
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

# The solver's 32 bits (literals.py) and the library's keys (keys.py)
if python3 "$ROOT/tests/static/literals.py" "$ROOT/src" > "$TMP/literals.log" 2>&1; then echo "ok   literals: $(tail -1 "$TMP/literals.log")"
else echo "FAIL literals:"; cat "$TMP/literals.log"; fail=1; fi
if python3 "$ROOT/tests/static/keys.py" "$ROOT/src" > "$TMP/keys.log" 2>&1; then echo "ok   keys: $(tail -1 "$TMP/keys.log")"
else echo "FAIL keys:"; cat "$TMP/keys.log"; fail=1; fi

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

# A dictionary's files are deleted only by Empty Trash (trash.py,
# quire#396): the app's own, and the checker's fixtures
if python3 "$ROOT/tests/static/trash.py" "$ROOT/src" > "$TMP/trash.log" 2>&1; then echo "ok   trash: $(tail -1 "$TMP/trash.log")"
else echo "FAIL trash:"; cat "$TMP/trash.log"; fail=1; fi
for d in "$ROOT"/tests/static/trash/reject/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if python3 "$ROOT/tests/static/trash.py" "$d" > "$TMP/trash-$n.log" 2>&1; then echo "FAIL trash/reject/$n: should be rejected"; fail=1
  elif grep -qF -- "$(cat "$d/expect")" "$TMP/trash-$n.log"; then echo "ok   trash/reject/$n"
  else echo "FAIL trash/reject/$n: rejected, but not with: $(cat "$d/expect")"; cat "$TMP/trash-$n.log"; fail=1; fi
done
fi

# The fixtures, one after another, each put into the checked copy
for member in $fixtures; do
  fixture="$ROOT/tests/static/$member"
  n=$(basename "$member")
  file=$(cat "$fixture/file")
  f="$app/$file"
  before=$(cat "$fixture/before")
  log="$TMP/$n.log"
  started=$(date +%s)
  if ! grep -qxF -- "$before" "$f"; then
    echo "FAIL $member: no line \"$before\" in $file"; fail=1; continue
  fi
  # the line of the module the snippet's first line is at
  at=$(grep -nxF -- "$before" "$f" | head -1 | cut -d: -f1)
  awk -v before="$before" -v snip="$fixture/snippet.bats" '
    $0 == before && !done { while ((getline l < snip) > 0) print l; print ""; done = 1 }
    { print }' "$f" > "$f.new" && mv "$f.new" "$f"
  status=0
  (cd "$app" && bats check --repository "$repository") > "$log" 2>&1 || status=$?
  took="($(( $(date +%s) - started )) s)"
  case $member in
    accept/*)
      if [ "$status" = 0 ]; then echo "ok   $member $took"
      else echo "FAIL $member: should type-check"; grep -E 'error' "$log" | head -5; fail=1; fi ;;
    reject/*)
      if [ "$status" = 0 ]; then echo "FAIL $member: should be rejected"; fail=1
      elif python3 "$ROOT/tests/static/expect.py" "$fixture" "$log" "$at" > "$TMP/$n.expect" 2>&1; then echo "ok   $member $took"
      else echo "FAIL $member: rejected, but not as its expect says: $(cat "$TMP/$n.expect")"; grep -E 'error' "$log" | head -5; fail=1; fi ;;
  esac
  # the module and the build back as the app's check left them (cp -p:
  # the same bytes and mtime, so the module is fresh again)
  cp -p "$ROOT/$file" "$f"
  rm -rf "$app/build"
  cp -a "$TMP/build-checked" "$app/build"
done
exit $fail
