#!/bin/sh
# Writes src/version.bats, the version the app and gen-pwa are built
# with (#219): the date of the commit built from, never of the build, so
# the same commit always gives the same version. It is the committer
# date in UTC as bats packages are versioned, YEAR.MONTH.DAY.SECONDS
# (seconds since midnight), and the commit's short SHA:
# "2026.10.2.61373 (f95ce82)". Android's version code is the same time
# in minutes since 2025-01-01, so it grows from release to release.
#
# The commit is QUIRE_COMMIT when set (CI names a pull request's own
# head, not the merge it checks out), else HEAD.
#
# usage: scripts/version.sh [<out-file>]   (default src/version.bats)
set -eu
cd "$(dirname "$0")/.."
out=${1:-src/version.bats}
commit=${QUIRE_COMMIT:-HEAD}
seconds=$(git log -1 --format=%ct "$commit")
sha=$(git rev-parse --short=7 "$commit")
# the commit's date in UTC (GNU date, else BSD date)
day=$(TZ=UTC date -u -d "@$seconds" +%Y.%m.%d 2>/dev/null || TZ=UTC date -u -r "$seconds" +%Y.%m.%d)
year=${day%%.*}; rest=${day#*.}; month=${rest%%.*}; dom=${rest#*.}
version="$year.$(expr "$month" + 0).$(expr "$dom" + 0).$((seconds % 86400)) ($sha)"
# minutes since 2025-01-01T00:00:00Z
code=$(( (seconds - 1735689600) / 60 ))
cat > "$out" <<BATS
(* version -- the version Quire is built as, written by
   scripts/version.sh from the commit built from (#219); not in git *)

(* The version: the commit's UTC date, YEAR.MONTH.DAY.SECONDS, and its
   short SHA *)
#pub fn quire_version (): [version_len:pos | version_len < 64] string version_len
implement quire_version () = "$version"

(* Android's version code: the commit's time in minutes since 2025 *)
#pub fn quire_version_code (): [code_len:pos | code_len < 16] string code_len
implement quire_version_code () = "$code"
BATS
echo "$version, version code $code"
