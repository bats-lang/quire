#!/bin/bash
# scripts/with-env: arguments arrive intact, the exit status is the
# command's, a usage error is 2, and a variable the file does not export
# reaches the command. Run from anywhere.
set -u
here=$(cd "$(dirname "$0")" && pwd)
with_env=$here/../../scripts/with-env
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
printf 'plain=one\nexport exported=two\n' > "$tmp/env"

got=$("$with_env" "$tmp/env" printf '%s|' 'a b' '*' '' 'c  d')
[ "$got" = 'a b|*||c  d|' ] || fail "arguments changed: $got"
got=$("$with_env" "$tmp/env" sh -c 'echo "$plain $exported"')
[ "$got" = 'one two' ] || fail "variables did not arrive: $got"
"$with_env" "$tmp/env" sh -c 'exit 7'; [ $? -eq 7 ] || fail "status 7 changed"
"$with_env" "$tmp/env" no-such-command-here 2>/dev/null; [ $? -eq 127 ] || fail "missing command is not 127"
"$with_env" "$tmp/missing" true 2>/dev/null; [ $? -eq 2 ] || fail "no env file is not 2"
"$with_env" "$tmp/env" 2>/dev/null; [ $? -eq 2 ] || fail "no command is not 2"
"$with_env" 2>/dev/null; [ $? -eq 2 ] || fail "no arguments is not 2"
echo "with-env: ok"
