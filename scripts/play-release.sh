#!/bin/sh
# Releases an AAB to Google Play's internal testing track (#308), through
# the Play Developer API's edits: insert, upload the bundle, set the
# internal track to a completed release of its version code with these
# release notes, then commit (or, for a dry run, validate). The release
# is named by Play, from the bundle's versionName (the commit's version,
# scripts/version.sh). Committing with ERROR_IF_IN_REVIEW: a change in
# review is never cancelled by this one, which then fails instead. An
# edit that does not commit is deleted, so nothing is left half made.
#
# usage: scripts/play-release.sh <aab> <notes-file> [--dry-run]
# env: PLAY_ACCESS_TOKEN, an OAuth token with the androidpublisher scope;
#      PLAY_PACKAGE, the application id; PLAY_API, the API's root
#      (https://androidpublisher.googleapis.com unless a test stubs it)
set -eu
aab=$1 notes=$2
dry_run=${3:-}
api=${PLAY_API:-https://androidpublisher.googleapis.com}
app="$api/androidpublisher/v3/applications/$PLAY_PACKAGE"
upload="$api/upload/androidpublisher/v3/applications/$PLAY_PACKAGE"

# Play's "What's new" holds 500 characters a language (the notes are
# taken without the white space at either end)
length=$(python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read().strip()))' "$notes")
if [ "$length" -eq 0 ]; then
  echo "error: the release notes are empty" >&2
  exit 1
fi
if [ "$length" -gt 500 ]; then
  echo "error: the release notes are $length characters; Play takes at most 500" >&2
  exit 1
fi
[ -s "$aab" ] || { echo "error: no AAB at $aab" >&2; exit 1; }

body=$(mktemp)
edit=
cleanup() {
  status=$?
  if [ -n "$edit" ]; then
    curl -sS -o /dev/null -X DELETE -H "Authorization: Bearer $PLAY_ACCESS_TOKEN" "$app/edits/$edit" || true
  fi
  rm -f "$body" "$body.track"
  exit $status
}
trap cleanup EXIT

# call <what> <curl arguments>: the answer in $body, a failure said with it
call() {
  what=$1
  shift
  code=$(curl -sS -o "$body" -w '%{http_code}' -H "Authorization: Bearer $PLAY_ACCESS_TOKEN" "$@")
  case $code in
    2??) ;;
    *) echo "error: $what: HTTP $code" >&2; cat "$body" >&2; echo >&2; exit 1 ;;
  esac
}

call "create the edit" -X POST -H 'Content-Type: application/json' -d '{}' "$app/edits"
edit=$(jq -r .id "$body")
echo "edit $edit"

call "upload the bundle" -X POST -H 'Content-Type: application/octet-stream' \
  --data-binary "@$aab" "$upload/edits/$edit/bundles?uploadType=media"
version_code=$(jq -r .versionCode "$body")
echo "bundle uploaded: version code $version_code"

jq -n --arg code "$version_code" --rawfile notes "$notes" '{
  track: "internal",
  releases: [{
    versionCodes: [$code],
    status: "completed",
    releaseNotes: [{language: "en-US", text: ($notes | sub("^\\s+"; "") | sub("\\s+$"; ""))}]
  }]
}' > "$body.track"
call "set the internal track" -X PUT -H 'Content-Type: application/json' \
  --data-binary "@$body.track" "$app/edits/$edit/tracks/internal"

if [ "$dry_run" = --dry-run ]; then
  call "validate the edit" -X POST "$app/edits/$edit:validate"
  echo "dry run: the edit is valid; it is deleted, not committed"
else
  call "commit the edit" -X POST "$app/edits/$edit:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW"
  edit=
  echo "released to internal testing: version code $version_code"
fi
