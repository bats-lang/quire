#!/bin/sh
# The CSS font-size reader (src/css_size.bats), run natively on bytes: the
# values and units, a declaration block, <font size>, selectors, whole style
# sheets, and the sizes and proportions that come of them (quire#431). The
# module is the app's own, copied with its target changed from wasm to
# native (it is proven, so the proofs are checked again here); what the
# proofs cannot say is what is tested: that what it reads is CSS's grammar.
#
# usage: tests/css-size/run.sh <repository-dir>   (bats must be on PATH)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/src/bin"
cp "$ROOT/tests/css-size/bats.toml" "$TMP/bats.toml"
cp "$ROOT/tests/css-size/bats.lock" "$TMP/bats.lock"
cp "$ROOT/tests/css-size/src/bin/css_size_test.bats" "$TMP/src/bin/css_size_test.bats"
python3 - "$ROOT/src/css_size.bats" "$TMP/src/css_size.bats" <<'PY'
import sys
s = open(sys.argv[1]).read()
assert "#target wasm begin\n" in s, sys.argv[1]
s = s.replace("#target wasm begin\n", "#target native\n")
i = s.rstrip().rfind("\nend")
open(sys.argv[2], "w").write(s[:i] + "\n")
PY
cd "$TMP"
bats build --repository "$1" > build.log 2>&1 || { cat build.log; exit 1; }
BIN=$(find dist -type f -perm -u+x | head -1)
[ -n "$BIN" ] || { ls -R dist; exit 1; }
LIMIT=""
if command -v timeout >/dev/null 2>&1; then LIMIT="timeout 600"; fi
$LIMIT "$BIN" | tee out.log
tail -1 out.log | grep -qx "all ok"
