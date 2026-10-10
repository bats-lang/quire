#!/bin/sh
# scripts/play-release.sh against a stub of Play's edits API (stub.py):
# a release makes an edit, uploads the AAB's bytes, sets the internal
# track to a completed release of the uploaded version code with the
# notes, and commits without cancelling a review; a dry run validates and
# deletes the edit; a refused step deletes the edit and commits nothing;
# notes that are empty or over Play's 500 characters fail before Play is
# asked anything. Run from anywhere.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
release=$here/../../scripts/play-release.sh
tmp=$(mktemp -d)
pid=
trap '[ -z "$pid" ] || kill "$pid" 2>/dev/null; rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

head -c 3000 /dev/urandom > "$tmp/app.aab"
printf '\n  • One\n• Two “quoted”\n\n' > "$tmp/notes"
export PLAY_ACCESS_TOKEN=token-1 PLAY_PACKAGE=dev.middlefield.quire

# stub <failing path suffix>...: a fresh stub and log; PLAY_API its address
stub() {
  if [ -n "$pid" ]; then kill "$pid"; wait "$pid" 2>/dev/null || true; fi
  rm -f "$tmp/port"
  : > "$tmp/log"
  python3 "$here/stub.py" "$tmp/port" "$tmp/log" "$@" &
  pid=$!
  i=0
  until [ -s "$tmp/port" ]; do
    i=$((i + 1))
    [ $i -lt 100 ] || fail "the stub did not start"
    sleep 0.1
  done
  PLAY_API=http://127.0.0.1:$(cat "$tmp/port")
  export PLAY_API
}
# requests: each request's method and path, one a line
requests() { jq -r '.method + " " + .path' "$tmp/log"; }
expect_requests() {
  printf '%s\n' "$@" > "$tmp/want"
  requests > "$tmp/got"
  diff "$tmp/want" "$tmp/got" || fail "$case: not the requests expected"
}
app=/androidpublisher/v3/applications/dev.middlefield.quire

case="a release"
stub
"$release" "$tmp/app.aab" "$tmp/notes" > "$tmp/out" || fail "$case: failed"
expect_requests \
  "POST $app/edits" \
  "POST /upload$app/edits/edit-1/bundles?uploadType=media" \
  "PUT $app/edits/edit-1/tracks/internal" \
  "POST $app/edits/edit-1:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW"
[ -z "$(jq -r 'select(.authorization != "Bearer token-1") | .path' "$tmp/log")" ] || fail "$case: a request without the token"
jq -r 'select(.path | contains("/bundles")) | .body' "$tmp/log" | base64 -d > "$tmp/sent.aab"
cmp "$tmp/app.aab" "$tmp/sent.aab" || fail "$case: the bundle sent is not the AAB"
[ "$(jq -r 'select(.path | contains("/bundles")) | .type' "$tmp/log")" = application/octet-stream ] || fail "$case: the bundle's type"
jq -r 'select(.method == "PUT") | .body' "$tmp/log" | base64 -d | jq -c . > "$tmp/track"
want='{"track":"internal","releases":[{"versionCodes":["4242"],"status":"completed","releaseNotes":[{"language":"en-US","text":"• One\n• Two “quoted”"}]}]}'
[ "$(cat "$tmp/track")" = "$want" ] || fail "$case: the track was $(cat "$tmp/track")"
grep -q "version code 4242" "$tmp/out" || fail "$case: did not say the version code"
echo "ok: $case"

case="a dry run"
stub
"$release" "$tmp/app.aab" "$tmp/notes" --dry-run > /dev/null || fail "$case: failed"
expect_requests \
  "POST $app/edits" \
  "POST /upload$app/edits/edit-1/bundles?uploadType=media" \
  "PUT $app/edits/edit-1/tracks/internal" \
  "POST $app/edits/edit-1:validate" \
  "DELETE $app/edits/edit-1"
echo "ok: $case"

for step in /bundles /tracks/internal :validate; do
  case="a refused $step"
  stub "$step"
  if "$release" "$tmp/app.aab" "$tmp/notes" --dry-run > /dev/null 2> "$tmp/err"; then
    fail "$case: succeeded"
  fi
  grep -q "HTTP 400" "$tmp/err" || fail "$case: did not say the answer"
  grep -q "refused by the stub" "$tmp/err" || fail "$case: did not say Play's message"
  [ "$(requests | tail -1)" = "DELETE $app/edits/edit-1" ] || fail "$case: the edit was not deleted"
  if requests | grep -q ':commit'; then fail "$case: committed"; fi
  echo "ok: $case"
done

case="a refused commit"
stub :commit
if "$release" "$tmp/app.aab" "$tmp/notes" > /dev/null 2>&1; then fail "$case: succeeded"; fi
[ "$(requests | tail -1)" = "DELETE $app/edits/edit-1" ] || fail "$case: the edit was not deleted"
echo "ok: $case"

case="notes over 500 characters"
stub
python3 -c 'print("é" * 501)' > "$tmp/long"
if "$release" "$tmp/app.aab" "$tmp/long" > /dev/null 2> "$tmp/err"; then fail "$case: succeeded"; fi
grep -q "501 characters" "$tmp/err" || fail "$case: did not say the length"
[ ! -s "$tmp/log" ] || fail "$case: asked Play"
python3 -c 'print("é" * 500)' > "$tmp/long"
"$release" "$tmp/app.aab" "$tmp/long" --dry-run > /dev/null || fail "500 characters: refused"
echo "ok: $case, and 500 taken"

case="empty notes"
stub
printf '  \n' > "$tmp/empty"
if "$release" "$tmp/app.aab" "$tmp/empty" > /dev/null 2>&1; then fail "$case: succeeded"; fi
[ ! -s "$tmp/log" ] || fail "$case: asked Play"
echo "ok: $case"
