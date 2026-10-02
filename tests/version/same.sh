#!/bin/sh
# The version (#219) depends only on the commit: written again, under
# other clocks' time zones, it is the same, it has the form
# YEAR.MONTH.DAY.SECONDS (SHA), and the Android project gen-pwa wrote
# carries it as its versionName (run after scripts/version.sh and
# gen-pwa, from the checkout's root)
set -eu
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for zone in UTC Pacific/Kiritimati America/Adak; do
  TZ=$zone scripts/version.sh "$tmp/version.bats" >/dev/null
  cmp "$tmp/version.bats" src/version.bats || { echo "the version written in $zone differs:"; diff "$tmp/version.bats" src/version.bats; exit 1; }
done
version=$(sed -n 's/^implement quire_version () = "\(.*\)"$/\1/p' src/version.bats)
code=$(sed -n 's/^implement quire_version_code () = "\(.*\)"$/\1/p' src/version.bats)
echo "$version" | grep -Eq '^[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}\.[0-9]+ \([0-9a-f]{7,}\)$' || { echo "not a version: '$version'"; exit 1; }
echo "$code" | grep -Eq '^[0-9]+$' || { echo "not a version code: '$code'"; exit 1; }
grep -qF "versionName '$version'" dist/android/android-release.gradle || { echo "dist/android/android-release.gradle has no versionName '$version'"; exit 1; }
grep -qF "versionCode $code" dist/android/android-release.gradle || { echo "dist/android/android-release.gradle has no versionCode $code"; exit 1; }
echo "version $version, version code $code: the same in every time zone, and the Android project's"
