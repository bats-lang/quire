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

### Sync

`src/sync.bats` keeps places, shelves, collections, annotations and
reading time the same on the reader's devices, through one file,
`quire-sync.json`, in the backup's JSON format plus each record's
stamps, a `deleted` list per book and a `devices` list. Where the file
is kept is a `store` (`WebDav(url, user, password)`, or `Fastmail`,
`Android` or `Dropbox`, below): its credentials are stored on this
device only, by the store's kind ("sync" names the kind, "sync-webdav"
holds the WebDAV ones, "sync-fastmail" Fastmail's, "sync-android" the
account's address, "sync-dropbox" the refresh token), never in the backup. The merge and its tries call only `store_read` (the file,
none yet, or a failure) and `store_write` (written, a conflict, or a
failure); WebDAV's read is a GET whose ETag is the version, its write
a PUT with If-Match (a 412 is the conflict). A sync reads, merges and
writes (again after a conflict, up to 3 tries), and only once the file
is written does this device take the merge, so a failed sync changes
nothing here. It runs when the app opens, when a book is opened, when
the page is hidden, and from the screen's Sync now (`LSync`,
`sync-screen`, opened from the Settings screen's Sync row; Turn off
goes through Undo). That row says sync's state in short
(`sync_summary_show`, refreshed with the screen's status line): "Off",
"WebDAV · synced 2 min ago" ("Fastmail · ...", "Android · ...", "Dropbox · ..."), or how the last sync
failed. The screen (#331, from Android's Backup and Add account
screens and Material's settings) is a status card at its top (where
sync is kept, how the last sync went or what it needs, and Turn off and
Sync now while it is on), then "Sync with": a row per service, its name
only (`sync_service`: Google Drive, Dropbox, Fastmail, Nextcloud,
WebDAV) and, for the one chosen, a word of state ("Connected",
"Paused", "Not syncing"), then a line on what sync keeps. A row opens
its service's own sign-in step (`sync_step_open`, the layer
`LSyncStep`, `sync-step`, first in the screen so the stylesheet hides
what follows it while it shows): what the service does, its fields,
its link, Cancel and its one button (Use Android or Sign in to Google
Drive, Sign in to Dropbox, Sync with Fastmail, Sign in with Nextcloud,
Sync with this folder); a field left empty is said in the step, and
once the sign-in begins the step closes and the card says how it goes.
Escape and Cancel close the step (`sync_step_cancel`, which stops a
Nextcloud poll). The screen lists only what can be used where it runs,
each row shown by its own `data-hide` (`ui_show` in
`sync_screen_open`): no row is there only to say why it is unavailable
(a provider a browser can't reach, a build with no client or key).

Nextcloud is signed in to with its Login Flow v2 (`src/nextcloud.bats`,
#184), which ends in the WebDAV store: the screen's Sign in with
Nextcloud (`sync_nextcloud_sign_in`) takes an https address, starts the
flow (`nextcloud_start`), offers the server's sign-in page as a link
the reader taps (`nextcloud-page`: a tap is never blocked, a script's
`window.open` after an answer is), and polls the flow's endpoint every
3 s for its 20 minutes (`nextcloud_poll`, a form body `token=…`); a new
sign-in or Turn off ends a poll (`_sign_in_generation`). Granted, the
user's id (`nextcloud_user_id`, OCS `cloud/user`: a login name can be an
email, the files folder is named by the id) makes the folder,
`<server>/remote.php/dav/files/<id>` (`nextcloud_folder`), kept with the
login name and the app password as `WebDav`, and a sync runs.

**Fastmail** (#184, #271), in the app only: the store `Fastmail(user,
password)`, its files over WebDAV at
`https://myfiles.fastmail.com/quire/quire-sync.json` (the folder made
by MKCOL at the first write), with the Fastmail address and an app
password the row's link and steps say how to make. Fastmail's WebDAV
sends no CORS headers, so a browser page can't reach it, and a browser
lists no Fastmail and sends it nothing; the app's requests are native.
A refusal is `FastmailRefused`. `sync-providers.yml` checks weekly
whether Fastmail now lets pages in (`fastmail-cors`), so browsers could
list it too. `e2e/sync-fastmail.spec.js` plays its files.

A change is dated by a stamp (`src/clock.bats`): a hybrid logical
clock, minutes since 2025 times 64 plus a count, after every stamp made
or seen here (the browser gives the time only to the minute), written
in the file as milliseconds. Shelves, collections (by name) and being
finished take the latest change, and so does the place (#302): each
move in a book is dated (`place_modified`, only a move to another
chapter or page, not a page counted anew, and none while a book opens
at its place, `reader_open_at`, until the reader acts), and the file
keeps the
latest place with its stamp and the device that read it
(`placeModified`, `placeDevice`); at the same stamp the further place
wins, and a place never dated (kept before places were) never does. The
open book's is not taken but offered, and only when another device read
it later than this device's last move there: in a row of the reader's
bottom bar (`sync-offer`, shown with the bars, so it covers no text),
"Go to where you were on another device (chapter 3)". Dismissed, that
place is declined (`place_declined`, in the library record only, not in
the backup or the file): it is neither offered nor taken again, and only
a later place of another device's is. A backup's place is restored by
the same rule. The reading log and each book's
time are each device's own (its entry in `devices`), summed for display
(`stats_elsewhere_*`, `minutes_elsewhere`). An annotation's id is the
SHA-256 of what never changes in it (bookmark or highlight, chapter,
start, end, minute made), so it is never stored and two devices that
restored one backup give it the same id; the latest change wins, and a
deletion (`deleted`, kept 180 days, `QA3`) wins over a change made
before it. A book only another device has is kept as an orphan ("o").

**Use Android** (#184), in the app only (bridge's
`google_authorize_available`): the store `Android(account)`, the file in
the app data folder of the device's Google account's Drive
(`src/drive.bats`: a listing for its id and version, then its bytes; a
write checks the version is still the one read, else it is a
conflict, and replaces the bytes, or makes the file in
`appDataFolder`). The access token for `drive.appdata` comes from
bridge's `google_authorize` (#321: bats-lang/capacitor-plugins'
google-authorize, Play services' `AuthorizationClient`, shaped as
Flutter's google_sign_in 7.x; Capawesome's Google Sign-In, which shows
Credential Manager's sheet each time, is not used). Use Android and
Sync now ask with `google_authorize_scopes`, which shows Google's
consent screen only when access is not granted; the syncs the app makes
by itself (`_google_access`) with `google_authorization_for_scopes`,
which never shows anything. The token is kept on the device
("sync-google-token", `_google_token_save`) as well as in memory
(`_token`). When Drive refuses it (401, its hour is up) it is
forgotten, taken out of Play services' cache (`google_clear_token`,
which would otherwise give it again) and one asked for once with
nothing shown (`_google_renewed`): a read is made again, a write's round
reads, merges and writes again. Only `NotAuthorized` (the reader took
access back in the Google account) pauses sync (`SignInAgain`): the
Sync row says "Android · paused, tap Sync now", the screen "Sync
paused: tap Sync now to sign in to Google again", no banner; each sync
point still asks with nothing shown (`_paused` is a browser's only), so
a grant given back ends the pause, and Sync now asks for consent. A
cancel says so, and a failure by its code (`_authorize_failure`:
NETWORK_ERROR or TIMEOUT can't reach the server, anything else Google
refused). The account ("sync-android") is the one the authorization
names, else Drive's (`drive_account_address`: about.get's
`user.emailAddress`, which `drive.appdata` may read), else none. Turn
off holds the token for the Undo; made final, it takes the grant back
(`_google_revoke`): `google_revoke_access` with the account and the
scope, or, with no account, Google's revocation endpoint with the token
(`drive_grant_revoke`). A build with no client lists no Use Android.
In a browser (Google Drive, below) the token comes from Google Identity
Services, whose window a page may open only at a tap: there it is asked
for only when the reader acts, a refused one pauses sync, and while
paused with no token the app tries nothing by itself (`_paused`), so
opening it again changes nothing. The client ID is public and not
compiled in:
it is committed in `scripts/sync-clients.env` (#200: the Web
application client `GOOGLE_WEB_CLIENT_ID`, with the Android client's ID
and Play's app signing SHA-1 recorded beside it, and Dropbox's app key,
#239; all public, none a repository variable), and
`scripts/sync-clients.sh` writes the Google client and the Dropbox key
(checked) into `sync-clients.json` beside the app, in CI and a local
build alike, read by `src/sync_clients.bats`; a build with none lists
neither Use Android nor Google Drive. `sync-identity.yml` prints the upload key's
fingerprints and checks the committed values (the IDs' form, and that
Play's SHA-1 is not the upload key's). The e2e suite stubs Google's
script (`googleStubbed` in `e2e/fixtures.js`), so it never reaches
Google; a spec that plays a provider, or a build with no client, serves
its own `sync-clients.json` (`clientsServed`). With no store chosen, the app keeps the file for Android's
Auto Backup (`STORE_BACKUP`, bridge's `backup_file` in `backup/` of
the app's files, the only thing pwa's backup rules keep): each sync
point merges it and writes it there, and the file a reinstall
restores is merged at the first launch like any sync file; a store's
write writes it too. `e2e/sync-android.spec.js` plays GoogleAuthorize
(the account's grant, Play services' token cache and the account it
names, `capacitorPlayed` in `e2e/sync-stores.js`), Filesystem, Drive's
API and Google's revocation endpoint. In a browser the same store is **Google Drive**
(bridge's `google_token_get` there goes through Google Identity
Services' token model: a token for about an hour, no refresh token),
listed only in a build with a client, so Google's script is loaded
only then; the summary says "Google Drive · ...", and Turn off revokes
the token bridge was given in this session (one kept from an earlier
session lapses within its hour) and forgets the one kept.

**Dropbox** (#184): the store `Dropbox(refresh)`, the same `quire-sync.json` in the
app's own folder (Apps › Quire; scopes `files.content.read` and
`files.content.write`). `src/dropbox.bats` reads it with
`files/download` (its rev from the `Dropbox-API-Result` header; a 409
`not_found` is no file yet) and writes it with `files/upload`, mode
`add`, or `update` with the rev read: a 409 `conflict` is the
conflict. `src/web_request.bats` holds the requests it shares with
`src/drive.bats`. The sign-in is OAuth's code flow with PKCE (S256, no
secret: the app key of the Dropbox app "Quire reader" is public,
committed as `DROPBOX_CLIENT_ID` in `scripts/sync-clients.env` (#239)
and written into `sync-clients.json` as `dropboxClient`; a build
without one lists no Dropbox). `sync_dropbox`
keeps the verifier and state ("sync-dropbox-sign-in") and leaves the
page for Dropbox's (bridge's `navigate_away`), which sends the reader
back to the page's own address with `?oauth=dropbox` (the registered
redirects are in `sync-identity.yml`). As the page opens,
`sync_start` takes the code and state from the address and puts the
address back (`replace_state`), Settings opens (`sync_returning`), and
the code is exchanged once the state matches (another's is refused);
the refresh token is kept and the access token held in memory
(`_token`), got again from the refresh token when Dropbox refuses it
(401), with no sign-in. Turn off, once made final, revokes the grant.
In the app (RFC 8252's way for a native app), Dropbox's page opens in
the system browser's tab over the app (bridge's `browser_tab_open`,
Capacitor's Browser plugin), and the redirect is the app's own address,
`quire://oauth/dropbox`. `src/bin/gen-pwa.bats` writes the Android
project's `intent-filters.xml` itself: pwa's `build_intent_filters`,
then the `quire` scheme's filter (`APP_SCHEME`; a scheme Android cannot
match fails the build). pwa's activity hands each such address to the
page once, not again when it is recreated. The app is opened there,
and bridge's `listen_app_link` (the App plugin's `appUrlOpen`, the
`RAppLink` slot of `regs`) hands the address to `sync_app_link`, which
takes the code and state as a browser takes them from its address; the
tab is gone by then (the app's activity is `singleTask`, so coming
forward finishes what is above it, bats-lang/bridge#135). One that
starts the app again (Android stopped it while the reader was in the
browser) waits for `sync_start` to load the stores (`start_state`); one
while the app runs is taken at once (`return_moment`: `AtStart`,
`WhileOpen`). Dropbox is listed in the app only with both plugins
(`_round_trip_available`: `browser_tab_available` and
`app_link_available`, quire's own sequencing of the two).
Dynamic client registration was tried and Dropbox refuses it (only its
trusted partners may), so the app is registered by hand (quire#239).
`e2e/sync-dropbox.spec.js` plays Dropbox's sign-in page, token
endpoint and files API (`e2e/dropbox-server.js`), and
`e2e/sync-dropbox-android.spec.js` the app's Browser and App plugins
with it.
