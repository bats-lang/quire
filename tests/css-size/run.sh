#!/bin/sh
# The CSS font-size reader and the cascade built on it (src/css_size.bats,
# src/css_cascade.bats), run natively on bytes: the values and units, a
# declaration block, <font size>, selectors, whole style sheets, the sizes
# and proportions that come of them, and a chapter's characters counted by
# the size they are set in (quire#431). The modules are the app's own,
# copied with their target changed from wasm to native (they are proven,
# so the proofs are checked again here); what the proofs cannot say is what
# is tested: that what they read is CSS's grammar and what they match is
# its cascade.
#
# usage: tests/css-size/run.sh <repository-dir>   (bats must be on PATH)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/src/bin"
cp "$ROOT/tests/css-size/bats.toml" "$TMP/bats.toml"
cp "$ROOT/tests/css-size/bats.lock" "$TMP/bats.lock"
cp "$ROOT"/tests/css-size/src/bin/*.bats "$TMP/src/bin/"
for MODULE in css_size css_cascade; do
  python3 - "$ROOT/src/$MODULE.bats" "$TMP/src/$MODULE.bats" <<'PY'
import sys
s = open(sys.argv[1]).read()
assert "#target wasm begin\n" in s, sys.argv[1]
s = s.replace("#target wasm begin\n", "#target native\n")
i = s.rstrip().rfind("\nend")
open(sys.argv[2], "w").write(s[:i] + "\n")
PY
done
# the real book of quire#868: its chapter and the sheets it links, put in the test as strings
python3 - "$ROOT/e2e/calculus101-mathml-test.epub" "$TMP/src/bin/css_book_test.bats" <<'PY'
import re, sys, zipfile
book = zipfile.ZipFile(sys.argv[1])
chapter = book.read("index.xhtml").decode("utf-8")
links = re.findall(r'<link rel="stylesheet" type="text/css" href="([^"]+)"', chapter)
assert links[-1] == "_static/sphinx-typst-math.css", links
def literal(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", "\\n")
sheets = "".join(book.read(name).decode("utf-8") + "\n" for name in links)
typst = book.read("_static/sphinx-typst-math.css").decode("utf-8")
source = open(sys.argv[2]).read()
for marker, value in (("@@CHAPTER@@", chapter), ("@@BOOK_SHEETS@@", sheets), ("@@TYPST_SHEET@@", typst)):
    assert marker in source
    source = source.replace(marker, literal(value))
open(sys.argv[2], "w").write(source)
PY
cd "$TMP"
bats build --repository "$1" > build.log 2>&1 || { cat build.log; exit 1; }
LIMIT=""
if command -v timeout >/dev/null 2>&1; then LIMIT="timeout 600"; fi
RAN=0
for BIN in $(find dist -type f -perm -u+x | sort); do
  $LIMIT "$BIN" | tee out.log
  tail -1 out.log | grep -qx "all ok"
  RAN=$((RAN + 1))
done
[ "$RAN" -ge 3 ] || { ls -R dist; exit 1; }
