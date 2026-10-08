#!/bin/sh
# The record codec, run natively: the CRC-32 check value, the numbers at
# the edge of 32 bits, a book's record written, read and written again,
# every byte of it damaged, every prefix of it, and a million bytes of
# fuzz. The codec modules are the app's own (src/*.bats), copied with
# their target changed from wasm to native (they are proven, so the proofs
# are checked again here); what the proofs cannot say is what is tested:
# the copy between arrays and lists (bytesarr.bats), arith's C operators.
#
# usage: tests/codec/run.sh <repository-dir>   (bats must be on PATH)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/src/bin"
cp "$ROOT/tests/codec/bats.toml" "$TMP/bats.toml"
cp "$ROOT/tests/codec/src/bin/codec.bats" "$TMP/src/bin/codec.bats"
cp "$ROOT/tests/codec/bats.lock" "$TMP/bats.lock"
for m in bytes crc chunk seq fields schema record bytesarr bookrec indexrec bookimage indeximage; do
  python3 - "$ROOT/src/$m.bats" "$TMP/src/$m.bats" <<'PY'
import sys
s = open(sys.argv[1]).read()
assert "#target wasm begin\n" in s, sys.argv[1]
s = s.replace("#target wasm begin\n", "#target native\n")
i = s.rstrip().rfind("\nend")
open(sys.argv[2], "w").write(s[:i] + "\n")
PY
done
cd "$TMP"
bats build --repository "$1" > build.log 2>&1 || { cat build.log; exit 1; }
BIN=$(find dist -type f -perm -u+x | head -1)
[ -n "$BIN" ] || { ls -R dist; exit 1; }
LIMIT=""
if command -v timeout >/dev/null 2>&1; then LIMIT="timeout 600"; fi
$LIMIT "$BIN" | tee out.log
tail -1 out.log | grep -qx "all ok"
