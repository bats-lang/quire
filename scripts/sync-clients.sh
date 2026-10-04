#!/bin/sh
# Writes the OAuth clients this build signs in with (#184) beside the
# app, as sync-clients.json, which src/sync_clients.bats reads as the app
# starts. A client ID is public (it ships in the app). Google's is
# committed in scripts/sync-clients.env (#200), so a local build has the
# same one as CI: GOOGLE_WEB_CLIENT_ID, the Google Cloud project's *Web
# application* client, which Google's Android sign-in takes too.
# Dropbox's app key (#239) is not registered yet, so it still comes from
# the environment, DROPBOX_CLIENT_ID; an empty one leaves Dropbox "not
# set up". A value not of its provider's form fails the build.
#
# usage: [DROPBOX_CLIENT_ID=...] scripts/sync-clients.sh <pwa-dir>
set -eu
here=$(dirname "$0")
google=$(sed -n 's/^GOOGLE_WEB_CLIENT_ID=//p' "$here/sync-clients.env")
if ! printf '%s' "$google" | grep -Eqx '[0-9]+-[0-9a-z]+\.apps\.googleusercontent\.com'; then
  echo "error: GOOGLE_WEB_CLIENT_ID in scripts/sync-clients.env is not a Google client ID (<number>-<letters>.apps.googleusercontent.com)" >&2
  exit 1
fi
dropbox=${DROPBOX_CLIENT_ID:-}
if [ -n "$dropbox" ] && ! printf '%s' "$dropbox" | grep -Eqx '[a-z0-9]{8,64}'; then
  echo "error: DROPBOX_CLIENT_ID is not a Dropbox app key (8 to 64 lowercase letters and digits)" >&2
  exit 1
fi
printf '{"googleWebClient": "%s", "dropboxClient": "%s"}\n' "$google" "$dropbox" > "$1/sync-clients.json"
echo "sync-clients.json: Google client $google"
if [ -n "$dropbox" ]; then echo "sync-clients.json: Dropbox app key set"; else echo "sync-clients.json: no Dropbox app key (Dropbox not set up)"; fi
