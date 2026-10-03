#!/bin/sh
# Writes the OAuth clients this build signs in with (#184) beside the
# app, as sync-clients.json, which src/sync_clients.bats reads as the app
# starts. A client ID is public (it ships in the app), so it comes from a
# repository variable: GOOGLE_WEB_CLIENT_ID, the Google Cloud project's
# *Web application* client, which Google's Android sign-in takes too;
# DROPBOX_CLIENT_ID, the Dropbox app's key (#239). An empty one leaves
# its store "not set up"; one not of its provider's form fails the
# build.
#
# usage: GOOGLE_WEB_CLIENT_ID=... DROPBOX_CLIENT_ID=... scripts/sync-clients.sh <pwa-dir>
set -eu
google=${GOOGLE_WEB_CLIENT_ID:-}
if [ -n "$google" ] && ! printf '%s' "$google" | grep -Eqx '[0-9]+-[0-9a-z]+\.apps\.googleusercontent\.com'; then
  echo "error: GOOGLE_WEB_CLIENT_ID is not a Google client ID (<number>-<letters>.apps.googleusercontent.com)" >&2
  exit 1
fi
dropbox=${DROPBOX_CLIENT_ID:-}
if [ -n "$dropbox" ] && ! printf '%s' "$dropbox" | grep -Eqx '[a-z0-9]{8,64}'; then
  echo "error: DROPBOX_CLIENT_ID is not a Dropbox app key (8 to 64 lowercase letters and digits)" >&2
  exit 1
fi
printf '{"googleWebClient": "%s", "dropboxClient": "%s"}\n' "$google" "$dropbox" > "$1/sync-clients.json"
if [ -n "$google" ]; then echo "sync-clients.json: Google client set"; else echo "sync-clients.json: no Google client (Use Android, Google Drive not set up)"; fi
if [ -n "$dropbox" ]; then echo "sync-clients.json: Dropbox app key set"; else echo "sync-clients.json: no Dropbox app key (Dropbox not set up)"; fi
