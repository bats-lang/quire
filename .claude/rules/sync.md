---
paths:
  - src/sync*.bats
  - src/drive.bats
  - src/dropbox.bats
  - src/nextcloud.bats
  - src/web_request.bats
  - src/clock.bats
  - scripts/sync-clients.*
  - scripts/sync-providers.py
  - e2e/sync*
---

# Sync

## The sync file and its stores

`src/sync.bats` keeps places, shelves, collections, annotations and reading
time the same on the reader's devices through one file, `quire-sync.json`, in
the backup's JSON format plus each record's stamps, a `deleted` list per book
and a `devices` list. Where it is kept is a `store` (`WebDav(url, user,
password)`, `Fastmail`, `Android` or `Dropbox`; `store_kind` is the flat copy).
Its credentials are stored on this device only, by the store's kind ("sync"
names the kind; "sync-webdav", "sync-fastmail", "sync-android" (the account's
address) and "sync-dropbox" (the refresh token) hold the rest), never in the
backup.

* The merge calls only `store_read` (the file, none yet, or a failure) and
  `store_write` (written, a conflict, or a failure). WebDAV's version is the
  ETag (PUT with If-Match; a 412 is the conflict).
* A sync reads, merges and writes (again after a conflict, up to 3 tries), and
  only once the file is written does this device take the merge, so a failed
  sync changes nothing here. It runs when the app opens, when a book is opened,
  when the page is hidden, and from Sync now (`LSync`, `sync-screen`; Turn off
  goes through Undo).
* The Settings row says sync's state in short (`sync_summary_show`: "Off",
  "WebDAV · synced 2 min ago", or how the last sync failed). The screen (#331)
  is a status card, then "Sync with": a row per service (`sync_service`) with a
  word of state for the chosen one. A row opens its service's sign-in step
  (`sync_step_open`, layer `LSyncStep`, first in the screen so the stylesheet
  hides what follows while it shows); Escape and Cancel close it
  (`sync_step_cancel`, which stops a Nextcloud poll). **The screen lists only
  what can be used where it runs** (each row by its own `data-hide`): no row
  exists only to say why it is unavailable.
* With no store chosen, the app keeps the file for Android's Auto Backup
  (`BackupKind`, bridge's `backup_file` in `backup/` of the app's files, the
  only thing pwa's backup rules keep): each sync point merges and writes it,
  and the file a reinstall restores is merged at the first launch.

**Stamps and what wins** (`src/clock.bats`): a hybrid logical clock, minutes
since 2025 times 64 plus a count, after every stamp made or seen here, written
in the file as milliseconds. Shelves, collections (by name) and being finished
take the latest change, and so does the place (#302): each move in a book is
dated (`place_modified`: only a move to another chapter or page, none while a
book opens at its place, `reader_open_at`), and the file keeps the latest place
with its stamp and device (`placeModified`, `placeDevice`); at the same stamp
the further place wins; a place never dated never wins.

* The open book's place is not taken but offered, and only when another device
  read it later than this device's last move there: a row in the reader's bottom
  bar (`sync-offer`). Dismissed, it is declined (`place_declined`, in the
  library record only) and only a later place of another device's is offered. A
  backup's place is restored by the same rule.
* The reading log and each book's time are each device's own (its entry in
  `devices`), summed for display (`stats_elsewhere_*`).
* An annotation's id is the SHA-256 of what never changes in it, so it is never
  stored and two devices that restored one backup give it the same id; the
  latest change wins, and a deletion (`deleted`, kept 180 days,
  `TOMBSTONE_DAYS`) wins over a change made before it. A book only another
  device has is kept as an orphan ("o").

## Services

**Nextcloud** (`src/nextcloud.bats`, #184) is signed in to with Login Flow v2
and ends in the WebDAV store: `sync_nextcloud_sign_in` takes an https address,
starts the flow (`nextcloud_start`), offers the server's sign-in page as a link
the reader taps (`nextcloud-page`: a tap is never blocked, a script's
`window.open` after an answer is) and polls every 3 s for 20 minutes
(`nextcloud_poll`); a new sign-in or Turn off ends a poll
(`_sign_in_generation`). Granted, the user's id (`nextcloud_user_id`: a login
name can be an email, the folder is named by the id) makes the folder
`<server>/remote.php/dav/files/<id>`, kept with the login name and app password
as `WebDav`.

**Fastmail** (#184, #271), in the app only: files over WebDAV at
`https://myfiles.fastmail.com/quire/quire-sync.json` (the folder made by MKCOL
at the first write), with an app password. Fastmail's WebDAV sends no CORS
headers, so a browser lists no Fastmail; `sync-providers.yml` checks weekly
whether that changed (`fastmail-cors`). A refusal is `FastmailRefused`.
`e2e/sync-fastmail.spec.js`.

**Use Android** (#184), in the app only (`google_authorize_available`): the
store `Android(account)`, the file in the app data folder of the device's
Google account's Drive (`src/drive.bats`: a listing for its id and version,
then its bytes; a write checks the version is still the one read, else it is a
conflict). The `drive.appdata` token comes from bridge's `google_authorize`
(#321: bats-lang/capacitor-plugins' google-authorize over Play services'
`AuthorizationClient`; Capawesome's Google Sign-In shows Credential Manager's
sheet each time and is not used).

* Use Android and Sync now ask with `google_authorize_scopes` (consent screen
  only when access is not granted); the syncs the app makes by itself
  (`_google_access`) use `google_authorization_for_scopes`, which never shows
  anything. The token is kept on the device ("sync-google-token") and in
  memory (`_token`).
* When Drive refuses it (401) it is forgotten, taken out of Play services'
  cache (`google_clear_token`) and one asked for once with nothing shown
  (`_google_renewed`). Only `NotAuthorized` (the reader took access back)
  pauses sync (`SignInAgain`: no banner); each sync point still asks with
  nothing shown, so a grant given back ends the pause, and Sync now asks for
  consent. A failure is said by its code (`NETWORK_ERROR` or `TIMEOUT` can't
  reach the server, anything else Google refused).
* The account ("sync-android") is the one the authorization names, else
  Drive's (`drive_account_address`), else none. Turn off holds the token for the
  Undo; made final it takes the grant back (`_google_revoke`:
  `google_revoke_access`, or with no account Google's revocation endpoint,
  `drive_grant_revoke`).
* **Google Drive** is the same store in a browser: the token comes from Google
  Identity Services (about an hour, no refresh token), whose window a page may
  open only at a tap, so it is asked for only when the reader acts, a refused
  one pauses sync, and while paused with no token the app tries nothing by
  itself (`_paused`). Turn off revokes the token bridge was given this session.
* **The client IDs are public and not compiled in**: committed in
  `scripts/sync-clients.env` (#200, #239: the Web client `GOOGLE_WEB_CLIENT_ID`,
  the Android client's ID and Play's app signing SHA-1 beside it, Dropbox's app
  key), written by `scripts/sync-clients.sh` into `sync-clients.json` beside
  the app (CI and local builds alike) and read by `src/sync_clients.bats`; a
  build with none lists neither Use Android nor Google Drive.
  `sync-identity.yml` checks the committed values (the IDs' form, and that
  Play's SHA-1 is not the upload key's).
* The e2e suite stubs Google's script (`googleStubbed`, `e2e/fixtures.js`), so
  it never reaches Google; a spec that plays a provider, or a build with no
  client, serves its own `sync-clients.json` (`clientsServed`).
  `e2e/sync-android.spec.js` plays GoogleAuthorize, Filesystem, Drive's API and
  the revocation endpoint (`capacitorPlayed`, `e2e/sync-stores.js`).

**Dropbox** (#184): the store `Dropbox(refresh)`, the same file in the app's own
folder (scopes `files.content.read` and `files.content.write`).
`src/dropbox.bats` reads with `files/download` (rev from the
`Dropbox-API-Result` header; a 409 `not_found` is no file yet) and writes with
`files/upload` (mode `add`, or `update` with the rev read; a 409 `conflict` is
the conflict); `src/web_request.bats` holds the requests it shares with
`src/drive.bats`.

* The sign-in is OAuth's code flow with PKCE (S256, no secret; the app key is
  `DROPBOX_CLIENT_ID`, written into `sync-clients.json` as `dropboxClient`).
  Dynamic client registration is refused by Dropbox, so the app is registered by
  hand (quire#239). `sync_dropbox` keeps the verifier and state
  ("sync-dropbox-sign-in") and leaves the page for Dropbox's, which returns to
  the page's address with `?oauth=dropbox` (redirects registered, listed in
  `sync-identity.yml`). `sync_start` takes the code and state from the address,
  puts the address back (`replace_state`), opens Settings (`sync_returning`) and
  exchanges the code once the state matches. The refresh token is kept, the
  access token held in memory (`_token`) and got again on a 401. Turn off, made
  final, revokes the grant.
* In the app (RFC 8252) Dropbox's page opens in the system browser's tab
  (`browser_tab_open`) and the redirect is `quire://oauth/dropbox`.
  `src/bin/gen-pwa.bats` writes the Android project's `intent-filters.xml`
  (pwa's `build_intent_filters`, then the `quire` scheme's filter, `APP_SCHEME`).
  `listen_app_link` hands the address to `sync_app_link`; one that starts the
  app again waits for `sync_start` to load the stores (`start_state`), one while
  it runs is taken at once (`return_moment`). Dropbox is listed in the app only
  with both plugins (`_round_trip_available`).
* `e2e/sync-dropbox.spec.js` plays Dropbox (`e2e/dropbox-server.js`),
  `e2e/sync-dropbox-android.spec.js` the app's Browser and App plugins.

## Every outcome is said, and the unexpected as such (#334)

A Google error that ended the consent screen once reached quire as the reader
backing out. Now:

* The plugin and bridge report every error and unexpected condition as an
  outcome of its own, never folded into another; what they do not recognise is
  an explicit `...Unexpected` constructor carrying the case and the answer as
  bridge's JS wrote it.
* Quire matches every answer with `case+` and handles every constructor
  visibly: `AuthorizeRefused` by each `google_status` (`_refusal_result`), a
  cancel the reader made is noted on the Sync screen, every other end of a
  sign-in or sync the reader started is said in the error banner
  (`_reader_told`). An `...Unexpected` outcome goes through `notice_unexpected`
  (Copy details, a Report link; an access token's value is written as its
  length); a refusal with a code through `notice_failure`.
  `e2e/sync-android-outcomes.spec.js` passes through every constructor of
  google_authorize.
* **A call that never answers is an outcome too** (#340). A call that shows
  nothing (`authorizationForScopes`, `clearAuthorizationToken`, `revokeAccess`)
  is ended after 30 s (`GOOGLE_ANSWER_MS`: Play services documents no timeout;
  chosen from what comparable software does, OkHttp's 10 s per phase and the
  ~30 s Flutter developers bound a hanging `signIn()` with) as `GoogleNoAnswer`.
  The consent screen (`authorizeScopes`) is the reader's to take as long as they
  like, so no timer ends it: while awaited (`GoogleAsking`) the status card shows
  Stop waiting (`sync_stop`), which ends the ask as the reader's cancel.
* Each such call is the promise of a resolver kept in a cell with the call's
  number (`answer_wait`, `consent_wait`): the plugin's answer and the timer or
  Stop waiting each settle that number, the first resolves it, and a late
  answer is dropped, keeps no token and asks Google nothing more
  (`_authorization_late`). `e2e/sync-android-hang.spec.js` leaves each call
  pending (`hold`) and settles it late.
