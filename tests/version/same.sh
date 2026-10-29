#!/bin/sh
# The version (#219) depends only on the commit. bats writes the commit's
# facts (build/src/_bats_facts.dats, bats-lang/bats#250), which
# src/version.bats words: written again under other clocks' time zones,
# by a project of its own, they are the same; the version has the form
# YEAR.MONTH.DAY.SECONDS (SHA); and the Android project gen-pwa wrote
# carries it as its versionName, and the number of commits reachable from
# the commit plus the offset of src/version.bats as its versionCode (#989:
# above 955894, the last code the minutes scheme gave Play, and above the
# parent's).
#
# Run after `bats build` and gen-pwa, from the checkout, with the
# BATS_COMMIT the build had (none: HEAD); bats must be on PATH.
set -eu
cd "$(dirname "$0")/../.."
facts=build/src/_bats_facts.dats
[ -f "$facts" ] || { echo "no $facts: run bats build first"; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# A project that only names the facts: bats writes them from git, here the
# checkout's repository
GIT_DIR=$(git rev-parse --absolute-git-dir)
export GIT_DIR
mkdir -p "$tmp/project/src/bin"
cat > "$tmp/project/bats.toml" <<'TOML'
[package]
name = "version-same"
kind = "bin"
TOML
cat > "$tmp/project/src/bin/facts.bats" <<'BATS'
#include "share/atspre_staload.hats"

staload F = "_bats_facts.sats"

implement main0 () = println! ($F.bats_commit_version())
BATS
for zone in UTC Pacific/Kiritimati America/Adak; do
  rm -rf "$tmp/project/build"
  (cd "$tmp/project" && TZ=$zone bats check) > "$tmp/check.log" 2>&1 || { echo "bats check under $zone failed:"; cat "$tmp/check.log"; exit 1; }
  cmp "$tmp/project/build/src/_bats_facts.dats" "$facts" || { echo "the facts written in $zone differ:"; diff "$tmp/project/build/src/_bats_facts.dats" "$facts"; exit 1; }
done
fact() { sed -n "s/^implement $1 () = \"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$facts"; }
date=$(fact bats_commit_version)
short=$(fact bats_commit_short)
seconds=$(fact bats_commit_time)
version="$date ($short)"
echo "$version" | grep -Eq '^[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}\.[0-9]+ \([0-9a-f]{7}\)$' || { echo "not a version: '$version'"; exit 1; }
echo "$seconds" | grep -Eq '^[0-9]+$' || { echo "not a commit time: '$seconds'"; exit 1; }
# the commit's, not the checkout's: BATS_COMMIT names a pull request's head
case $(git rev-parse "${BATS_COMMIT:-HEAD}") in "$short"*) ;; *) false ;; esac || { echo "the facts name $short, not ${BATS_COMMIT:-HEAD}"; exit 1; }
[ "$seconds" = "$(git log -1 --format=%ct "${BATS_COMMIT:-HEAD}")" ] || { echo "the facts' time $seconds is not ${BATS_COMMIT:-HEAD}'s"; exit 1; }
# the commit count the facts hold is git's own, and the code is that plus the offset
count=$(grep -Eo '^implement bats_commit_count \(\) = CommitCounted \([0-9]+\)$' "$facts" | grep -Eo '[0-9]+' || true)
[ -n "$count" ] || { echo "the facts hold no commit count (a shallow clone?): $(grep bats_commit_count "$facts")"; exit 1; }
[ "$count" = "$(git rev-list --count "${BATS_COMMIT:-HEAD}")" ] || { echo "the facts' count $count is not ${BATS_COMMIT:-HEAD}'s"; exit 1; }
offset=$(sed -n 's/^#pub stadef VERSION_CODE_OFFSET = \([0-9][0-9]*\)$/\1/p' src/version.bats)
echo "$offset" | grep -Eq '^[0-9]+$' || { echo "src/version.bats has no VERSION_CODE_OFFSET: '$offset'"; exit 1; }
code=$(( count + offset ))
[ "$code" -gt 955894 ] || { echo "version code $code is not above 955894, the last code the minutes scheme gave Play"; exit 1; }
if git rev-parse -q --verify "${BATS_COMMIT:-HEAD}^" > /dev/null; then
  parent=$(( $(git rev-list --count "${BATS_COMMIT:-HEAD}^") + offset ))
  [ "$code" -gt "$parent" ] || { echo "version code $code is not above its parent's $parent"; exit 1; }
fi
grep -qF "versionName '$version'" dist/android/android-release.gradle || { echo "dist/android/android-release.gradle has no versionName '$version'"; exit 1; }
grep -qF "versionCode $code" dist/android/android-release.gradle || { echo "dist/android/android-release.gradle has no versionCode $code"; exit 1; }
echo "version $version, version code $code: the same in every time zone, and the Android project's"
