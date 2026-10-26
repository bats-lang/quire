#!/bin/sh
# The EPUB CFI module (src/cfi.bats), run natively on chapters: the steps of
# the specification's examples, of epub.js's and KOReader's, the steps of every
# position of generated chapters against a generator that knows them, and
# the way back (keyword cfi, quire#901). The modules are the app's own, copied
# as they are (cfi, xhtml_parse and entity name no target, so the same
# source is the one compiled for wasm); what the types cannot say is what is
# tested. Avenue exhausted (quire#646): `bats test` builds a package's own
# sources; a `{ path = ... }` dependency (bats's lock.bats) names a whole
# package directory with a src/lib.bats, and quire is kind = "bin", so it
# cannot name the four modules of src/ this test needs; there is no bats
# command that builds a test package from chosen modules of another one, so the
# copy is made here, as tests/codec/run.sh does. bats.lock is made in the layout
# this script builds (modules copied, then `bats lock --repository <dir>` with
# the clone .github/repository-version names): in tests/cfi alone no module is
# there to #use str, so a lock made there drops it.
#
# usage: tests/cfi/run.sh <repository-dir>   (bats must be on PATH)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/src/bin" "$TMP/fixtures"
cp "$ROOT/tests/cfi/bats.toml" "$TMP/bats.toml"
cp "$ROOT/tests/cfi/bats.lock" "$TMP/bats.lock"
cp "$ROOT/tests/cfi/src/bin/cfi.bats" "$TMP/src/bin/cfi.bats"
cp "$ROOT/tests/cfi/fixtures/epubjs-chapter1.xhtml" "$TMP/fixtures/"
for m in cfi xhtml_parse entity epub_xml; do
  cp "$ROOT/src/$m.bats" "$TMP/src/$m.bats"
done
cd "$TMP"
bats build --repository "$1" > build.log 2>&1 || { cat build.log; exit 1; }
BIN=$(find dist/debug -type f -perm -u+x | head -1)
[ -n "$BIN" ] || { ls -R dist; exit 1; }
LIMIT=""
if command -v timeout >/dev/null 2>&1; then LIMIT="timeout 600"; fi
$LIMIT "$BIN" | tee out.log
tail -1 out.log | grep -qx "all ok"
