#!/bin/sh
# Writes the OAuth clients this build signs in with (#184) beside the
# app, as sync-clients.json, which src/sync_clients.bats reads as the app
# starts. A client ID is public (it ships in the app), so it comes from a
# repository variable, GOOGLE_WEB_CLIENT_ID: the Google Cloud project's
# *Web application* client, which Google's Android sign-in takes too.
# An empty one leaves Use Android "not set up"; one that is not a
# Google client ID fails the build.
#
# usage: GOOGLE_WEB_CLIENT_ID=... scripts/sync-clients.sh <pwa-dir>
set -eu
google=${GOOGLE_WEB_CLIENT_ID:-}
if [ -n "$google" ] && ! printf '%s' "$google" | grep -Eqx '[0-9]+-[0-9a-z]+\.apps\.googleusercontent\.com'; then
  echo "error: GOOGLE_WEB_CLIENT_ID is not a Google client ID (<number>-<letters>.apps.googleusercontent.com)" >&2
  exit 1
fi
printf '{"googleWebClient": "%s"}\n' "$google" > "$1/sync-clients.json"
if [ -n "$google" ]; then echo "sync-clients.json: Google client set"; else echo "sync-clients.json: no Google client (Use Android not set up)"; fi
