#!/bin/sh
# Writes the OAuth clients this build signs in with (#184) beside the
# app, as sync-clients.json, which src/sync_clients.bats reads as the app
# starts. A client ID is public (it ships in the app), so both are
# committed in scripts/sync-clients.env (#200, #239), and a local build
# has the same ones as CI: GOOGLE_WEB_CLIENT_ID, the Google Cloud
# project's *Web application* client, which Google's Android sign-in
# takes too; DROPBOX_CLIENT_ID, the Dropbox app's key. A value not of its
# provider's form fails the build.
#
# usage: scripts/sync-clients.sh <pwa-dir>
set -eu
env=$(dirname "$0")/sync-clients.env
value() { sed -n "s/^$1=//p" "$env"; }
google=$(value GOOGLE_WEB_CLIENT_ID)
if ! printf '%s' "$google" | grep -Eqx '[0-9]+-[0-9a-z]+\.apps\.googleusercontent\.com'; then
  echo "error: GOOGLE_WEB_CLIENT_ID in scripts/sync-clients.env is not a Google client ID (<number>-<letters>.apps.googleusercontent.com)" >&2
  exit 1
fi
dropbox=$(value DROPBOX_CLIENT_ID)
if ! printf '%s' "$dropbox" | grep -Eqx '[a-z0-9]{8,64}'; then
  echo "error: DROPBOX_CLIENT_ID in scripts/sync-clients.env is not a Dropbox app key (8 to 64 lowercase letters and digits)" >&2
  exit 1
fi
printf '{"googleWebClient": "%s", "dropboxClient": "%s"}\n' "$google" "$dropbox" > "$1/sync-clients.json"
echo "sync-clients.json: Google client $google, Dropbox app key $dropbox"
