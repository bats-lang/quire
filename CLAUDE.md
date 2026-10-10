# quire

## Decisions are made by research, not left to the human

No task is ever "left to the human" unless an agent physically cannot do
it (a permission it was denied, access it does not have, a secret it
cannot see). Every other question, design choices included (which
layout, which wording, which default), is settled by research (what
other apps do, what their users and reviewers say, what studies and
guidelines say) and best judgement, written down where it is decided
(the issue or the PR), and then done. Judgement is what is left after
the research, never a substitute for it: a value or a design chosen
with no look at what comparable software does (the libraries,
frameworks and apps that face the same question, and what they chose
and why) is not decided. "The platform documents no value" is where
the research goes on, to what others do, not where it stops; if
nothing comparable can be found, say so where it is decided, with what
was searched. The quality rules below (the
proofs, the static tests, the e2e suite) still hold: when a choice
would break one, choose another that keeps it.

## A proof is a proof

When a requirement says proof, it means a static proof, checked by the
compiler from types and lemmas. It never means a test, a runtime check,
a read-back, an assertion or a witness that is only believed. A claim
that is only tested is said to be tested, and the proof is still owed:
where the proof system cannot reach (the array package had no model of
an array's contents), the tool is extended (a content-indexed array API
in the array package), not worked around at runtime. Trusted primitives
live in the one package that owns the platform, state what they assume,
and are tested there; nothing in quire uses `praxi`, `assume` or
`$UNSAFE` to skip a proof.

## Names are words

Element ids, numbered-id prefixes (up to 16 bytes), variables, static
indices and functions are named by what they are, in words:
`search-close`, `toc-row12`, `query`, `query_len`, not `qsrz`, `qe`,
`q`, `qn`. Nothing is short of bytes, and terse names collide: four
new ids once took existing ones, and a rename of the id `qn` also hit
a query length of the same name. A loop index (`i`, `j`) or a
conventional pair (`l` and `n` for an array's location and size) may
stay short within a few lines.

## Priorities

* **p0:** first, before anything else.
* **p1:** next.
* **p2:** known issues the Android release is held for. Work sessions
  address them.
* **p3:** not held for. A session may file p3 issues but does not work
  on them.

## CI is pinned

Every input to CI is pinned in the source (#203), so a commit that
passes keeps passing: the packages by the committed `bats.lock`, the
compiler by its commit in `.github/bats-version`, and pwa's Android
workflow by its commit (`android.yml@<sha>` in `check.yml`). CI never
runs `bats lock`: `bats check` and `bats build` fetch exactly the locked
versions, and fail when a locked one is missing or the lock does not
match the project (a package used but not locked, or locked but not
used).

A quire PR that adopts new package versions runs `bats lock --repository
<dir>` and commits `bats.lock` with the change that needs them. Package
releases publish first; then the quire PR with the new lock. A publish
never turns main red: until a lock names it, quire does not use it. The
daily `relock.yml` (the shared `relock-pins.yml` of
bats-lang/repository-prototype, called by commit) relocks against the
newest, moves the compiler pin, pushes `relock/<date>`, opens a PR
listing the old and new versions and dispatches `check.yml` on it, so a
breaking publish shows as a red relock PR. GITHUB_TOKEN cannot change
workflow files, so without a `RELOCK_TOKEN` secret that PR lists pwa's
`android.yml` pin as not moved; move it in a PR of its own.

### The compiler's cache (#460)

`build` and the `static` jobs each compiled the whole app from nothing
(about 10 minutes of the same work four times). A pull request's jobs
now restore the `build/` directory of the newest earlier build under the
same toolchain (`.github/actions/build-cache`, `actions/cache` pinned by
commit), and save theirs once the job passed. What was found:

* What bats keeps (read from the compiler pinned in `.github/bats-version`,
  `src/build.dats` and `helpers.dats`, and a project's `build/`): per
  module a `.dats` and the SHA-256 of its source in `<module>.dats.src`
  (a module is emitted again exactly when the hash, or the target, differs;
  the compiler's comment says an mtime cannot tell, a relocked
  dependency's files keep their archive's), then its C (patsopt's output)
  and objects, which are fresh when newer than the `.dats` and than
  `build/.sats_changed`, a stamp touched whenever an emitted `.sats`
  changes. A build of another target or mode (`.bats_target`: native, wasm,
  and 2 more in check and test mode) is set aside in `build/.stash/<n>`
  with its mtimes. `check` and `build` therefore never share a cache (check
  is mode 2 and 3, build 0 and 1), so there are two caches, `build` and
  `static`. `.bats_cache_id` drops a cache when the compiler's semantics
  change.
* Staleness. Nothing in `build/` records the compiler, ATS2 or the C
  compiler, so the key names them: `.github/bats-version`, the ATS2 pin
  (`setup-bats/action.yml`), `bats.lock`, `bats.toml`, the runner image and
  architecture. The sources are the key's end, so an exact hit is the same
  sources, and a prefix hit is the incremental build the compiler does on a
  developer's machine: a changed module is re-emitted by its hash (its
  `.dats` is then newer than its C), a changed `.sats` rebuilds every
  module that staloads it. A cache is saved only by a job that passed
  (`actions/cache` saves on success only), so it holds no failed build, and a
  module that failed to emit has an empty `.src` and is never fresh. The
  residual risk is a bug of that incremental logic, so main never restores:
  a push to main (and the merge queue's run, and a dispatched relock) builds
  and checks from nothing, then saves for the pull requests (GitHub gives a
  pull request its base branch's caches, and a pull request's own are
  readable only by that pull request: same repository, no cross-fork
  writes). The required check on a pull request is incremental, main's is
  cold, so a stale hit would show on main at the latest.
* Paths. patsopt names C symbols by the absolute path of the files, so a
  cache is valid at the path it was made at. `build` is at the checkout,
  `/home/runner/work/quire/quire` in every job. The static jobs checked in
  `mktemp -d`, a different path each time; `tests/static/run.sh` now takes
  `QUIRE_STATIC_WORK`, a fixed directory (CI: `$RUNNER_TEMP/quire-static`),
  where the app is copied and checked and which is not removed.
* Sharing. Jobs of one run start together, so none sees what another saves:
  the gain is from the previous build (main's, or the pull request's earlier
  push), a few modules instead of 63, in all four jobs at once, and not from
  a job feeding another (a first job the others wait for would have made the
  run longer). Each static group saves the same key; the second to finish
  gets a warning, not a failure. Caches are immutable, 10 GB per repository,
  evicted by last access and after 7 days unused: a miss is today's cold
  build.
* What others do. Swatinem/rust-cache keys on the lockfile, the rustc version
  and the toolchain's environment, restores the newest older cache for a
  changed lockfile, caches dependencies only (the workspace's crates are not
  cached, "generally not effective"), deletes incremental artifacts and
  anything older than a week before saving, sets `CARGO_INCREMENTAL=0`,
  and suggests `save-if` main only. ccache and sccache key each result on a
  hash of the preprocessed source and the compiler and flags, never on a
  time, and Bazel's remote cache is content-addressed with the toolchain among
  the inputs: they are right where the key holds every input. bats's
  own rule for C is a time, which is why the toolchain is in the key, only
  passed builds are saved, and main is checked cold.

## Check locally before every push

A session sets up the compiler in its own environment and runs `bats
check` before it pushes, so a push that does not type-check never
reaches CI (#350's first push failed on a comparison and a free that
`bats check` rejects in a few minutes; CI took 15 to learn it). Setup is
what `.github/actions/setup-bats` does: ATS2 (`patsopt` from the
tarball it names), `lld`, the compiler built from the commit in
`.github/bats-version` (its `bootstrap/c`, `make release/bats`), and a
clone of bats-lang/repository-prototype; then `scripts/version.sh` and
`bats check --repository <the clone>`. A check takes about 10 minutes
on a cold build: run it in the background and wait for it, never push on
the hope that it passes. A change to a spec or a static fixture runs
that group too where the machine can (`tests/static/run.sh`, `npx
playwright test <spec>`), and what it cannot run is left to CI and said
in the PR. A fix pushed after a red CI is checked the same way first.

The e2e suite needs Playwright 1.58 or later (`package.json` says so,
`package-lock.json` pins 1.58.2): before 1.58 its fake clock can set the
time back after a `page.clock.fastForward` (a `_runTo` already in flight
finishes after the jump and writes its old target over it; 1.58 ignores a
target in the past), so a spec that counts minutes, like "the minutes
read on each device are summed" (#352), loses one now and then (about one
run in five on 1.56.1; none in 40 on 1.58.2). A machine whose Chromium
build is older than 1.58 expects (`ls $PLAYWRIGHT_BROWSERS_PATH`) runs
1.58.2 on it by pointing `PLAYWRIGHT_BROWSERS_PATH` at a directory whose
`chromium_headless_shell-1208/chrome-headless-shell-linux64/chrome-headless-shell`
is a link to the installed `headless_shell`; it does not downgrade
Playwright.

## The version is the commit's

Quire's version is the date of the commit it is built from, never of the
build, so the same commit always gives the same version (#219): the
committer date in UTC as bats packages are versioned,
`YEAR.MONTH.DAY.SECONDS` (seconds since midnight), and the short SHA,
`2026.10.2.61373 (f95ce82)`. `scripts/version.sh` writes it into
`src/version.bats` (not in git; run it before `bats check` or `build`),
which the app and gen-pwa compile in: About shows it, a backup records
it (`appVersion`), and gen-pwa appends it to the Android project's
`android-release.gradle` as `versionName`, with `versionCode` the same
time in minutes since 2025 (so it grows from release to release, and
pwa's run-number code is overridden). CI writes it for a pull request's
own head (`QUIRE_COMMIT`, the merge's second parent, hence
`fetch-depth: 2`), and for a run of a merge queue's group (`merge_group`
in `check.yml`, should a queue be switched on) from the group's own
commit (`github.sha`). `tests/version/same.sh` checks that it is the
same in other time zones and that the Android project carries it.

## To do: book memory in a rolling window of page arenas

Partly done: the window exists (`src/pages.bats`), and the buffers a
chapter or image is parsed from come from the current page's arena. The
rest is the intended design.

Everything that belongs to a book's content (chapter text, pictures and
other images, per-page layout data) is allocated from arenas (array's
`arena_create` / `arena_alloc`), not with `alloc`. `alloc` is bounded at
1 MiB on purpose, to limit fragmentation (see array's CLAUDE.md), and a
page's content does not belong in scattered long-lived allocations.

* One arena per page, sized to hold a page with generous limits for
  images and the like.
* Five arenas live at a time: the current page, the 2 pages before it and
  the 2 after it.
* Turning forward one page releases the arena of the page that is now 3
  back and prepares the arena of the page that is now 2 ahead (turning
  back does the mirror image): a rolling window.
* Arenas are created and destroyed whole and never reused piecemeal, so
  they cannot fragment.

The point of doing this in ATS2 rather than Rust is that the arena
discipline is checked at compile time:

* a piece that does not fit its page's arena does not type-check;
* a page's pieces cannot be freed on their own, or given back to
  another page's arena;
* a page's arena cannot be released while any of its pieces is still in
  use (the arena's outstanding count must be 0), so nothing on screen
  can point into a released page.

The window itself should be in the types too: the reader state holds
exactly the five arenas, indexed by page number, so a page outside the
window has no arena to allocate from.

### The window today

`src/pages.bats` holds it. `page_arena(page, pages)` is the arena of
that page of a chapter of that many pages, with no piece out; it exists
only for `0 <= page < pages`. `window(page, pages)` holds exactly the
arenas of pages page - 2 to page + 2 (scrolled, a page is a screenful,
so the window counts those). `window_forward` turns it into
`window(page + 1, pages)` by releasing page - 2's arena and making
page + 3's (`window_back` is the mirror image), so keeping any other
arena does not type-check. Each arena is 4 MiB (`PAGE_BYTES`).

The reader's window lives in a `ref` taken out and put back with
`ref_exch_elt`, since it is linear. `_show_page` moves it to the page
shown: one page on rotates it, and any other move (a jump, a new
chapter, a new page count after a resize) releases it and makes it
anew. Going back to the library releases it (`window_close`).

A buffer a book's content is parsed from (`piece_new` in
`src/book.bats`: an entry's data, a decompressed OPF, chapter or image)
is a piece of the current page's arena when it fits there
(`page_lend`). The arena leaves the window while the piece is out (its
slot is `Lent`), so the arena in the window never has a piece out, and
`page_give_back` returns it to its slot, or releases it when the window
has moved on. When there is no window yet (the first chapter's load),
or the page has no room, the piece is the one piece of an arena of its
own, as before. `piece_owner` says which, so `piece_free` gives it back
to the right one.

### Where book content is allocated today

In arena pieces (`piece` in `src/book.bats`: a piece of the current
page's arena, or the one piece of an arena sized to it, so it has no
1 MiB bound):

* an entry's compressed data (the piece `index_read` returns): the
  container.xml, the OPF and each chapter;
* decompressed content (`take_content`): the container.xml, the OPF and
  each chapter's XHTML;
* the OPF's compressed data when a chapter is loaded (`opf_cbuf`);
* each image's bytes (`_show_image` in `src/reader.bats`);
* a book's annotations while a backup is written (`annot_json`), each
  book's part of the backup, and the whole file (`backup_export`);
* a backup file while it is restored (`backup_import`);
* a dictionary's .idx and .syn while it is imported, and its table
  (`_index_read`, `_table_store` in `src/dictionary.bats`); an article
  read from a .dict, or the dictzip chunks that hold it and their
  inflated bytes (`_article`, `_article_dz`);
* a page of an OPDS catalogue (at most 4 MiB, `FEED_MOST`) and its
  OpenSearch description while they are read, and a book's EPUB got
  from one until it is handed to the JS side as a file (`_claim` in
  `src/catalogue.bats`); the catalogues' part of the backup
  (`catalogue_backup_json` in `src/catalogues.bats`);
* the sync file: as it is read from the store, each chunk of the merge
  and the merge joined as it is written (`_out`, `_remote`, `_written`
  in `src/sync.bats`), refused over 16 MiB (`SYNC_MAX_BYTES`);
* a chapter's text read aloud (its `script`, `reader_script_load` in
  `src/reader.bats`), held while the chapter is read aloud; each
  block's copy while it is cut into sentences; and each sentence's copy
  while it is said (`script_text`);
* a narrated chapter's SMIL, its compressed data and its content, from
  when it is read until the chapter is rendered (`_overlay_load` in
  `src/reader.bats`), and a deflated audio entry's data and inflated
  bytes while a blob URL is made of them (`_source_then` in
  `src/narration.bats`).

The one long-lived arena piece is a narrated chapter's clip table
(`clip_table` in `src/overlay.bats`): the one piece of an arena of its
own (so it never holds a page's arena out of the window), at most 1 MiB,
kept until the next chapter is rendered.

Each piece lives only while it is parsed or written, except the
script read aloud, which outlives page turns (the arena it was lent from
is released when it is given back, if the window has moved on): pages
are CSS columns of the chapter's DOM.

With `alloc`:

* `src/book.bats` (`book_index_make`): the archive's tail and each
  entry's local header while the book is opened, and its central
  directory (at most 1 MiB), kept while the book is open for its
  entries' names.
* `src/book_cards.bats` (import): the OPF path (`opf_path_buf`, under
  65536 bytes as a zip name is) and a title buffer (`tbuf`).
* `src/reader.bats`: the OPF's name (for its directory), the chapter
  path (`ch_buf`), and title and text copies (`exact`, `tbuf`).
* The EPUB file itself never stays in wasm memory: bridge's file module
  keeps it on the JS side, it is read by ranges, and it is saved to and
  restored from IndexedDB there (`$BF.file_idb_put`, `$BF.file_idb_get`).
  Only a book got from a catalogue passes through, in an arena piece,
  since the bridge's fetch hands its bytes to wasm and `$BF.file_store`
  takes them back.
* Everything else (`src/bin/quire.bats`, the small buffers in
  `reader.bats`) is element ids, event names and storage keys: UI, not
  book content; it stays on `alloc`.

### Offline dictionaries

`src/dictionary.bats` keeps the StarDict dictionaries Look up reads
without a connection (`src/stardict.bats` reads their bytes: the
.ifo's keys, the headwords' order, an article as text). Like an EPUB,
a dictionary's files never enter wasm memory to stay: they are stored
from the JS side (bridge's `$BF.file_idb_put`) and read back by
ranges. Its import checks the .ifo and the .idx's size, every record
of the .idx and .syn, and a .dict.dz's chunk table, and stores a table ('X') of
every 64th headword of each with where its record is; a lookup
binary-searches it and reads one block of records. An article is
shown as text only (`article_text`): HTML and XDXF tags are dropped,
never put in the DOM. The list of dictionaries (`dicts`) is stored
under "dicts"; a removal moves the dictionary to the Trash (#396, as a
book is: `dict_state`, `Installed | InTrash`, stored in bit 4 of the
form's byte), offered back by the Undo toast, its files kept. It is out of
Look up, listed under the books while the Trash is the shelf shown
(`trash-dictionaries`, `dict_trash_render`) with a Restore, and only Empty
Trash deletes its files (`dict_trash_empty`, in quire.bats' `_harm_clicked`
after `lib_ask_harm` resolves Accepted; the dialog says dictionaries go
too). `tests/static/trash.py` fails any other call: that is a scan of the
source, not a type, and the proof that only an answered dialog deletes
them is owed (the dialog is in library.bats, which cannot staload
dictionary.sats while dictionary.bats uses library's `lib_key`). Drive and
Files by Google keep trashed items, which still use storage, until they
are emptied; the Trash shows counts, not sizes (a dictionary's files are
on the JS side). The backup lists the
dictionaries' names and languages, not their files.

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

### Catalogues

`src/catalogues.bats` keeps the OPDS catalogues books are got from
(the library menu's Catalogues): each one's name and URL, stored under
"catalogues", Project Gutenberg's alone until the list is changed. A
removal is offered back by the Undo toast; the backup lists them by
name and URL. `src/catalogue.bats` browses one, a page at a time, each
page a step of a trail Back walks (and from the first page, back to
the list). A page is fetched through the bridge (`$FE.fetch`: its
status and bytes), read into an arena piece of at most 4 MiB (a larger
one is refused) and read by `src/opds.bats`, OPDS 1.2 (Atom, with
xml-tree) or OPDS 2 (JSON, with jsonio), into a feed of at most 500
entries: links to other pages, and books (title, author, cover, EPUB)
with Get; its next and previous pages; its search template
(`{searchTerms}`, or OPDS 2's `{?query}`), or the OpenSearch
description that holds one, fetched after the page. Every address is
resolved against the page's own (`src/url.bats`, RFC 3986). Get
fetches the EPUB acquisition link (an EPUB 3 one first), puts its
bytes on the JS side (bridge's `$BF.file_store`) and imports them as a
picked file is (`import_fetched`), so a book already there is asked
about. Where the fetch fails (in a browser, a page without CORS), Get
gives way to a download link (`ui_download_nn`) "then import it". A
page that cannot be read says why: not readable by a browser, not
found (404), needs a sign-in (401, 403), or not a catalogue.

### Narration

A book with EPUB 3 Media Overlays (EPUB 3.3 §9) is read aloud by its
own recorded narration (issue #133). Its chapters' overlays are found
once, with the chapters (`_spine_build`): a spine item's manifest
`media-overlay` names the SMIL's item, whose entry is kept in the
chapter (`chapter_overlay` in `src/book.bats`); `_book_narrated` is set
when any chapter has one, and the bottom bar's `narration-controls`
then take the place of reading aloud by speech (`_narration_offered`).

`src/overlay.bats` reads a SMIL's bytes (the format alone, as
`src/stardict.bats` reads a dictionary's): its body, seq and par
elements flattened, in order, into clips, each a par with an audio
element (one without is passed over; `media:duration` is not read).
Each clip is 32 bytes of a `clip_table(count)`, at most 32768: its
begin and end (clock values as H.4 has them; no clipEnd is the audio's
end; a value over 2^31 - 1 ms makes the clip invalid), its audio entry
(found relative to the SMIL's directory when the chapter loads), its
text's fragment, whether it is skippable (it or a seq around it is a
footnote, endnote or pagebreak) and the clip after the innermost
escapable table, list, figure or aside it is in. A clip's index is
proven below the table's count, so reading past the table does not
type-check (`tests/static/reject/clip-past-end`).

As a narrated chapter is rendered, an element with an id is matched
against the next 8 clips not yet matched (`_clip_match` in
`src/reader.bats`): a match keeps the element's first content node and
the one after its last (`!_content_count` after its children, as
`_link` does). An unmatched clip still plays, with nothing marked and
no page turned. Then the SMIL is freed and only the clip table is kept,
for the narration to take (`reader_clips_take`).

`src/narration.bats` plays it on one `<audio id="narration">` (made by
`ui_audio`: no controls, `aria-hidden`; not a control, so the tag type
stays closed to them), for the whole book, so the permission a click
gave it holds clip after clip. Its state is `Idle`, `Playing(clip,
generation)` or `Paused(clip, at)`, each clip proven below the table's
count. The source is a blob URL of the audio entry, made on the JS side
from the book's file when it is stored (`book_blob_url`, file's
`file_blob_url`), or from its bytes inflated into a piece when it is
deflated; the URL is revoked when the entry changes and when the book
is closed. Each clip is played from its begin (one that follows the
last in the same audio plays on without a seek), marked with
`mark_range` kind 5 (`::highlight(bats-mark-5)`, the proven pair of
read-aloud's highlight), and its page shown when its text is not on
the page. A timer at its end, by the speed, checks `audio_time` and
moves on within 20 ms of the end, else sets itself again; the timer
reaches `_tick` through a cell (`_tick_handler`), as an event reaches
its listener, so playing on is not a recursion. `timeupdate` is a
backstop, and `ended` covers an audio file shorter than its clip. A
generation number drops the timers and answers of earlier clips. At a
chapter's end the narration goes on into the next chapter with an
overlay (`book_narrated_after`). A page the reader shows (a turn, a
jump, a new chapter; the promise `reader_page_shown` resolves) moves it
there: from the first clip on or after the page, or the chapter's
first; so does a tap on text a clip reads. A play the browser refuses,
or an `error`, stops it, and the error banner says "This narration
cannot be played"; a
`pause` it did not ask for (a headset, a call) leaves it paused. The
screen stays awake while the reader is open, so while it plays.

The controls: Read aloud (`aria-pressed`), Previous phrase, Next phrase,
and, inside an escapable structure, Skip table (list, figure, aside).
The reading settings' Read aloud tab offers, for a narrated book, its speed (0.5× to
2× in quarters, `audio_rate`, the pitch kept) and whether page numbers
and notes are read (Skip by default: skippable clips are passed over).
Both are the device's own, kept outside the settings record as `_ruby`
is; in its storage they follow the voices, after an "N" (a record
written before them has their defaults); the reset's Undo and the
backup's settings (`narrationSpeed` in hundredths, `narrationReadsNotes`)
cover them.

### The archive is checked once

`book_begin` opens a book (an import, or a restore from IndexedDB) and
checks its archive then, once: the end record, the central directory
(zip's `cd_refs`) and every entry's local header. What survives is the
book's index (`book_index`): the kept directory and a list of entries
whose data spans are proven inside the file. Reading an entry
(`index_read`, for the container.xml, the OPF, a chapter or an image)
only looks its name up there; nothing in the file is checked again.

A book's chapters are found once too, the first time one is loaded
(`_spine_build` in `src/reader.bats`): the OPF is read and parsed, and
each spine item's href, after the OPF's directory, is looked up in the
index. The chapters (`book_chapters`, each an entry whose data span is
proven, or missing) are kept in the book (`book_spine_set`), so loading
chapter i only walks to it (`book_chapter_get`); the OPF is not read
again.

### Note popups (#414)

A note opens as its text, in one popup (`footnote`): an element's text
is gathered from the chapter's XHTML by its id (so a note marked `aside`,
`div`, `li` or none, and one `hidden` or not, all open), a block ends in a
space and an inline element does not (a reference "3" and the "." after it
stay together), and a note over 4 KiB (`NOTE_CAPACITY`) ends in an ellipsis,
cut at a whole character and outside a character reference. The popup has no
links in it: links in a popup are what an iBooks popover collapsed on (Stack
Overflow 12952352) and Apple advises a note of one paragraph; the note's own
links, nested notes and backlink work where the note is, which Go to note
reaches, with the way back. No unmarked footnote is detected (Calibre's
maintainer does; Apple Books and Kobo ask for markup, and a heuristic opens a
popup for a "see 3" cross-reference): an unmarked link is a link.
`e2e/footnotes.spec.js` plays `e2e/note-books.js`.
### Wide and structured content (#413)
A table is its own scroll container (`.caf table`: `overflow: auto`), at
most as wide as the column and as tall as the reading area
(`calc(100dvh - var(--page-top) - var(--page-bottom))`, as a picture is):
a block that scrolls cannot be split between columns, so a table taller
than the page, as it was (`overflow-x` made it scrollable too), lost every
row past the page's foot (90 rows: the first six were all that could be
read). `pre` wraps (`white-space: pre-wrap`) and keeps its spaces, tabs
and blank lines, and, being no scroll container, continues over the pages.
Verse keeps its `<br/>` lines and the indents made of no-break spaces;
indents made of the book's CSS (`text-indent`, `padding-left`, hanging)
are not kept, since no publisher CSS is applied (#411), and a wrapped
line of verse is told from a new one only by the text.
`e2e/wide.spec.js` plays `e2e/wide-books.js`.
### Position stability and page-turner keys (#412)
The place is a content node (the first paragraph that begins on the page,
`_anchor_kept`), not a page: `e2e/stability.spec.js` changes each of the
theme, font, size, line spacing, paragraph spacing, margins and columns,
and the window (paged, two columns, scrolled, vertical, fixed-layout),
several in a row, and kills the app after each, and the paragraph is on the
page shown (the one at the page's middle is not: a page's first
paragraph is what is kept); a book converted from each of QLB1 to QLB6
opens at its stored chapter, page and anchor (`e2e/legacy-library.js`
holds the old record and the store for it, as `library-records.spec.js`
uses them). Keys: the page turns by the arrows, Page Up and Down, Space
(Shift for back), the volume keys when the reader chooses (the Android
app's), and MediaTrackNext and MediaTrackPrevious (a page turner's
multimedia mode: the DuRoBo Moodi sends previous and next track there, its
reading mode the volume keys; the others in the field send the arrows or Page
Up and Down). Enter follows the focused link and is no page key. Keys are not
the page's while a text field or a panel has the focus, and a volume key is
the system's while a panel is open. `QUIRE_PORT` in `playwright.config.js` is
the port the app is served on, so two runs of the suite from two checkouts
do not serve each other's build.
### Where a book opens the first time (#409)
A book never read opens where it says reading starts, as Apple Books
opens at the bodymatter landmark (and as the EPUB 3.3 landmarks section,
DAISY's knowledge base and Thorium's "Start of Content" have it), not at
its cover or copyright page: `toc_start_dest` (`src/toc.bats`) gives the
chapter and fragment of the first `bodymatter` entry of the nav document's
`landmarks` nav (`nav_part`'s `PartStart`, read beside the contents and
the page list in `toc_build`), else, for a book with none (EPUB 2), of the
OPF's `<guide>` `<reference type="text">` (`find_guide_text`, its entry
found in `toc_locate`; its fragment is not kept). A start that names no
chapter of the book (no href, a file the book lacks, one outside it)
gives none, and the book opens at its first spine item, saying nothing.
`reader_open_at` takes `unread`: set by `_open_book` only when the place
is the first chapter's first page, no move has been dated
(`place_modified` 0) and no minute is read, so a book once read, even
back at its first page, opens at its kept place. The chapters, contents
and fonts are made ready first (`_book_prepare`), so the cover is never
shown before the jump; the jump is not dated, as no open is.
The landmarks are not listed in Contents (issue #409: Apple Books uses
the bodymatter landmark to open the book and lists none, Calibre's viewer
shows none, only Thorium has a Landmarks list; publishers put the
contents page, index and list of illustrations in the table of contents
too, so the list would repeat it).
`e2e/landmarks.spec.js` plays the books in `e2e/landmark-books.js`
(`createEpub`'s `landmarks`, `guide` and `epub2`), and
`e2e/epubcheck.spec.js` checks every book there with epubcheck (5.2.1,
pinned with its SHA-256 in `check.yml`; `EPUBCHECK_JAR` names the jar
locally): a valid book must pass, one that is invalid on purpose (a
landmark naming a file the book lacks) may give only the errors its
entry lists.
### Publisher styling and the reader's settings (#411)
No part of a book's own styling reaches the page: the CSS (a `<style>`, a
style attribute, `!important`, a media rule) is dropped with the rest, and
so are the obsolete presentational attributes (`<font>`, `bgcolor`,
`width`), so a book's sizes, colours, grounds, margins, alignment, line
height and font cannot fight the size, theme, margins, Justify, spacing and
Font settings, and no theme has a light slab. That is the opposite of
Readium CSS (Thorium), which keeps the publisher's styles unless the reader
turns advanced settings on, and in which an `!important` in a book can beat
a setting. What only CSS hid (`display:none` by a rule or a style
attribute) is shown, there being no CSS to say it; the `hidden` attribute is
HTML's own word and is kept: `_pass_attrs` gives an element that has it the
class `hidden-by-book`, which the stylesheet hides. `e2e/publisher.spec.js`
plays `e2e/publisher-books.js`.

### The print page list and page breaks (#415)

The Pages tab lists the page list's entries as the book gives them (not
sorted, duplicates kept, each going to its own target); an entry whose chapter
the book lacks is listed and leads nowhere (the panel stays), one whose fragment
is missing goes to its chapter, an empty page list shows no tab. The
footer names the latest page the screen reaches, from the break's `title`, else
its `aria-label`, whichever of `epub:type="pagebreak"` or `role="doc-pagebreak"`
the element has, with no page list too; a break with neither is shown and names
no page. A label in the contents or the page list is decoded as any text is
(numeric references too) and cut at a whole character.
`e2e/pagelist.spec.js` plays `e2e/pagelist-books.js`.
### EPUB 2 packages (#416)
A package of version 2.0 (OPF 2.0, XHTML 1.1, an NCX, no nav) opens as
an EPUB 3 one does: its contents are the NCX (`navPoint`s listed in
document order, whatever their `playOrder`; one with no `content` is listed
and leads nowhere, one with no label is "Untitled"), its cover the
manifest item a `<meta name="cover">` names, its `<guide>`'s `text`
reference where a first open lands (#409), its author the first
`dc:creator` as written (`opf:file-as` is not read: books are sorted by
the name shown). XHTML 1.1's named entities (`&nbsp;`, `&mdash;`) are
decoded as any text's are. A DTBook or OEB 1 spine item (`application/x-dtbook+xml`,
`text/x-oeb1-document`, which a package names an XHTML fallback for) is read
as XML and its text shown. A Hebrew book whose spine names no direction
reads right to left, as Readium reads it. A row of the contents or the
page list that leads nowhere keeps the panel up (`reader_goto_entry` and
`reader_goto_page` say whether they went).
`e2e/epub2.spec.js` plays `e2e/epub2-books.js` (create-epub.js's `epub2`,
`creatorXml`, `ncxNavMap`, `alsoNav` and `extraSpine`), each book valid
under epubcheck 2.0 rules except those invalid on purpose.

### Found while taking this inventory

* (Fixed) An EPUB larger than 1 MiB could not be imported, because the
  whole file was read into one `alloc`. Entries are now read at their
  offsets, and the file has no size bound. An entry's data and its
  decompressed content are read into arena pieces, so a chapter over
  1 MiB is shown; only the central directory is still read into one
  buffer of at most 1 MiB.
* (Fixed) Book images were not shown. A chapter's `<img>` elements are
  now filled once the chapter is rendered: each src is resolved against
  the chapter's directory ("." and ".." segments, a "#fragment"
  dropped), its entry read into an arena piece (decompressed into
  another when deflated) and handed to the element as a blob URL. An SVG
  `<image>` (a cover page's usual form) is shown the same way, as an
  `<img>` whose source is its `xlink:href` (or `href`).
* (Fixed) Ruby was shown as blocks: `ruby`, `rb`, `rt`, `rtc` and `rp`
  were made `div`s. They are now kept as themselves (`_tag_of`), so a
  reading sits over its base and `rp` is not shown. The settings' Ruby
  row (Show / Hide, byte 19 of the "S2" record, `ruby` in the backup;
  held apart from the settings record in memory, as the device's own
  settings are: each of the record's setters writes it out whole, so a
  field there costs a line in every setter, and a cell of its own one
  setter; quire#210)
  is offered once a chapter of the open book has shown a ruby
  (`_ruby_seen`); Hide adds `.caf rt,.caf rtc{display:none}` to
  `style-type`. Search (`_scan_node`) does not match inside `rt`, `rtc`
  or `rp`, but counts their content nodes as render makes them, so a
  hit or an annotation after a ruby keeps its node number.

## Spine items and fallbacks (#419)

The W3C's EPUB 3 test suite (`reports/quire-w3c-epub-tests.md`) found that
a spine item was read as XHTML whatever its type: a 3 MB PNG as a spine
item killed the page (`lay-pp-images-in-spine`), a JSON or XML one was
shown as text and the fallback its manifest names was never followed.

* **A spine item shows a content document** (`find_chapter_shown_href_n`
  in `src/epub_xml.bats`, used by `_spine_chapters` in `src/reader.bats`):
  the item itself when its media type is `application/xhtml+xml`,
  `image/svg+xml`, `text/html`, an OEB 1 or DTBook document (read through,
  quire#416) or none is given; else the item its `fallback` names, and so on
  down the chain (at most 16 items, so a loop ends), as EPUB 3.3 §3.3
  says. An item with the property `scripted` and a fallback is replaced by
  the fallback too, since Quire runs no scripts (`scr-support-fallback`;
  one with no fallback is shown, scripts unrun). An itemref none of whose
  items is a content document is left out of the chapters, so the reader
  never turns to it and never reads its bytes as XHTML; the book opens at
  the next. Decided by the spec and the suite's reports: EPUB 3.3 (§3.3,
  §3.5.1) makes a foreign resource valid in the spine only with a manifest
  fallback to a content document, and the suite's own pass criterion is
  that the fallback is shown; the W3C working group's minutes (2022-03-11)
  found few reading systems that show it, so the suite's reports hold
  the comparison (`lay-pp-images-in-spine` 2/2, `pub-foreign_json-spine`
  4/9 pass). No documentation of what Thorium or Readium do with a
  spine item they cannot render with no fallback was found (searched:
  the specs, the working group's minutes, Readium's wiki); skipping it is
  chosen because the alternatives are a page of binary text or refusing the
  whole book, and no word of the book is lost. The
  chapters' count is the count kept, not the itemrefs' (`_spine_chapters`
  returns both).
* **An `<img>` whose manifest item is a type no browser draws and has a
  fallback is shown as the fallback** (`pub-foreign_image`): at the
  spine build the items that are not a core image type and have a
  `fallback` are found (`find_image_fallback_n`, `find_image_target`: the
  chain down to a core image, 16 items at most, 256 items at most) and
  their entry paths kept (`image_fallbacks`, replaced by the next book's),
  and `_show_image` shows the target's entry when the image's path is a
  kept one, so the image viewer does too.
* **The title and author are the first `dc:title` and `dc:creator`**
  (`_opf_metadata_node`), as EPUB 3.3 §5.4 makes the first title the main
  one and a reader needs one author (`pkg-title-order`,
  `pkg-creator-order`). EPUB 3's `title-type` refinement is not read.

## The archive and the XML are checked for what EPUB forbids (#419)

* **A zip that EPUB's OCF forbids is refused at import** (`src/zipcheck.bats`,
  called from `book_index_make` in `src/book.bats`; the suite's
  `ocf-zip-comp` and `ocf-zip-mult`, both "MUST treat ... as in error"):
  an archive whose end record names a disk other than 0 (a split
  archive), and one with an entry compressed by a method other than stored
  or Deflate. The zip package leaves such an entry out of its references
  without a word (its own documentation says so), so a book with a bzip2
  chapter used to open with the chapter gone; `zipcheck` reads the end
  record's and the central directory's own fields, `book_refusal` says
  why, and the import banner says it (`ArchiveSplit`,
  `CompressionNotAllowed`: "... is a zip split into segments, which an
  EPUB may not be ..."). The zip package is the tool that could report this
  itself (a refusal in `cd_refs`); until it does, the check is Quire's.
* **A content document that is not well formed is not shown**
  (`src/wellformed.bats`, `xml_well_formed`, called by `_chapter_render`;
  `pub-xml-non-validating_unclosed`, `pub-xml-names`, both "The reading
  system must produce an error", EPUB RS 3.3 §3.1: a non-validating XML
  processor, a fatal error for a document that is not well formed):
  an element not closed by its own end tag, an end tag that closes
  another, and an element name with two colons, a colon at either end, a
  digit first or a character no name has. The chapter is then a chapter
  that could not be read: the banner says "Chapter N of this book could
  not be read" and to open another chapter or import it again with
  Replace. Comments, CDATA, processing instructions, the DOCTYPE and
  quoted attribute values (with a `>` in them) are read over, and entity
  references are not checked: XHTML's named entities are decoded as any
  text's are. Of the reading systems the suite holds, 8 of 9 (unclosed)
  and 9 of 9 (names) pass, Thorium and Apple Books among them. The check
  is on the chapter shown; the chapters read for search, notes or
  narration are not refused. xml-tree builds a tree from any bytes, so it
  reports nothing itself; a well-formedness error from the parser would
  be the better place for it.
* **An image the manifest does not list is shown, by decision**
  (`pkg-manifest-unlisted-resource`, a SHOULD): the zip is read by name.
  11 of the 15 reading systems that answered the suite show the image
  too, hiding it would blank the images of books whose manifest is merely
  incomplete, and nothing is gained, the file being in the book's own
  archive.

## The package's directions and language (#419)

* **A title's and an author's direction are the package's** (`opf_text_directions` in
  `src/epub_xml.bats`; the suite's `pkg-dir_creator-rtl`, `pkg-dir_rtl-root-ltr`,
  `pkg-dir_rtl-root-unset`, `pkg-dir_unset-root-rtl`): the first `dc:title` and the first
  `dc:creator` take their own `dir` (`ltr`, `rtl`, `auto`), else the `package` element's.
  They are kept in the book's record as one number (`text_directions`, title + 4 * author, the
  optional group `tdir`, lower case so an older Quire keeps it as an unknown chunk), set at
  import and again by Replace, decoded once into a `text_direction` (`_direction_of_code`), and
  the library card sets `dir` on its title and author (`ADir`). `dir=auto` is the browser's
  first-strong-character rule; none leaves the page's. A book imported before this has none
  until it is replaced. The backup and sync do not carry it (it comes from the package).
* **The package's language and direction are not the content's, by decision, and the suite's
  `pkg-lang_but_not_content` and `pkg-dir_but_not_content` stay failures.** A chapter that
  names no language is shown in the book's (`_page_book_lang`; "und" when the book names none):
  browsers hyphenate and pick quotation marks only for text whose language is known (MDN on
  `hyphens`; the CSS specification requires hyphenation only where the content language is
  known), and the package's `dc:language` is the only language a book declares. A Hebrew or
  Arabic book whose spine names no direction reads right to left (#416, as Readium reads it): the
  page is one flow of CSS columns whose order is the page's `direction`, so a list or paragraph
  in it inherits it. The suite's criterion (a document that names none stays in the reading
  system's own language and left to right) is met by 11 of the 15 reading systems that answered
  for language and all 13 for direction, which lay each document out on its own; Quire's flow
  cannot without giving up one of those two decisions. They stay listed as policy in the report.

## The platform, in Bats

What the browser and the Android app offer beyond the page (reading
aloud, full screen, the rotation lock, the brightness, sharing,
installing, keeping the storage, the local time, files opened with the
app) is quire's own logic, on bridge's typed atoms (each with its
`*_available`, and each JS answer decoded into a datatype that is
matched exhaustively), not pwa's page scripts (bats-lang/pwa#49): no
element carries a `data-pwa-*` marker and no rule keys on a `pwa-*`
class, so pwa's scripts act on nothing of quire's. A control is shown
only where its platform has it, by its own `data-hide`.

* **Reading aloud** (`src/read_aloud.bats`): Read aloud (the bottom
  bar) reads the chapter shown from the first sentence on the page
  (halving the sentences by where each starts against the page:
  `placement`, `Before | OnPage | After`, across as the book reads, down
  when scrolled), Read from here from the sentence the selection starts
  in. A chapter's sentences are its `script` (`src/reader.bats`): the
  text of each block holding no other block (a paragraph, a heading, a
  list item, a quotation, a term, a description, a caption, a cell,
  preformatted text), a ruby's `rt`, `rtc` and `rp` left out but their
  content nodes counted as render makes them (search and render's walk,
  a third time), cut by bridge's `segment_sentences` in the book's
  language; each sentence knows its text and where it is on the page
  (content node and UTF-16 offset at each end). Each is said by
  `speech_speak`, marked with `mark_range` as mark 5
  (`::highlight(bats-mark-5)`, the search hit's proven pair), and when
  the next one starts past the page the page is turned by
  `reader_turn_on` (the next page button's turn, as a promise of
  `turned`: `TurnedPage | TurnedChapter | NotTurned`), into the next
  chapter too, at most 3 turns for one sentence; reading stops where
  nothing turns. The state is one `aloud`: `Silent`, `Loading` (a
  script being made), `Saying` (a sentence, its utterance's number),
  `Turning` (a turn awaited, for a sentence or the chapter's end:
  `turn_for`) or `Paused`; each run is numbered, so what an earlier
  run started is dropped. A pause cancels what is said and says that
  sentence again on resume, when it is still on the page shown (else
  from the page's first): `speechSynthesis.pause()` stops for good on
  Android's Chrome and after some 15 s on desktop Chrome. Read aloud is
  pressed (`aria-pressed`) while it reads, and the screen kept awake
  (`keep_awake`; the reader keeps it awake anyway). The speed
  (`speech_rate`, 0.75 to 2 times) and the voice of each language (by
  the language's primary subtag, the voices whose language has it)
  are kept with the settings, outside the settings record (bytes 20
  and 23 on of "S2", as `ruby` is), so like them they are not saved
  over settings that could not be read (`storage_savable`, #174). They are settings like the others,
  and so are the brightness, the rotation lock and full screen: in the
  backup (`readingSpeed`, `voices`, `brightness`, `rotationLocked`,
  `fullScreen`) and reset
  with the settings, Undo putting them back (`set_reset_undoable`;
  `screen_controls_apply` sets the screen again). Going to the library, opening
  another book, or the page going away (`pagehide`) stops reading.
* **The screen** (`src/screen_controls.bats`, the reading settings'
  Page tab, a row each, quire#300): Full screen (`fullscreen_*`; in the
  app bridge hides both system bars, Capacitor's `SystemBars`, Android's
  immersive mode) and Lock rotation (`orientation_*`, a `rotation` kept
  with the settings and locked again as the app starts) are switches:
  a button named by its label, with a drawn track whose knob moves when
  it is pressed (`_switch_row` in `src/app.bats`), and a line saying
  what it does (`aria-describedby`). In the app full screen is kept
  (quire#313): a `fullscreen_choice` (`FullscreenOff | FullscreenOn`),
  the device's own, after an "F" at the end of the "S2" record, turned
  and kept by the switch (`screen_fullscreen_toggle`) and by nothing
  else, the switch saying it from the first frame
  (`screen_controls_start`). It is the setting for the immersive reading
  screen only (quire#348): the system's bars are hidden when the setting
  is on and the reader is shown with its own bars away (`_immersive`,
  set by quire.bats' `_chrome_set` and `_show_library` through
  `screen_immersive_set`), and shown in the library, in the in-book menu
  and its panels, and as the app starts; the setting is not changed by
  what the bars show, nor by the menu coming up. A browser keeps none:
  the Fullscreen API enters only at a click (the user's activation), so
  a page opened again starts out of it, its switch off, and a click
  there does not change what is kept, and the page is in full screen or
  not as that click left it.
  Where the device refuses the rotation lock (bridge's `LockRefused`),
  Lock rotation is not offered again that session (`_lock_refused` in
  `src/screen_controls.bats`) and the banner says so (quire#355): a
  control that cannot work is not shown. While the reader is immersive and full screen is on, a page shown hides the
  bars again (`_bars_hidden_again` in `src/reader.bats`), since Android
  brings them back at a swipe from the edge, the reader's own way out of
  immersive mode (quire#314). pwa's activity reports each bar's
  visibility at each window insets dispatch (`batsNative.systemBars`,
  bridge's `listen_system_bars`, `RSystemBars`), which lays the chapter
  out again when it changes (quire#356). Brightness while reading
  (`brightness_*`, the app only, quire#392: a `brightness_choice`, the
  device's own or `BrightnessOwn`, with a level of 10 to 100 kept apart
  as the narration's speed is, `set_brightness_level`; kept with the
  settings, in the one byte of the "S2" record that held the five levels
  of the old select (1 to 5 still read as 10, 25, 50, 75, 100), and set
  again as the app starts) is a slider that changes the screen as it
  moves (`screen_brightness_moved`, on each `input` event, so the reader
  sees the brightness they choose and no percentage is shown), and a
  "Same as device" switch (`screen_brightness_system_toggle`) that gives
  the screen back to the system and, pressed again, to the level the
  slider shows.
  `e2e/controls-shown.js` checks, on every screen the layout spec walks,
  that no control's text is cut (a select's chosen option too) and that
  every toggle looks different on and off.
* **Sharing** (`src/sharing.bats`): the selection, quoted and cited
  ("“…”\n— Author, Title"), by `share_text`; the annotations' Markdown
  file (`annot_export` to `ToShare`) by `share_file` where files can be
  shared (`share_as`: `AsFile | AsText`), else, or when the platform
  refuses it as a file (`FilesNotShareable`), as its text.
* **Installing and keeping the storage** (`src/platform.bats`): Install
  Quire is shown while the browser offers to install the app
  (`install_prompt_available`, `listen_install_prompt`) and asks for it
  (`install_prompt`); the Home Screen hint shows on iOS Safari only
  (`is_ios_browser`, `src/library.bats`). The storage is asked to be
  kept (`storage_persist`) once, after the first book is imported, and
  in a browser a line of Settings, under Backup (`settings-storage`),
  says whether it is (`storage_persisted` at startup); the Android
  app's storage is its own, and there nothing is said (#333).
* **The local time** (`src/local_time.bats`): its offset from UTC
  (`timezone_offset_minutes`) and whether it is night (22:00 to 07:00,
  from `epoch_millis`), for the auto theme (checked each minute while a
  book is open, through the timer, and at each page turn) and the
  reading statistics' local day.
* **Files opened with the app** (`launchQueue`, the share target, the
  Android app's files) arrive on bridge's external-file path, which the
  library imports (`OnExternalFiles`); pwa writes no JS of its own
  (bats-lang/pwa#49), so bridge's service worker keeps a file shared
  with the installed web app, and bridge's `batsNative` entry points
  are what the Android activity calls. They are asked for only once
  the stored library is read (#262): `_external_wait` in
  `src/bin/quire.bats` needs the proof `LIBRARY_READ`, which only
  `_library_read` makes, after `lib_load`, so a book is never added
  to the library the read then replaces; until then the bridge keeps
  the files in their order. When the library could not be read, each
  file is kept (`_handed_kept`, linear) and not added, and the banner
  says so (when Try again is offered, they wait for it: see "A library
  that cannot be read says why").

## The library is stored as records (#354)

The library is not one record any more. Each book is a record,
`library/book/<14 hex digits>` (its id as two 28-bit halves, 7 digits
each), and the collections another, `library/index`. They are read
together by their prefix (`libstore_read`, bridge's `idb_get_prefix`)
and saved one at a time, so a change to one book writes one book's bytes,
and a record damaged in one place costs that record's damaged part and
nothing else.

**The format** is `QREC`, a kind (book, index), the version of the
format that wrote it (1) and the least version that can read it (1, the
reader's `READER`), then chunks as PNG has them: a u32le length under
2 to the 20, a 4-byte tag, the data and a CRC-32 (IEEE, 0xEDB88320, the
check value of "123456789" is 0xCBF43926) as its low 16 bits and then
its high 16 bits, little endian, over the tag and the data; the last
chunk is `IEND`. A record is a set of groups, one chunk each, in
ascending tag order (a book's: `AUTH BOOK COLL ELSE FNSH ORDR PLCE SERI SHLF
SIZE TIME TITL`, the index's `LEGA NAMS`); each group is required (its
loss makes the record `Undecodable`) or optional (its loss gives its
defaults and `DecodedWithLoss`). A chunk of a tag this version does not
know is kept as it is, at the end, when its first letter is lower case
(ancillary, as in PNG), so a newer Quire's addition survives this one's
save; a capital one (critical), or a least version over `READER`, makes
the record `Newer`, and a first four bytes that are not `QREC` make it
`NotQuire`. What a record is decoded to is one of those five outcomes
(`recres`: `rr_ok`, `rr_loss`, `rr_notquire`, `rr_newer`, `rr_damaged`);
a decode never fails to say which.

**The codec is proven** (`src/bytes.bats`, `crc.bats`, `chunk.bats`,
`seq.bats`, `fields.bats`, `schema.bats`, `record.bats`; the book's and
the index's tables are in `scripts/record_tables.py` and
`bookrec.bats`, `indexrec.bats`, `bookimage.bats`, `indeximage.bats` are
generated from them by `scripts/gen-record.py` and `scripts/gen-image.py`,
so a field is added in one place). Byte strings are a datasort
(`bytes`) in the types, `blist(bs, n)` linear lists indexed by them, so a
proof can say what the bytes are. Reading is a relation between bytes
and its result (`DECODES(sp, kind, bs, res)`, built of `CK`, `SEQ`,
`FIN`, `SDEC`), writing another (`ENCODES(sp, kind, x, bs)`, built of
`CKENC`, `CHAINS`, `SENC`), and the laws are lemmas the compiler checks,
so a codec that is not the inverse of itself does not type-check:

* `decodes_encodes`: if the bytes decode to a record x, encoding x gives
  exactly those bytes (so a record is never altered by being read and
  saved: no padding is accepted, no unknown chunk is lost);
* `encodes_decodes`: what is encoded decodes to what was encoded;
* `decodes_functional`: bytes decode to one result;
* `record_read` is total: it answers every list of bytes with a result
  and its `DECODES` proof, and `record_write` returns the `ENCODES`
  proof of the bytes it made. The CRC's tables are `CRCP`, a relation
  checked by the same compiler, and the stored sum is compared with it
  before a chunk is `ok` (`CKD_ok` cannot be built from a sum that
  differs).

**The round trip is proved, from the value to the bytes and back.**

* A stored book is a `book_image(x)`, indexed by the book `x` it holds
  (`bookx_mk(author, id_high, ..., title)`): each number is an
  `int32v(n)` (its four bytes and the proof `LES` that they are the
  number `n`), each string a `bstr(bs)`, an array of array's `barr` whose
  cells are proved to hold the bytes `bs` (`HOLDS`, by induction on the
  list over array's own lemmas about `NTH` and `SETC`). `int32_make`
  gives the number `n = x` of an int `x`, or says it is not one of 32 bits.
* `book_record_new` makes a `bookrecord(x, 1, 1, ex_nil())` of an
  image, `book_record_image` an image of the very `x` of a record,
  `book_of_image` and `book_image_of` keep it; the lemma
  `book_roundtrip` (generated with the records: `index_roundtrip` too)
  proves that bytes written from `x` and read back as a book `y` make
  `x = y`, and `book_enc_dec` that they are read back as a book at all.
  `book_image_roundtrip` is the whole of it as a function: an image
  written as a record and read back from the bytes is an image of the
  same book, and the compiler accepts it only by those lemmas
  (`tests/static/reject/image-roundtrip-another-book`). Without the
  lemma it does not type-check.
* The bytes of a record reach an array through `blist_to_buffer`, which
  fills a `barr` whose cells it proves hold the list. What is outside the
  proof is only what is outside quire: bridge's atoms that write an array
  to IndexedDB and fill one from it (JS), the array package's memory
  primitives (`barr_get`, `barr_set`, ..., the one unsafe core), arith's C
  operators (`and_proved`, `or_proved`, and `xor_g1` from them) and the
  prelude's `/`. Each is tested where it lives (array's
  `tests/dynamic/content`, arith's `tests/dynamic/xor`). The copy of
  a library `Book`'s fields into an image and back (`_image_of_book`,
  `_book_of_image` in `src/library.bats`) is a copy of its numbers and
  strings by `book_image_make`, which refuses a number that is not 32 bits.
  `tests/codec` runs the whole on bytes and numbers at the edge (damage to
  every byte, every prefix, fuzz) as a check of those boundaries, not as the
  proof.

**The solver is 32-bit**: a constant or a coefficient of 2 to the 30 or
more in a hypothesis makes the context contradictory, and anything is
then proved. No proof here has one (integers are built from bytes,
`b + 256 * m`, and bounded by 2 to the 28); `tests/static/literals.py`
fails the checkers on a literal of 2 to the 29 or more in `src/`, apart
from a run-time value marked `(* wide *)`.

**The only way to change a record** is `libstore_save_book` and
`libstore_save_index` (`idb_update`, bridge: one transaction in which a
key is read, the closure decides from what it read, and the answer is
written back, kept as it was or deleted). The closure reads the stored
record, decodes it, puts the groups of the image that changed into it
(`book_record_patch`: the other groups, and the chunks it does not
know, stay as they were), writes it, and answers `BookSaved`,
`BookRefused` (undecodable: `Newer`, `NotQuire`, `Damaged`; nothing is
written) or `BookNotSaved`. A record that lost a group is repaired, and
its old bytes are kept in the same transaction under
`library/damaged/<id>/<crc>`. Nothing else writes `library/` keys
(`tests/static/keys.py` fails the checkers on a `"library/` key named
outside `src/libstore.bats`).

**What the library keeps in memory** (`src/library.bats`): the books and
collections, and a shadow of each record (`shadows`, `index_shadow`): the
image of what was last sent. `lib_save` makes the image of each book,
compares it with its shadow by group (`book_image_diff`) and sends the
groups that differ, none when it does not. A shadow is set when its
groups are sent, not when they are kept, so a change sent and changed
back before the first is kept is still sent; a save that is refused or
fails puts the shadow back (`_shadow_unsend`) and says so once. A book
whose record is no longer in the library has its record deleted; a stale
tab sends only its own groups, so two tabs changing different parts of a
book (a shelf, a collection) keep both changes (`e2e/library-records.spec.js`).

**The order and the view.** A book's record holds its place in the
library's order (`ORDR`, the `position` it had when last saved), and the
books are read back in it, so a book touched last is first again. The
view kept for a reload ("view") names its book by id (the key is only
the number the book was given as the library was read, and records are
read in id order): `lib_index_of_id`; a view kept before, of a key
alone, is found by the key.

**The old record** `"lib"` (QLB1 to QLB6) is converted once, by
`_convert_legacy`: when no record of the library is there, "lib" is read,
shown, and written as the records of its books and the collections'
(with the size and the byte sum of "lib", `LEGA`) in one transaction,
all or none (`batch_commit`, bridge's `idb_write_all`, the index in it
too); until it commits nothing is saved. "lib" itself is never changed or
deleted, so an older Quire still finds it; a "lib" that is not a QLB1 to
6 record is a library that could not be read.

## How far through the book: by the text's size, to the text's end (#426)

`_progress` (the library card and Book info) counted every spine item the
same, so a book of 3 long chapters and 10 short notes read 23% at the end
of its text, and a cover, a title page and a copyright page started a
book at 20%; the reader's footer and scrubber already weighed chapters by
size (`book_weights`). They are one rule now, written down here first, by
research:

* **By size, not by spine item.** Readium's positions are a resource's
  size in 1024-byte steps (the W3C EPUB working group's thread on page
  lists: Adobe since 2007, Readium-based apps since; some systems divide
  the zip entry's size, as `book_weights` does), and Kobo's percentage
  follows the book's words or size, not its pages (MobileRead users on
  the same book as an EPUB and a KEPUB, where 160 of 405 pages and 812 of
  2607 differ). Kindle's is a location, which is also size. Nothing
  comparable counts spine items, except for a fixed-layout book, where
  every spine item is one page of the same worth and the page indicator
  counts them: `book_weights` gives each chapter 1 when every chapter is a
  fixed page (`book_all_fixed`).
* **The text's end is 100%.** Kindle counts the back matter in the
  percentage, and its readers say what the Mudita forum's reader said
  (64% to 100% on the last page of the text) and keep a bookmark where the
  notes begin; Kindle's own "end of book" is the cure Quire takes. The
  EPUB 3 landmarks' `backmatter` entry (the same nav `toc_start_dest`
  reads `bodymatter` from, `PartEnd` in `src/toc.bats`) names the first
  chapter of the back matter; `toc_build` hands it to
  `book_text_end_set`, and from that chapter on `book_weights` gives
  nothing (before = total, own = 0), so the total is the text's, the
  back matter reads 100%, and the scrubber, the ticks and the time left
  follow. A book with no such landmark counts all of it. `epub:type` inside
  a chapter is not read: that is every chapter opened, for one that is
  not the book's. A `backmatter` landmark at the first chapter is no end.
* **The page's start, but the last page of the text is 100%.** The
  footer has always said where the page starts (a first page is 0%, a
  second "<1%"); the page that holds the text's last line says 100%
  (`_permille`), so the percentage is not 98% on a finished book. The book
  is finished (`done`) when the percentage is 100%, which for a book
  without back matter is the last page, as before, and for one with it is
  the end of the text (`_weighed_stored` >= 1001 in `_record_position`).
* **Stored once, carried with the place.** The library cannot weigh a
  book it has not opened, so the reader keeps the thousandth of the place
  (`progress_weighted`: the thousandth plus one, 0 when never worked out,
  decoded once into a `progress_basis`, `ByChapters | Weighed`, by
  `_progress`) beside the place whenever it saves it. A book not read
  since keeps the old count by chapters until it is. It is the record's
  `prog` group (lower case: ancillary, so a Quire without it keeps it and
  reads the record, as for any unknown chunk; every group before it is
  capital), the backup's and the sync file's `progressWeighted`, slot
  `SLOT_PROGRESS_WEIGHTED` taken whenever the place is (`_take_place`),
  and the 18th number of an orphan record ("QO1"). A file that does not
  have it gives 0, so a place restored or synced from an older Quire is
  counted by chapters until the book is read here.
* The size is the entry's size in the archive, as before: the e2e books
  store their chapters, so it is their bytes. A book whose chapters
  compress very unlike each other weighs them by compressed size; the
  uncompressed size is in the zip's directory and is not carried to the
  chapters yet.

`e2e/progress.spec.js` (books in `e2e/progress-books.js`, checked by
epubcheck) plays each of #426's cases, and backup and sync carrying the
number (`e2e/sync.spec.js`).

## Replace keeps what the reader made (#425)

A book's id is the SHA-256 of its file (`_file_id` in `src/import.bats`),
so the duplicate question (Skip / Replace) is asked only for a file that
is already in the library, byte for byte, and an archived book is put
back by importing it with no question. Replace (`import_mode` `Replace`)
changes the book's file (one `b<id>` entry), size, series and cover (when
the file has one) and nothing else: the place, collections, finished
mark, minutes, annotations and notes, order and id stay, and so does a
hidden book's shelf; only an archived book or one in the Trash comes back
to the Library, as the reader asked for it. `e2e/replace.spec.js` holds
the whole record of the library, the file's size and the card, before and
after, to be the same, and plays a backup, a second device and a second
tab over it. By research (the issue's comment): Apple Books and Kobo make
a corrected file a new book and the notes stay with the old one, which is
what users complain of; so a corrected file of a book in the library is
offered Replace too.

**A corrected file** has another id, so it is not the duplicate question's.
When the OPF of a new file is read (`_opf_done`), its title and author are
compared with the library's (`lib_find_similar`: case and the white space
around them ignored, a title that is empty never matches, a book in the
Trash is not one); a match asks "Newer file of a book?" (`QNewerFile`,
`_ask_newer`): **Replace** or **Add as new book** (also Escape: nothing is
lost either way). Nothing has been stored by then (`BookLooksLike`); after
the answer the OPF is read again as `Replace` (the file, cover and
accessibility data stored under the *book's* id, the id kept) or as
`AddAlone`.

**Chapters are found by name.** The hrefs of a book's chapters (`src/chapter_hrefs.bats`,
the chapters as `_spine_chapters` numbers them, an empty line for one that
names no file) are kept under the key `h<id>`, written when a book is
opened and by every replace. A replace reads the old record, makes a
`chapter_map` with the new file's hrefs (`MapByHref`; `MapByNumber` when
the old file's were not kept, a book not opened since: the same number
when the count is the same) and:

* the place (`_place_moved`): the chapter of its href, at the same page and
  anchor; else the chapter of the same number if there are as many, else
  the first, at its start; the progress weights are counted anew. Nothing
  changes when the hrefs are the same in the same order.
* each note (`annot_reanchor`, `_relocate`): its chapter's new number; one
  whose chapter is not in the new file is kept under `LOST_CHAPTER` + its old
  chapter, which is listed after every chapter under "Not found in this
  version" with its words and note, painted nowhere, leading nowhere,
  exported with that heading. A note's id contains its chapter, so a moved
  note has its old id deleted (a tombstone) and sync passes on a deletion
  and a new note. A note of a chapter that exists but has not the node it
  names is lost the same way when the chapter is shown
  (`annot_chapter_shown`, from the chapter's count of content nodes): the
  nodes of a chapter are known only when it is rendered, and a changed
  word is not noticed (a note is lost when its nodes are gone, not when
  its text changed).

By research for the annotation rule: Kobo keeps an annotation of a
restructured book in the list when it no longer shows in the text; Apple
Books and Kobo lose them when the corrected file is a new book. No
documentation was found of how Thorium or Moon+ match annotations of a
replaced file (searched), so nothing is taken from them.

**Another tab** (`src/file_version.bats`): bridge has no channel between tabs,
so a tab that has a book open asks, when it is shown again
(`visibilitychange`, the moment sync runs; web apps refetch stale data when
a tab regains focus, as TanStack Query does by default with
`refetchOnWindowFocus`), which
file the book is made from: the key `v<id>` holds the file's id when it is
not the book's own (a corrected file; deleted when the book's own file comes
back). If it is not the file the tab opened, the tab goes to the library and
the banner says "This book was replaced with another file in another tab"
with Reopen Quire (`BookReplacedElsewhere`). A tab in a second window
side by side is told when it is shown again, not at once. An identical file
changes nothing, so nothing is said. `e2e/replace-corrected.spec.js` plays
all of it with fixtures that pass epubcheck (`e2e/replace-books.js`).

## A library that cannot be read says why, and offers what fits (#374)

Bridge's IndexedDB read says why it failed: `Unreadable(cause)` carries a
`browser_reason`, the DOMException's name decoded once there
(`Transient` = UnknownError, `StorageBlocked` = SecurityError,
`NewerVersion` = VersionError, `Aborted` = AbortError, `NoErrorGiven`,
`BrowserUnexpected` with the name, a line feed and the message).
`src/unreadable.bats` turns that into a `failure_kind` (flat, copied
freely: `KindTransient`, `KindStorageBlocked`, `KindNewerVersion`,
`KindAborted`, `KindNoReasonGiven`, `KindBytesUnreadable`,
`KindUnexpected`), and the library's read keeps it: `library_content`
(`src/libstore.bats`) matches the lookup itself, where `lookup_content`
folds every cause into `ContentUnreadable`, and `library_read.ReadFailed`
carries a `failure_found` (the kind and, for an unexpected one, the
name and message as text, cut at 4096 bytes, never dropped). No other
read of storage changed: each still folds, as #174 says.

* **Hope is a proof.** `HOPE(failure)` is a dataprop with a constructor
  for `FTransient` alone (the sort `failure` and the witness
  `failure_is(f)` of each kind sit beside the flat `failure_kind`, which
  a cell can hold). The screen's `remedy` is `TryAgain(HOPE(f) | failure_is(f))`
  or `NoRemedy`, made only by `remedy_of`, a total `case+` over the
  kinds, and `ui_try_again_show` needs the `HOPE(f)`: Try again for any
  other kind does not type-check (`tests/static/reject/try-again-without-hope`;
  `accept/try-again-transient` shows the transient one does). `retry_hope`
  (`Hope | NoHope`) is read off `remedy_of`.
* **Aborted has no hope**, by research (the decision is also next to
  `HOPE`): the IndexedDB specification defines only UnknownError as
  transient; AbortError is "a request was aborted", raised when a
  transaction is aborted (by `abort()`, or after a failed request nothing
  handled), and Quire's read never aborts, so something else did and
  nothing says it will not again; Dexie's page on AbortError says only
  that it happens when the transaction was aborted and gives no advice
  to retry, and localForage reconnects and retries once, but on
  InvalidStateError and NotFoundError when a transaction cannot be
  created, not on AbortError.
* **What the screen says** (`library-empty`, `_unreadable_text` in
  `src/library.bats`; every text ends "Quire has not changed anything and
  will not save until it can read your library.", and none says "Import
  an EPUB", which is for an empty library): Transient, "Quire could not
  read your library this time." with Try again (`library-try-again`);
  StorageBlocked, the private window or site data blocked and to allow
  site data for this address, or leave the private window, then reopen
  Quire; NewerVersion, "This device holds data from a newer version of
  Quire. Update Quire."; Aborted, NoReasonGiven and BytesUnreadable, to
  reopen Quire to read it again; Unexpected, an unexpected error with the
  details in the banner. None but Transient has a button. Import is off
  while the library is unreadable (`inert` on `import-file`, and the
  button drawn disabled: muted text on the card, a cursor that says no,
  `#import-button:has(input[inert])` in the stylesheet, a `surf` pair
  proven in each theme; a file handed or dropped is refused with "Books
  cannot be added until Quire can read your library"). Records that can be read but not
  used are another case, below (set aside); a read that failed as a whole
  is not one, since nothing is known of what it holds and a new library
  made beside it could not be seen while the read keeps failing.
* **Records that cannot be used are set aside, not replaced** (the
  follow-up of #374). A library whose read worked can still hold a book's
  record, or the collections', that is damaged or not Quire's: it is shown
  nowhere and never written over, so the book cannot be imported again and
  no collection can be made. Settings shows a row then (`settings-aside`,
  `lib_aside_show`: "Set aside unreadable records",
  `settings-set-aside`), and only then. Pressing it
  (`lib_aside_run`, `lib_set_aside`) reads the library again and, for each
  such record, runs `libstore_set_aside_book` / `libstore_set_aside_index`:
  one `idb_update` transaction that reads the record, decides again with
  the codec (`_read_book`, `_read_index`; what was believed before does
  not decide) and, only for `UnusableDamaged` and `UnusableNotQuire`,
  writes the record's bytes to `library/damaged/<id>/<crc>` and deletes
  the record in the one batch (`_aside_writeback`), so an aborted
  transaction leaves the old record byte for byte
  (`e2e/library-records.spec.js`). A newer Quire's record
  (`UnusableNewer`) is never set aside: it is not damaged, an update of
  Quire reads it (`AsideNewer`). Nothing is lost, so it is not a `harm`
  and has no confirmation; the row then says to import those books again
  and restore a backup, which re-applies their places, shelves and notes.
  By research: Firefox renames a corrupt `places.sqlite` to
  `places.sqlite.corrupt` and starts a new one; Mozilla's application-services
  weighed moving the file aside against deleting it and chose deleting only
  because it acts on confirmed corruption; Roon and Miro tell the user to
  keep the old data folder or back the corrupt database up, then start
  fresh. Quire keeps the copy, as they do, and acts on one record at a time
  instead of the whole library, so what reads is never touched.

* **The banner.** A kind the screen says completely has no banner: the
  screen gives what happened, what Quire did, what to do and the
  browser's name for it ("Details: UnknownError."), which is what a
  report needs. Only an unexpected failure raises one
  (`notice_unexpected`: the name and message as the answer, Copy details,
  Report), since it carries what the screen cannot and its screen has no
  button for it to cover. A banner shown first at the foot of the library
  covered Try again on a short phone (CI, mobile-portrait), and one at
  the top covered the header; over the library the banner is now part of
  the page, above the header, and pushes it down (Material 3: a banner
  sits under the top app bar and moves the content; position relative
  with the base rule's centring), so it is over nothing. `coveredByBanner`
  (`e2e/controls-shown.js`, run by `fits`) reports the header's controls,
  `library-empty` and `library-try-again` under the banner, and Try again
  under anything at its centre, whether a banner is up or not; the layout
  spec runs it on an unreadable library of each sort in every project. A
  banner wraps its buttons under its message on a narrow window instead
  of squeezing Report. Over the reader it is fixed at the top while the
  reader's bars are away, and under the top bar while they are up
  (`#bats-root:has(.rv:not(.chrome-off)) .banner`: the bar's safe inset,
  44px control and 2px, and 8px), as material.io's, Flutter's and
  Zeta's banners sit under the app bar and none draws over it;
  `e2e/storage.spec.js` raises one over the reader with its bars up and
  runs `coveredByBanner` on both bars. The details of an unexpected
  failure outlive its banner: they are kept in memory (`_details` in
  `src/notice.bats`, replaced by the next such failure, never stored)
  and About shows "Copy last error details" (`about-error-copy`, an
  `about_control` of the screen's one listener, since the table of
  listeners is full) once one is kept, as Firefox keeps its
  troubleshooting information on about:support with a Copy text to
  clipboard button. Start-up with a library that could not be read yet
  does not write over the stored view (`_library_shown(false)`): the
  retry opens the book it names, as the sync that waits for the retry
  runs then (`e2e/storage.spec.js`).
* **One honest retry.** Try again repeats the read start-up makes
  (`lib_load`) through `_library_read`, so the `LIBRARY_READ` proof is
  still only made there. `lib_retry_begin` spends the retry when it
  starts, so a second press does nothing and a failure leaves the screen
  with no button for the rest of the session (it says it tried again).
  When the first read fails for a reason with hope, the start-up steps
  that wait for the read (`_after_read`: files handed to the app, sync, the
  stored search and view) are held and run once when the retry ends,
  whichever way (the bridge keeps the files in their order meanwhile); for
  a reason without hope they run at once, as before (the files are kept,
  not added). The flag that stops every save of the library
  (`storage_savable`) is cleared only by `storage_read_again`, given
  `AttemptRead` by a read that worked (`Readable`); `AttemptFailed`
  leaves it (`StillUnread`). A read made again starts from nothing
  failed (`_read_outcome`), the kind it failed with is `_read_kind`, and
  `library_view` is `ViewBooks | ViewEmpty | ViewUnreadable(failure_kind)`
  (fixture `library-view-unmatched`).
* `e2e/storage.spec.js` stubs the library's read to throw a DOMException
  of each name (`failLibrary`), once or always: each kind's text and
  button, an unlisted name's details, Try again showing the books and a
  later import being kept, and a retry that fails.

## What allocates is linear

wasm has no garbage collector, so outside `$UNSAFE` nothing that
allocates is non-linear (bats-lang/bats#224): a type whose constructor
carries data is a `datavtype`, consumed by a `case+ ~` match (a list
has a `_free` walk); a closure is a `lincloptr1`, made with `llam`.

Quire never frees a closure itself (`cloptr_free` needs `$UNSAFE`):
each one is handed to a library that runs it once and frees it, a
promise (`$P.finish`, `$P.and_then`) or the bridge (a listener of the
`regs` table, `ui_listen_all`). What waits for a later answer keeps a
promise's resolver, not a closure: the Undo offer (`undo_offer`
returns the promise of how it `settled`: `Undone` or `Final`), the
dialog (`modal_open` and `modal_confirm` return the promise of its
`reply`: `Accepted` or `Declined`), a sync's round (`_rounds` in
`src/sync.bats`). The caller hands its continuation to that promise,
and the cell resolves it exactly once, so what would not have run
before (an undo made final, a dialog's other button) still runs,
told so by the value, and is freed. A function that called a closure
for each item takes data that says what to do instead (`lib_nums_set`,
`counted` in `src/annot.bats`, `regroup` in `src/library.bats`).

A promise's payload type implements `$P.dispose`, before its first use
in each module that makes a promise of it (`$P.create`, `$P.ret`,
`$P.resolved`): `bats check` does not catch a missing one, only the C
compile of `bats build` does.

## A choice is a datatype

An int never encodes one of a fixed set of cases (bats-lang/quire#192):
a choice is a datatype matched with `case+`, so a case left out does
not type-check ("pattern match is nonexhaustive"), and "none" is an
option, not -1. Ints are quantities, offsets and indexes. Stored bytes
stay as they are, decoded once as they are read and encoded once as
they are written: a book's `shelf` (`shelf_of_code`, `shelf_code`) and
cover (`image_of_code`, `image_code`), and the library view's
`sort_order`, `layout` and `book_filter` (`lib_state_set`,
`lib_state_get`, which packs them only to be saved with the settings),
and each setting of the "S2" record and the backup (`font`, `alignment`,
`hyphenation`, `image_dimming`, `tap_zones`, `volume_keys`, `readout`,
`page_flow`, `column_count`, `ruby_display`, each with its `_code` and
`_of_code`). The theme chosen is a `theme_choice`, `Auto` or
`Fixed(theme)`, kept apart from the settings record since it is linear;
a `theme` (style's `palette_theme(n)`) is indexed by its number in the
palette, `theme_palette` the one function that gives it, and the theme
rules are written from it (their selectors too), so a theme's colours
and its proofs cannot be another's.
How a sync ended is a `sync_result`, stored as its code in
"sync-state" (`_result_code`, `_result_of_code`); the store's kind a
`store_kind` (`WebDavKind`, `AndroidKind`, `BackupKind`, `DropboxKind`,
`NoStoreKind`);
and an HTTP status is read once into an `http_answer`.
An annotation's kind (`Bookmark`, or a highlight in its
`highlight_style`) is stored as its code in the "QA" record
(`_kind_code`, `_kind_of_code`), the record's version is a
`record_version`, a highlight's mark set a `mark_set`, and the list's
filter a `style_filter`. A kind is one flat datatype, not `Highlight of
highlight_style`: a constructor that carries data would make it linear,
and an annotation's numbers are copied freely.
Opening an archive is done in an `import_mode` (`Reopen`, `AddNew`,
`Replace`) and ends in an `archive_outcome`; an import's promise
resolves with an `import_outcome` (`Added(key)`, `Kept`, `Failed`), the
duplicate question with a `duplicate_answer`, and a chapter's load with
a `load_outcome` (`ChapterShown` or why not, `load_shown`).
A link found on the page is a `link_found` (`NoLink`, `InBook`,
`OutOfBook`); a spine's direction a `spine_progression`; a book's
accessibility metadata an `a11y_feature` each (its bit in the stored
flags made by `a11y_bit` alone, asked by `a11y_has`) and a
`wcag_level`; an OPDS list of links a `link_list`; the catalogue's
fields `entry_field` and `page_field`, and a refused fetch a `refusal`.
A click's target is decoded once, in `src/ui.bats`, into its listener's
own control datatype (`typography_control`, `selection_control`, ...),
each control's id given by its `*_control_id` (which
`tests/static/ids.py` reads: each must be made, none twice), and each
listener matches it with `case+`; a key event is decoded once into a
`key` and its `modifiers` (`ui_key`, `ui_modifiers`).
A dictionary's form (`dict_form`, a record: a .dict.dz, a .syn) is
its byte in "dicts" (`_form_code`, `_form_of_code`); a file to import is
a `dictionary_file`; a lookup finds a `word_match` (`Exact`,
`CaseFolded`, `NotFound`) by stardict's `word_order` (`Before`, `Same`,
`After`); an article's part is a `part_kind`.
`tests/static/case_plus.py` fails on any plain `case` (ATS2 checks only
`case+`), in CI through `tests/static/run.sh`.

## Backup: Export says it saved, Restore says what it did and can be undone (#362)

A restore overwrites, from the file, the settings (the device's own too:
brightness, rotation lock, full screen, voices, sort order), the books it
has in the library (shelf, place when the file's is later, collections,
finished, minutes), the notes of each book it names (the book's stored
array is replaced, deletions dropped), the reading log's missing days,
and the collections it names (made when missing); a book the library
does not have keeps its record as an orphan ("o"). Nothing went to the
Trash, so the Undo rule was not met: nothing was offered back.

Now what is in the library is kept first, as a backup file in memory
(`backup_snapshot`, linear: the same file Export makes, made by the same
code into an `export_sink`, `IntoReader` or `IntoSnapshot`), then the
file is restored, `_restored(restore_report)` says it (books, notes,
settings, days, and the books the backup knows that this library lacks:
`_restored(1)` does not type-check, `tests/static/reject/restored-bare-count`),
and `undo_offer(BackupRestored())` is made; its `Undone` puts the snapshot
back (`PutBack`: shelf, place and Trash exactly as they were, the reading
log replaced, not merged), its `Final` frees it, so a snapshot unconsumed
is a type error (`snapshot-not-handed-on`). A restore whose snapshot
cannot be made (memory, a book's notes unreadable) is not made; a file
found damaged midway is put back at once. Left behind by an Undo: a
collection the restore made stays, empty, and orphan records a restore
kept for books not in the library stay until they are imported.

Export says how it ended (`export_outcome`, matched with `case+`:
`tests/static/reject/export-unmatched`): in a browser the file is
downloaded and the dialog says it is in the downloads; in the app a
blob download does nothing in the WebView, so the file goes to Android's
share sheet (bridge's `share_file`) and the dialog says it was shared,
a closed sheet or a failure is said too. Settings says under Backup,
browser and app alike, what a backup holds and that the books' files are
not in it.

## Every error says what to do (#360)

The error banner (`error-banner`, `src/notice.bats`) says a failure and
a next step, made in one place from data: `notice_say(failure)` for a
fault (`SettingsNotRead`, `BookFileLost`, `StorageFull`,
`RotationNotLockable`, ...; `notice_say_part(chapter)` for a chapter
that could not be read, which it names), and `notice_say_named(name,
name_len, named_failure)` for a file or book that has a name
(`NotAnEpub`, `PackageDamaged`, `FileEmpty`, `BookFileNotStored`, ...).
The words come from two total `case+` matches, `_what_put` (what
happened, per `host`: `InBrowser | InApp`, so the app never says
"browser") and `remedy_of` / `named_remedy_of` (the next step, a
`remedy`: `ReopenQuire`, `ImportAgain`, `OtherChapterOrReplace`,
`ChooseAnotherFile`, `UpdateQuire`, `FreeSpace`, `OpenAgain`,
`RemoveGrantByHand`, `UseDeviceRotation`, `CopyByHand`, `RestoreBackup`,
`TryNextPhrase`), so a failure added without words or without a next
step does not type-check (`tests/static/reject/notice-without-remedy`).
Where reopening is the step, the banner has a Reopen Quire button
(`error-reopen`, a reload). A step is words, not a Try again button: no
failure has data to retry from, and a retry would be a closure (linear).
A chapter's failure does not say "import the book again" alone: that
meets the duplicate dialog, so it also says to choose Replace.
`notice_error` is private; `tests/static/notice.py` (in
`tests/static/run.sh`) rejects `notice_error(` outside `notice.bats` and
a wildcard in a match of `ArchiveFailed(_)` (`tests/static/notice/reject`).
Import's causes are matched one by one (`_archive_named`); only a book
that declares its protection is blamed on DRM (below), never a damaged one. A sync's result texts, made by
`sync.bats` from its `sync_result`, go through `notice_sync_said`.
`expectBannerSaysWhatToDo` (`e2e/helpers.js`) checks a banner has a
Reopen Quire button or words naming the step, and in the android project
no "browser".

## A book that declares its protection is refused, named (#427)

A file that *declares* its encryption is not a guess, so it is refused at
import, before its container.xml is read (`_protection_check` in
`src/import.bats`, only for an import, since a stored book was checked
then), with the scheme named and not added to the library. What it looks
for, in this order: `META-INF/license.lcpl` (Readium LCP,
`ProtectedByLcp`), `META-INF/sinf.xml` (Apple FairPlay,
`ProtectedByFairPlay`), `META-INF/rights.xml` (Adobe ADEPT,
`ProtectedByAdept`); then `META-INF/encryption.xml` read by
`encryption_of` (`src/epub_xml.bats`): `ns.adobe.com/adept` (ADEPT),
`readium.org/2014/01/lcp` (LCP), `kobo.com` or `kobobooks.com` (Kobo,
`ProtectedByKobo`), else any `EncryptionMethod` whose `Algorithm` is
neither font obfuscation (IDPF's `http://www.idpf.org/2008/embedding`,
Adobe's `http://ns.adobe.com/pdf/enc#RC`: undone by a reading system,
no DRM, and not refused) is `ProtectedUnknown`. Each is a
`named_failure` and an `archive_failure` (`DrmAdept`, ...), matched with
`case+`, so a scheme added without words does not type-check. A damaged
book that declares nothing, or whose encryption.xml cannot be read, stays
"damaged": DRM is never guessed from damage.

By research (Thorium, Calibre, Readium's docs): Thorium, which has an LCP
client, only says what is missing ("This publication needs an LCP
passphrase", and, for an encrypted publication with no licence,
"Publication is encrypted but lacks an LCP license!"); Calibre, which has
none for the schemes it cannot open, says the book is locked by DRM and
points the reader to its manual's DRM page, offering no way round it.
Quire has no client for any scheme, so its words name the scheme (as
Thorium names LCP), say it cannot open it and that the book was not
imported, and give the next step, which is to read it in the app it came
from or get a copy without DRM (`ReadWhereItCameFrom`); it points to no
way of removing DRM. A build that one day has a client for a scheme
changes only that scheme's case. Kobo's check is a guess at its
namespace (the issue names `http://www.kobo.com/...`; no Kobo book was
available to look at), written in one place. The books the tests use are
made by `e2e/drm-books.js` (chapter bytes replaced by random ones, the
encryption.xml and licence files written), registered in
`e2e/epubcheck.spec.js`, and played by `e2e/drm.spec.js`.

An OPDS entry whose acquisition link has type
`application/vnd.adobe.adept+xml` or
`application/vnd.readium.lcp.license.v1.0+json` is an `acquiring`
(`AdeptAcquisition`, `LcpAcquisition`, in `src/opds.bats`, kept over the
entry's other acquisitions): with no EPUB link of the entry's own, the
row says "Protected by Adobe DRM: Quire cannot open it, so it cannot be
got here" (or Readium LCP) in place of Get and the licence is never
fetched; an entry that also has an EPUB is got as ever
(`e2e/drm-catalogue.spec.js`).

## Every outcome is said, and the unexpected as such

After #334, where a Google error that ended the consent screen reached
quire as the reader backing out, and was said only on a line of the
Sync screen:

* The plugin and bridge report every error and unexpected condition as
  an outcome of its own, never folded into another. What they do not
  recognise is an explicit `...Unexpected` constructor, carrying which
  case it was as a datatype (bridge's `google_unexpected`) and the
  answer as bridge's JS wrote it.
* quire matches every answer with `case+` and handles every
  constructor visibly: google_authorize's `AuthorizeRefused` by each
  `google_status` (`_refusal_result` in `src/sync.bats`), a cancel the
  reader made noted on the Sync screen, every other end of a sign-in
  or sync the reader started said in the error banner (`_reader_told`).
* An `...Unexpected` outcome goes through `notice_unexpected`
  (`src/notice.bats`): the error banner says an unexpected error
  occurred while doing what it was doing, with Copy details (Quire's
  version, the platform, what was being done, the call, the case, and
  the answer as the atom kept it, an access token's value written as
  its length) and a Report link to Quire's GitHub issues. A refusal
  with a code is said the same way (`notice_failure`), the code in its
  text ("Details: DEVELOPER_ERROR (10)").
* An e2e test passes through every constructor of every answer quire
  handles (`e2e/sync-android-outcomes.spec.js` for google_authorize);
  an answer bridge's JS never gives is passed through by bridge's own
  dynamic test.
* A call that never answers is an outcome too (#340): no call to Google
  is left pending with nothing shown. A call that shows nothing
  (`authorizationForScopes`, `clearAuthorizationToken`, `revokeAccess`)
  is ended after 30 s (`GOOGLE_ANSWER_MS`: Play services documents no
  timeout, so it is chosen from what comparable software does: OkHttp
  ends a request at 10 s each for connect, read and write; Firebase
  Auth's own 3 minutes is the length developers call too long, and
  Flutter developers who bound a hanging `signIn()` themselves use
  about 30 s; Google's Tasks guide says to bound a wait and gives no
  value, only a 500 ms example; and Nielsen's 10 s is the limit of a
  reader's attention, a sync saying "Syncing..." meanwhile) as `GoogleNoAnswer`: "Google didn't
  answer. Check the connection, then try again." (a revoke's, in the
  banner, with where to take the grant back by hand). The consent screen
  (`authorizeScopes`) is the reader's to take as long as they like, so
  no timer ends it: while it is awaited (`GoogleAsking`) the status card
  says "Waiting for Google's consent screen. Finish it there, or stop
  waiting." and shows Stop waiting (`sync-stop`, `sync_stop`) in place
  of Sync now and Turn off; it ends the ask as the reader's cancel, as
  backing out of Google's screen does, and a second ask meanwhile is
  said as the consent screen already open. Each such call is the
  promise of a resolver kept in a cell with the call's number
  (`answer_wait`, `consent_wait` in `src/sync.bats`): the plugin's
  answer and the timer or Stop waiting each settle that number, the
  first resolves it, and what comes after (the answer of a call already
  ended) is dropped, so it changes nothing, keeps no token and asks
  Google nothing more (`_authorization_late`: a late answer that logged
  the reader in after they were told Google did not answer is what
  Flutter developers who time out Firebase's sign-in found).
  `e2e/sync-android-hang.spec.js` leaves each call pending (`hold` in
  `e2e/sync-stores.js`) and settles it late.

## What the types guarantee about the interface

The stylesheet is built in `src/style.bats`, not written as CSS:

* A text colour and its background are only ever set together
  (`surf`), with a proof (`SURF`) that the pair reaches 4.5:1 in each
  of the five themes. The proof is css's `CONTRAST` over the palette
  (`PAL(t, r, c)`, its theme a `palette` and its role a `colour_role`,
  both datasorts, so a role is passed as a `role_value(r)`, never a
  number): a table of every sRGB channel's linear light (`LIN`, made by
  css's `scripts/gen-contrast.py`) bounds each colour's luminance, so
  a pair that falls short does not type-check. Control edges and
  accents need 3:1 (`EDGEP`). A field's placeholder is text like
  any other (quire#357): `input::placeholder` is written through `surf`
  as muted on the field's card (`S_muted_card`, proven in each theme)
  and drawn at full opacity, so a placeholder is under the proof too;
  `textContrastShort` in `e2e/controls-shown.js` measures it in the light
  and dark themes (`e2e/layout.spec.js`).
  A chosen tab is told apart by more than a tint (quire#358, WCAG
  1.4.11; Material 3: an underline on the active tab): `.tab
  [aria-selected=true]` keeps the card and draws `underline`, a 3px inset
  line in the accent whose `EDGEP(accent, card)` is proven 3:1 in each
  theme; `stateCueShort` in `e2e/controls-shown.js` fails a tab list whose
  chosen tab has no cue the others lack. Grounds without text (`fill`, `tint`)
  set their font size to 0, and a dialog's veil makes its own text
  transparent.
* Each theme is written (`theme`) only with a proof (`HARMONY`) that
  it follows css's harmony rules (`harmony.bats`, which gives each
  rule's source): its hues in at most three families of 30 degrees;
  its surfaces, bars, edges and text neutrals of the first; danger and
  the error banner red, highlights yellow; accent and danger as
  saturated; a card lighter than the page; body text at 7:1; and, in a
  dark theme, a ground that is not black, text that is not pure white,
  and calm accent, danger and edges. No text/ground pair vibrates: one
  of them is calm (`SURF`). `scripts/gen-harmony.py` writes the proofs
  from `PAL`; the solver checks them, so a palette that breaks a rule
  does not type-check.
* Spacing comes from one scale (#331): `space(n)`, Material's grid as
  a datatype indexed by its length (4, 8, 12, 16 and 24 px), written
  by `spaced` and `spaced_pair` into the paddings, margins and gaps of
  the screens, sheets, menus and dialogs. `SPACE_INSET` (8 px,
  Material's least gap between targets) is the least a control keeps
  from its container's edges; the page gives it as `--space-inset`,
  and the layout walk (`insetsShort` in `e2e/controls-shown.js`, run
  by `fits` on every screen it walks) fails any control nearer its
  container's padding box than that. A full screen's rows and notes
  are cards inset 8 / 16 px (`_spacing`), a panel opened as a dialog
  16 px, a dialog 24 px. #332 is to prove the insets statically.
* The page's width and height are a whole number of pixels (`page_extent`,
  indexed by whether it is whole; `page_width_rule` and `page_height_rule`
  (`src/page_size.bats`, a module of its own so its fixtures check in a
  minute, where a snippet in `style.bats` costs 7 to 18) give the `.caf`
  rule's `max-width` and `max-height` from a `page_extent(1)` only,
  so an extent that is a fraction does not type-check:
  `tests/static/reject/page-width-fraction`, `page-height-fraction`). The reader
  scrolls to page n by n times the width (the height, down) it is told and
  counts pages by the scroll width over it, and both are whole numbers (bridge's measure
  and `scrollWidth` round). A Pixel 9's window is 1080 device pixels at
  2.625 a CSS pixel, 411.43 wide and 923.43 high; the page was as large as
  that, the
  offsets 0.43 px out more with each page, and a chapter of 19 pages or
  more was counted a page too many, whose scroll clamped to nearly the
  page before it: the last page of every chapter, doubled, and each page
  before it begun in the previous page's last letters. The rule rounds
  the container's width down (CSS `round()`, Chrome 125; a WebView
  without it drops the declaration and is as before). What the proof does
  not reach is the browser (that columns are as wide as the page and that
  `round()` rounds): `e2e/fractional-window.spec.js` plays a window 411.43
  wide or 923.43 high and walks two chapters page by page across, right to
  left, as a spread, down (a vertical book) and scrolled.
* A setting with two states is a switch (`_switch_row`: Justify text,
  Hyphenation, Dim images, Turn pages with volume keys, Full screen,
  Lock rotation), never a segmented On | Off nor a lone pressed button
  (quire#363, Material 3: a switch makes a binary selection and takes
  effect at once); a segmented group is for three or more choices, or
  two that are not on and off (Pages | Scroll). `onOffPairs` in
  `e2e/controls-shown.js` fails a screen that has one, in `fits`.
* A sign-in field is named by a visible label (quire#361, WCAG 3.3.2 and
  1.3.1): `ui_form_field` (`FormUrl`, `FormUser`, `FormPassword`,
  `FormName`) makes a `<label for>` above the input and shows only an
  example as the placeholder, so the name does not vanish as the field is
  typed in; `ui_field` has no such kinds, so a password field made
  without a label does not type-check (`tests/static/reject/
  form-field-as-field`). A sync service's step button is `Sign in to
  <service>` for every service (`sign_in_label`, the title being
  `service_title`), and a row that opens a screen ends in a chevron
  drawn by the stylesheet (`.chev::after`, with an empty alternative text),
  never a character of its words: `tests/static/glyphs.py` rejects U+203A in
  `ui_text_btn`. `labelsShown` and `labelInName` in
  `e2e/controls-shown.js` check both on every screen the layout walks.
* The base rules are the only `!important` ones: every control is at
  least 48px square (quire#403: Material 3 and Android's accessibility
  guidance say 48dp, Apple's HIG 44pt, WCAG 2.5.5 44px, which 48 also
  meets; the app is released on Android; `targetsShort` in
  `e2e/controls-shown.js` measures it on every screen the layout walks), text fields use a 16px font (so iOS does not zoom
  in), and focus shows a 2px ring in the text's own colour.
* The sheet's size is in its type (`sheet(r, media, open)`: r bytes
  left, and whether an @media block and a rule are open), so it always
  fits the 64 KiB text it is put in, and a rule is opened only outside
  another and closed only once.

Elements are made through `src/ui.bats`:

* Plain elements come from a tag type with no interactive tags; a
  button, a field or an image can only be made by a constructor that
  names it. A text button is named by its text alone, so its name
  holds what it shows (WCAG 2.5.3); an icon button is given its name;
  an icon is a glyph of one monochrome set, a subset of Material
  Symbols (Apache-2.0, `assets/fonts/material-symbols-subset.woff2`,
  made by `scripts/icon-font.py`) at its Private Use Area code point
  (`_glyph`, `ui_icon_set`), drawn in the button's own proven text
  colour, never an emoji (#274);
  images are decorative (`alt=""`); an audio element (`ui_audio`) has no
  controls and is hidden from assistive technology; a role that needs a name (dialog,
  region, toolbar, menu, group) is given one with it.
* Each element id is made at one place in the code, no numbered id
  (`nid_make`, a prefix and a number) can spell another, and every id
  the code names is one it makes: `tests/static/ids.py` checks the
  source (the constructors, `ui_harm_id`, the controls' `*_control_id`,
  and helpers that pass an id on), in CI through `tests/static/run.sh`. An element made again to
  reset it (a search field, a file input) is made by one function,
  called at startup and at the reset.
* `ui_attr` takes a typed attribute that cannot be a name, a role or a
  style. The inline styles are a place (`ui_place`: left or width,
  in tenths of a percent up to 100%) and a fixed page's box
  (`ui_fixed_box_n`: width and height, 1 to 10000 px, and a zoom of 1
  to 10000 thousandths, so a zoom of 0 does not type-check), each
  written from numbers alone, so no inline style can set a colour or
  anything else the stylesheet proves.

Nothing is lost at a click, except by emptying the Trash. That is the
one irreversible action because it is the one with no visible effect: it
only gives storage back, so nothing a reader needs to do ever requires
it. Every other action changes what the reader sees, and is offered back
(Undo), keeps what it replaces, or can be done again (reauthorizing
sync brings back what turning it off took, with the security boundary
the revocation is for); an action with a visible effect is never a
`harm`. Removing a dictionary does not follow this yet: its files are
deleted when the Undo offer is made final (#396 moves them to the Trash).

* Removing a book moves it to the Trash (the shelf `Trash`), where it can only be
  restored; archiving, hiding, deleting a highlight or bookmark and
  resetting the settings are done at once. Each is offered back by the
  Undo toast (`undo_offer` in `src/undo.bats`), whose undo runs only
  from its own button, whose listener the module registers
  (`undo_listen`). An offer stays until it is used, dismissed (the
  toast's Dismiss) or another takes its place, which makes the earlier
  one final (quire#364: Material 3's snackbar with an action, WCAG
  2.2.1): `undo_offer` takes an `offered(UntilDismissed)`, a datatype
  indexed by its `offer_life`, so an offer with a `Brief` life does not
  type-check (`tests/static/reject/undo-offer-brief`), and each
  constructor says what an Undo would undo.
* A factory reset moves every book to the Trash and resets the
  settings (`lib_trash_all`, `set_reset_undoable`), with one Undo that
  puts back each book's shelf and the settings.
* Emptying the Trash is the one irreversible action, and the one
  question with a red button: the dialog (`src/modal.bats`) asks a
  `harm` (`src/ui.bats`), which has only `HEmptyTrash`. It closes any
  Undo offer first, since what that would put back is gone.
* Red is the stylesheet's rule for `[data-harm=y]`, which only
  `src/ui.bats` sets, and only from a harm: on the harm's menu item
  (`ui_harm_item`, whose id and label are the harm's) and on a button
  whose tone is `Danger(h)` (the dialog's, for `Harmful(h)`). A click
  on a harm's item is dispatched by the harm its id belongs to
  (`_harm_clicked` in `src/bin/quire.bats`) to `lib_ask_harm`, which
  asks that same harm, so a red item always asks about what it names.

What deletes is private to the module that owns it: deleting a book
and emptying the Trash (`src/library.bats`), and dropping an
annotation (`src/annot.bats`) have no `#pub`. Emptying runs only in
`lib_ask_harm`, when the promise of the dialog's answer
(`modal_confirm`) resolves `Accepted`, and only the dialog's second
button's click resolves it so: the dialog registers that listener
itself (`modal_listen`) and its answer function is not exported, so
other code can dismiss a dialog (`modal_dismiss`, which answers
`Declined`) but never confirm one. A destructive question's title, text, button verb
and red marking all come from one `harm` value.

No promise's value is dropped unread (`$P.discard` is not used): a
chain ends with `$P.finish`, and a value it ignores is written out as
`llam(_) => ()`, with a comment saying why losing it is harmless (a
cover, a hint, a delete nothing reads again). What fails is said
(`src/notice.bats`): the error banner (`error-banner`, `RAlert`) is a
child of `bats-root`, so it shows over the library and the reader
alike. A write of the reader's own data (the library, annotations,
settings, statistics, catalogues, dictionaries, sync's store) ends in
`save_checked`, which says once a session that storage may be full; a
book whose own file was not stored is named (`_book_store_checked` in
`src/import.bats`). A chapter that cannot be shown leaves the reader on
the page it was on (`_jump_checked` in `src/reader.bats`), or, as a book
opens, back in the library; either way the banner says why. A copy is
confirmed by the copy status (`copy-status`, `RStatus`), apart from the
Undo toast.

A read of storage that failed is never taken for an empty one (#174):
`lookup_bytes` and `lookup_content` (`src/book.bats`) answer
`StoredUnreadable` / `ContentUnreadable` apart from nothing stored, so
every load must say what it does then. A record each save rewrites
whole (settings, statistics, reading speed, catalogues, dictionaries,
sync's state, a book's annotations) that could not be read is not
saved this session (`src/storage.bats`: its save checks
`storage_savable`), and an unread book's annotations cannot be made;
the banner says so. The library is read as its records are (below): one
that could not be read at all is not saved this session and books are not
added to it, and the screen says why and offers what fits (#374, below); a book's record that is damaged, newer or not Quire's is
shown nowhere, said once and never written over. A backup that could not
read a book's notes is not made.

The overlays (the menus, book info, the reader's panels and the full
screens: Settings, Sync, a sync service's step) are a `layer` (`src/layer.bats`), whose
element ids only that module knows: they are shown and hidden only by
`layer_open` and `layer_close`, which keep the stack of open overlays,
last opened on top. Escape answers the dialog if one is open, and
otherwise closes the top of that stack (`layer_escape`), whatever
opened it: from Sync, Escape goes back to Settings, and another closes
Settings.

Back, Android's and the browser's, is one model (#333, `_go_back` in
`src/bin/quire.bats`): the dialog is answered No, else the top of the
stack closes as Escape closes it (Sync to Settings, Settings to what
was under it), else the in-book search's results end, else the book
goes back to the library; at the library with nothing open it is the
platform's. In the Android app the App plugin's `backButton` reaches
it (bridge's `listen_back_button`, `RBackButton`), and at the root the
app goes to the background (`app_minimize`, `minimizeApp`: what Android
12+ does itself at a root activity; `exitApp` would finish it). In a
browser `src/back.bats` pushes one history entry (the guard, at the
page's own address) above the page's own once there is anything to go
back from (a dialog, an overlay, the reader: `back_dialog_set`,
`back_overlays_set`, `back_view_set`), so Back takes it (`popstate`,
`back_popped`) and the app goes one step back, pushing it again if
something is still open. The app never takes a guard back on its own
(`history.back()` is asynchronous, and raced pushes and reloads): one
left after something closed another way is taken by the next Back, and
with nothing to go back from that Back is the platform's, so the app
goes on back past its own entry (`back_leave`, bridge's
`history_back`) and the page is left at once. The page restores its own
scroll (`history_scroll_restoration`, `ScrollManual`), so going back
over a guard never moves the library. `e2e/back.spec.js`
walks every screen of the layout's walk (`e2e/walk.js`, which
`e2e/layout.spec.js` walks too, so a screen added there is covered) and
checks Back goes exactly one step from each, in a browser and in the
android project, and leaves at the root.

The Settings screen (`LSettings`, `settings-screen`, made by `app.bats`
and wired by `_wire_settings_screen` in `src/bin/quire.bats`) follows
Android's settings pattern: one screen of groups, each complex area a
screen of its own opened from a row that shows its state. It opens
from the library menu's Settings only: in a book, the reading settings
sheet is the one settings place (#342). It holds Sync ›, Dictionaries ›, the backup
(Export backup, and Restore backup: the input `backup-file`), the daily
reading goal (also in the statistics panel; `stats_goal_show` marks
both), Reset settings and Factory reset, each with its Undo, and
About Quire › (`LAbout`, `about-screen`): the app's name and links out
of the app (`ui_link_out_https`, an address dom's `set_url_literal`
sets) to the home page, privacy policy and terms (no link to the
source: nothing in the app or its pages points to the repository but
the GitHub issues the pages give for contact).

The home page, privacy policy and terms are plain static HTML in
`homepage/` (#216), published by `deploy.yml` beside the app at
`https://bats-lang.github.io/quire/homepage/` (`privacy.html`,
`terms.html`). They are not the app's: gen-pwa does not read them, the
Android project does not hold them, and the service worker (bridge's
`produce_service_worker`) answers only files directly in its scope, so
it neither answers nor keeps them (`e2e/about.spec.js`). The privacy
policy states what the code does: change it with any change to what is
stored, what leaves the device, or the Google scopes asked for.

The library bar's More options (Material's overflow, ⋮, #333: a gear
would say it goes straight to Settings) opens the library menu:
Settings, About Quire (the same About screen, so the library reaches
it without Settings), Catalogues, Reading statistics, Hidden, Archived
and Trash (each a screen of its own, below), Install Quire (while the
browser offers it), Empty Trash (the red harm item) and Close.

## The library screen (#375, #376, #377, #404)

One redesign of the library's header and empty state, decided by
research (what comparable library apps do) and written here:

* **The bar is one row** (`library-bar`): the name, Import (`import-button`,
  a plus; its file input, named Import EPUB, lies over it, since a page
  cannot open the picker itself), Sort and view (`sort-menu-button`) and
  More options, with the search field on a row under them. Material 3's
  top app bar is a title and up to three trailing actions, the rest in an
  overflow menu; Apple Books has its view and sort control in the top
  right of the library, Play Books its sort in a menu. At 320 px the
  bar used to wrap to five rows (the first book began 53% down); it is
  one row now and the first card begins in the top 40% of the screen
  (`e2e/library.spec.js`, "the first book starts in the top 40%"). Import is
  the screen's main action but an icon, not a chip among chips: it is the
  only control that adds, and Material's guidance is that chips are for
  filters and choices, not for actions.
* **Sort and view is one menu** (`LSortMenu`, `sort-menu`, an `ovl` over the
  library; Apple Books' Sort By menu offers Recent, Title, Author and
  Manually in one menu, Material's menus check the current choice): the
  five orders (`sort_order`: Last opened, Title, Author, Date added,
  Series) and List or Grid (`layout`) as two groups of
  `menuitemradio`s (`ui_menu_choice`), the current one `aria-checked`
  (`_view_show`), the mark drawn by the stylesheet (`.mi[aria-checked=true]::before`).
  A choice closes the menu and is kept as before (`set_apply`, `set_save`).
  `sort_next` is gone; `tests/static/next.py` fails a `*_next` function
  that takes and gives a datatype of more than three constructors (the
  reader's footer readout, tapped to go round as the Kindle apps' footer
  does, is the one allowed). The filters (All, Unread, Reading, Finished)
  stay chips: they are a filter of the collection, which is what Material
  3 chips are for, and List and Grid, a view, are no longer among them.
* **Hidden, Archived and Trash are screens of their own** (`LShelf`,
  `shelf-header`: a back button, the shelf's name and More options, in
  place of the library's bar while it is open), opened from the library
  menu, reusing the library's list; there is no shelf selector on the
  library (the old shelf button cycled four shelves, up to four taps from
  Trash back to the library, and a prominent Hidden undercut hiding a
  book). Kindle keeps archived items out of the main library list too, in a
  menu entry of its own. A shelf is a layer, so Escape, Back and the back
  button close it as one step (`_escape_overlay`: `Escaped(LShelf())` shows
  the library again), and the filters, search and collection are the
  library's alone (`_passes` lets everything on a shelf through; opening a
  shelf clears the search and the collection). More options stays on a
  shelf's screen so Empty Trash is asked from the Trash itself, as Drive's
  Trash has its Empty trash. A book opened from a shelf's screen closes to
  the library (`_show_reader`). A shelf's rows offer Unhide, Unarchive (it
  says to import the book's file again: archiving drops the file) and
  Restore (Trash). A row's actions open on its More button and on a long
  press or right click (`contextmenu`), as before.
* **An empty library says what to do, and only that one** (`emptiness`:
  `NoBooksYet | NoMatch | NoCollection | NoUnread | NoneReading |
  NoneFinished | NothingHidden | NothingArchived | TrashEmpty`, made by
  `_emptiness_of`, said by `_emptiness_text`, and `_emptiness_offers` is
  true for `NoBooksYet` alone, each a total `case+`). NN/g on empty
  states: communicate system status, provide learning cues, direct
  pathways for key tasks. With no book to search, sort or filter the bar
  keeps its name and menu (`_tools_show`), and the message offers Import
  EPUB (`empty-import`, a primary button, its own file input
  `empty-import-file`, both inputs always there so a pick is never lost to
  a control made again) and Get free books (`empty-catalogues`, which opens
  the Catalogues). Every other reason for an empty view is said and offers
  nothing, since importing would not change it. The unreadable library
  (#374) keeps the bar's inert Import and no offer.
* **One word for a book's state** (`reading_state`: `StateUnread |
  StateReading | StateFinished`, `_reading_state_of`): the filter and the
  card use it, so the card says Unread and Finished where it said New and
  Done beside chips that said Unread and Finished.
* `e2e/library.spec.js` plays each of these (and `e2e/walk.js` walks the
  sort and view menu and the three shelf screens, so the layout, safe
  area, target size and Back specs cover them). The listener table has
  room for them: the library's wiring grew by four.

The page turns by a horizontal drag, recognized by the gestures package
(its classifier and drag state machine are proven there). Bridge's
`listen_pointer` on the reader view (`OnPointer("reader")`) sends each raw
pointer record. `_gesture_record` in `src/bin/quire.bats` hands it to the
gestures package's pointer source (`gestures_raw`), which batches the
records per frame and feeds the recognizer. The source answers with
gesture events and with actions for the host: `CapturePointer` (done by
`ui_pointer_capture`) or `WantFrame` (bridge's `animation_frame`, then
`gestures_frame`, at most `FRAME_ROUNDS` frames in a row). A pan scrolls
the page with the finger (`reader_pan`), a commit turns it and a cancel
puts it back. The page (`page`, region 1, `data-gesture-region`) takes
touch and pen only, so a mouse drag still selects text; its CSS
touch-action comes from the same axes the region is declared with
(`page_turn_axes` in `src/style.bats`). A drag's end suppresses the click
the browser sends after it (`_dragged`). The source captures a mouse
pointer only once it has moved more than 4 px: capture at pointerdown
would send the click to the reader view instead of the button under it,
so no button in the reader could be clicked.

Every page turn is animated (#246): a tap, a key, a button, reading
aloud and a drag. A copy of the page is kept in an overlay
(`page-turn`, idle: laid out but `visibility:hidden`), made by
`ui_copy_inert` in one flush of the DOM stream's own operations
(bridge's CLONE_NODE, then the copy's tabindex and gesture region
removed, `inert` set, its scroll set: quire's policy, not bridge's),
again a moment (`COPY_SETTLE_MS`) after the page last changed (a
chapter shown, laid out anew, an image come in), so a turn only
scrolls the copy to the place and shows it: on a 300 KB chapter its
first frame comes in 20 to 30 ms, where making the copy at the turn
took 110 to 200 (`e2e/page-turn.spec.js` holds it within 30 ms of an
instant turn's, in the same page). A turn shows only a `fresh_copy`,
which only `_copy_ready` gives, making a stale copy again first, so no
turn shows a chapter or a layout gone. The page
itself goes to the incoming page at once, so the place, the indicator
and the arenas' window move as before. The overlay is a strip of
[copy | gap] scrolled each frame, so the copy slides off (mirrored
right to left, along the axis for `Down`) with the stylesheet's edge
shadow, over a shade (`turn-shade`) on the page beneath. 280 ms,
eased out; a drag's commit takes what is left. Under
`prefers-reduced-motion: reduce` a turn is instant and nothing is laid
over the page; so it is in a chapter too big to slide a copy of
(`_chapter_heavy`, #423, below), which keeps no copy ahead either. The turn is a `turn_cell` in `src/reader.bats`
(`TurnStill`, `TurnHeld`, `TurnReturning`, `TurnWaiting`,
`TurnSliding`), each holding a linear `turn_sheet(HELD | SLID)` whose
constructors are local: a sliding sheet ends only by `_sheet_lift`, a
held one only by `_sheet_put_back` (the page back at its place) or
`_sheet_commit`, so no turn, interrupted or late, leaves the copy over
the page or the page between two places (`tests/static`'s
`page-turn-*`). The shade's levels are proven in each theme
(`VEILED`, written by `scripts/gen-harmony.py`): under it the text
keeps 7:1 and the links, highlights and marks 4.5:1, so Night has
none.

The reading settings' sheet (`typography-panel`, opened by the bottom
bar's Reading settings) holds every reading setting in named tabs
within the one sheet (#288, which gives the research: Kindle's Aa menu
has tabs; a "More" row and a screen over the sheet were a vague label
and a modal over a modal): Look (theme, font, size, the spacings, ruby,
dimmed images), Page (pages or scrolled, pages on screen, margins,
justify, hyphenation, the screen), Turning (Tap to turn pages, each
choice with a drawing of its zones, mirrored for a book read right to
left, and in the app one switch, Turn pages with volume keys) and Read
aloud (shown where the platform speaks or the book is narrated), with
Reset to defaults under them all. The tabs (`sheet_tab` in
`src/ui.bats`) follow WAI-ARIA's tabs pattern: the chosen one alone
selected and in the Tab order, the arrow keys, Home and End moving the
focus and the panel with it (`_sheet_tab_key` in `src/bin/quire.bats`);
the sheet opens on Look, and its head (title, Close and the tabs) stays
at its top as it scrolls. The sheet is as tall as its tallest tab
(#301): the panels lie one over another in one grid cell
(`typography-panels`, `.tabpanels`), the ones not chosen `.unchosen`
(`visibility: hidden`: their room kept, but not seen, focused or read
out), so switching tabs moves neither the sheet nor its tabs, and the
height follows the rows actually shown; a tab chosen shows from the
sheet's top (`ui_scroll_to_top`). Their controls are one `typography_control`
datatype, stored, backed up and reset as before.

The reader is fixed to the window (`.rv`, not a height in `vh`, which
an Android WebView can make taller than what it shows), and the page
keeps out of the screen's safe area on every side (#275): above and
below in its paddings (`env(safe-area-inset-top)`, `-bottom`), at its
sides in its margins (`-left`, `-right`), so no text is under a camera
cutout, in or out of full screen, in either orientation. In the app the
WebView is given the cutout's insets by Capacitor's SystemBars (pwa's
`insetsHandling: native`: a WebView from 140 on reads them out, an
older one is padded natively instead). Every other screen, panel,
sheet, dialog, toast and bar pads the sides it can touch by `--safe-*`
(`_spacing` in `src/style.bats`): that side's inset and the spacing
scale's least inset beyond it, so none of its controls or text comes
near a system bar (#341, `e2e/safe-area.spec.js`). A spread's columns are at least
40vw, so two fit beside a cutout. A sheet's height is in `dvh`, and the
typography sheet's head (`.shead`), with Close, is held at its top as
it scrolls. `e2e/layout.spec.js` sets the insets through DevTools.

The visible reading area is given once, as the reader view's (`.rv`)
variables in `src/style.bats` (#296): the running footer sits 8px above
the screen's bottom inset (`--footer-bottom`, Android's navigation bar,
which the app is drawn over edge to edge), 16px tall
(`--footer-height`), and the page's paddings (`--page-top`,
`--page-bottom`) keep the text half a line (at least 12px) clear of the
footer and of the top inset. A column is the page's height less those
paddings, so it is exactly that area; a vertical page's column gap and a
picture's largest height are the same paddings. Pages are counted
across by the page's scroll width, which the column's height does not
change. Scrolled, the same variables are the page's margins instead
of its paddings (`_put_scrolled` in `src/settings.bats`), so the page
is the reading area itself and its text is clipped there, never drawn
under the footer or a system bar; two transparent fixed bands (the
page's `::before` and `::after`) keep a tap or a drag beside it the
page's, and a turn (`_step`) scrolls the area's height less one line
of the text, so the line its foot cuts is whole at the next screen's
head. `e2e/page-margins.js` measures those margins against the
insets the page computes, and the e2e fixture measures them at the end
of every test in the phone-sized projects (`MARGIN_PROJECTS`), full
screen too, whenever the reader shows a reflowed page, paged or
scrolled, with the bars down, so a spec that leaves the reader open
checks them; each line counts as drawn, cut to the page's scrollport.

The reader's bottom bar follows the reading direction (quire#359; Apple's
HIG flips progress and the next and previous buttons in a right-to-left
context, Material runs a progress bar from the right): the book's
`reading_direction` (`LeftToRight | RightToLeft`, from its spine, matched
with `case+`) is kept by `_direction_set` in `src/reader.bats`, which gives
the bar (`.bot.rtl`) and the scrubber (`.trk.rtl`) their class and swaps
the page-turn buttons' arrows, and every drawing along the reading axis
takes `_drawn_at`: the thumb, the chapters' ticks and the tip are placed
from the right and the fill grows from it, and a drag's x on the track is
turned back into the book's thousandth (`_track_at`). Previous is right
of Next. `expectBarFollows` in `e2e/helpers.js` checks it for a book
whose spine reads right to left, a Hebrew one whose spine does not say so,
a vertical Japanese one, and a left to right one; `vertical.spec.js`
fails first, naming the cause, where no font has Japanese characters
(CI installs `fonts-noto-cjk`).

A book is set vertically as Readium sets it, from its OPF (the book's
CSS is dropped): `vertical-rl` when its spine reads right to left and
its language is Chinese, Japanese or Korean, `vertical-lr` for
Mongolian in its script (mn-Mong) read left to right. `spine_vertical`
in `src/epub_xml.bats` answers a `writing_mode` (`Horizontal |
VerticalRightToLeft | VerticalLeftToRight`), from the spine's
`spine_progression`, and `src/reader.bats` keeps it in `_vertical`.
CSS columns follow the inline axis, which then runs down, so its pages
go down the page: the page's class is `caf vertical` (not `rtl`, whose
`direction` would turn that axis upward), a column and its gap (the
page's top and bottom paddings) are exactly the page's height, and
Latin and digits are turned, the default `text-orientation:mixed` (JLREQ: an English word is rotated 90 degrees; only a short number or acronym stands upright, by `text-combine-upright`, which no browser supports as `digits` and which needs the run wrapped for `all`; quire#391 stays open for that), and `_page_axis` (`Across`, `AcrossBack`, `Down`) is what counts, finds and
shows pages, by scrollTop for `Down`. Such a book is always paged, one
column a screen, a drag does not follow the finger (a committed one
turns the page), and the settings of the page's layout and of its
words' spacing and breaking are hidden while it is open. A paragraph's
margins are logical (`margin-block`, and the Paragraph spacing setting
as `margin-block-end`), so set vertically the space after it is beside
it and its lines keep their length; that row stays. Taps, keys and
swipes keep the meaning of a book read right to left.

A fixed-layout book (EPUB 3.3 §8.2, `rendition:layout` pre-paginated)
is shown a spine item a page, as Thorium shows it. `src/epub_xml.bats`
reads the OPF's layout (`opf_layout`), each itemref's own
(`itemref_layout_n`: `rendition:layout-pre-paginated` or
`-reflowable` outranks the book's) as a `rendition_layout`
(`Reflowable | PrePaginated`), kept with each chapter in `Chapter`, and
a page's viewport meta (`xhtml_viewport`: a `viewport`, its width and
height 1 to 10000, or `NoViewport`). The reader (`_layout`, `_is_fixed`)
renders a fixed page into a box (`page-box`, `_box_add`, the page's one
child; `_render_into` says which element a chapter's top-level nodes go
into, so its content nodes are numbered as ever), laid out as its
viewport (else the last fixed page's, in `_page_size`, as EPUB RS 3.3
§8.1.2 allows; else the view's) and scaled with CSS `zoom` to fit whole,
letter-boxed (`_fixed_fit`, at every layout, so a resize fits it
again). The page (class `caf fixed`) is then the whole reader view, the
bars over it as over a reflowed page, the box centred in it, so taps
and drags beside a letter-boxed page turn it. It is one page, never
scrolled or in columns, its images fit it (`100cqw`, `100cqh`), and it
is set horizontally whatever the book's `_vertical` (`_writing`). The indicator counts spine items ("page 5 of
24 in book"). It is not restyled: only the theme and what the reader
does (taps, keys, reading aloud, the screen) are offered, with Columns,
which say its spreads (`_rows_set`).
The book's own CSS is dropped as for every book, so text a publisher
placed over art shows in flow.

Fixed pages are shown two at a time, a spread, as the Columns setting
says (Two always, One never) and at Auto as the book's
`rendition:spread` says (`rendition_spread`: `SpreadNone` never,
`SpreadBoth` always, `SpreadLandscape` and `SpreadAuto` when the view
is wider than tall, as Apple Books and Thorium do; `_spreads_wanted`).
Each itemref's `page-spread-*` is kept with its chapter (`page_spread`),
and `book_chapter_slots` places the pages as Apple Books does: a page
takes the side it asks for, else the side after the page before it,
and the first fixed page (or the first after a reflowed one) is alone
on the right (on the left read right to left); a centred page is
alone. `_shape_of` makes the page shown a `spread_shape`: `Single`,
`AloneLeft` or `AloneRight` (the other side blank), or `WithNext` or
`WithPrevious` (a spread of two). Its facing page is rendered into the
other box (`facing-box`, `_facing_open`), its content nodes going on
from the page's, after the page is shown; it cannot be selected
(`.facing`), so what is marked or read aloud is the page's. The two
boxes meet in the middle with no gap (EPUB RS 3.3), each fitted to its
half. A turn moves a spread at a time, and a layout that wants spreads
otherwise (a turned device, the Columns setting) shows the page again.

The back button a jump leaves (to the place jumped from) never stays
up: `ps_cell` in `src/reader.bats` holds the positions it offers, and
its only shown state, `PsShown`, needs a proof `TIMED(g)` that a timeout
numbered g is armed; `_ps_put`, the only code that shows or hides the
button, shows it exactly in that state. `TIMED`'s constructor is local to
`_timed_arm`, which arms the timer, so no other code can make one, and a
proof for one number does not type-check as another's. When the timeout
runs (10 s, `BACK_SHOWN`) the button goes with its positions, unless a
later jump has armed a later timeout. It goes sooner when a page is
turned, the bars are brought up (`_chrome_set`), or a book is opened or
closed (`reader_stack_clear`).
`tests/static` holds code that must not type-check (a forged `TIMED`,
another timeout's proof, the button with nothing to offer), and code
that must (`_back_offer`); CI runs `tests/static/run.sh`.

A static fixture is a snippet put into one module (`file`, before the
line `before`), and it knows what proof fails when it is built. A reject
fixture's `expect` names the function of its snippet, the line of the
snippet patsopt reports, and patsopt's error word for word (the
constraint left unsolved, the case left out, the type that does not
match); `tests/static/expect.py` passes it only when that is the one
error of the check, in that module, at that line, inside that function.
A substring that another error could also hold is not enough. An accept
fixture must check. Each fixture is put into the app checked whole in
the same job, so only its module is checked again, and what depends on
it when its `#pub` declarations change (bats keeps a module's C while
the `.sats` it staloads has only moved, and each of check's passes keeps
a cache of its own, bats-lang/bats#243), and a reject fixture stops at
its error: a fixture costs about what its snippet changes.

CI runs the static tests and the e2e suite in groups side by side
(`tests/groups.json`), the e2e groups on the app built once (the `build`
job). Every spec and every static fixture is in exactly one group, or
`scripts/ci-groups.py` fails the run: a new one is put in a group, by
area and balanced by time. The `check` job, which main's branch
protection requires, passes only when every group did.

Each group runs every project of `playwright.config.js`: `desktop` and
`mobile-portrait` every spec, `narrow` (320 px, WCAG's reflow width),
`mobile-landscape`, `tablet` and `wide` the layout specs, and `android`
every spec (#295): a Pixel-class phone (412 x 915 at 2.625, touch, the
WebView's user agent), its status bar and gesture navigation as the
safe area's insets, and the app's Capacitor played in the page
(`androidApp` in `e2e/fixtures.js`), so bridge takes its Android branch.
`scripts/ci-groups.py` fails the run when the `android` project is
missing or narrowed (a testMatch, testIgnore or grep, in it or over the
configuration, or a --project or --grep on CI's run); a spec that cannot
apply on Android skips itself there, saying why (`test.skip`).
`e2e/icons.spec.js` checks that every icon (a Private Use Area
character) is drawn by the icon face, by drawing it on a canvas, so it
does not hang on the machine's fonts.

Listeners are registered only as one table (`regs` in `src/ui.bats`),
each with its position as its id, so no two share an id, and the
table's length, in its type, is at most 127: the bridge's last slot
(of 128) is the media query listener's (`ui_media_listener`), which
shares the bridge's table, so no listener of the table can take it.
The platform's typed listeners take their slots in the same table:
full screen's (`RFullscreen`), the app's system bars' (`RSystemBars`),
speech's (`RSpeech`), the install
offer's (`RInstallOffer`), the app's links' (`RAppLink`) and the page's
fonts' (`RFonts`), each given its event as bridge decodes it. A
chapter's pages are counted again as it is shown, for 3 s (`_settle`),
and whenever a load of the page's fonts ends (`RFonts`, bridge's
`listen_fonts_loaded`): the reading face can arrive after those 3 s,
and the count made with its fallback would stay. A layout made anew
(those counts, a resize, the type) shows the page of the node the
place is kept by (`_anchor_kept`: the one a jump took the reader to,
else the one at the top of the page they last moved to) and keeps that
node until the reader moves, never the node at the top of the page it
then shows, which can begin before it, so layouts one after another do
not move the place back (quire#305).

The place also survives the app's bars shown or hidden (quire#356). The
app is drawn edge to edge, so full screen changes the reading area
only through `env(safe-area-inset-*)` (the page's paddings): the window
does not resize and no `resize` came, so the chapter was not laid out
again and the page, scrolled by whole pages of the old area, showed text
two paragraphs on. The activity reports the bars at each window insets
dispatch (`batsNative.systemBars`, `RSystemBars`), and when what is
shown changes (`screen_system_bars_changed` answers whether) the
chapter is laid out again once the area settles (`_relayout_for_bars`,
`reader_relayout_for_bars`, which does not hide bars the system brought
back: that is a page turned, not an area changed). What a place is: a
content node and the page that holds it, as an EPUB CFI (Kobo, Apple
Books, Calibre) or a Readium locator names a text position and not a
page, so the paragraph the reader was at stays on the page shown
whichever way the area changes (`e2e/layout.spec.js`, "the place stays
when the reading area changes"); where the page breaks fall is the
layout's, as in Kindle and Books.

## Pathological structure (#423)

KOReader's notes on slow books name the shapes `e2e/pathological.spec.js`
walks (`e2e/pathological-books.js`, each checked by epubcheck): a table
cell of many pages, a single-file book of 5 MB, a thousand nested
elements, ten thousand short paragraphs, a megabyte without a space. The
spec measures a pathological chapter against a plain one of the same
length, in the same page, so a slower machine slows both. What it found:

* **A wide chapter was never shown.** xml-tree's `_parse_nodes` cons-es a
  node onto the list that a call made after it parses, so the stack grows
  by a frame per sibling. Wasm's stack is 1 MiB (the compiler's
  `stack-size`, no package or project sets it), and a body of about 9000
  paragraphs (8800 shows) ran out of it: the overflow wrote into the
  module's data, raised nothing, and the reader stayed blank with no
  banner and no console error. The same 9000 paragraphs in groups of 100
  divs show, so it is the width of one sibling list, not the node count.
  `src/xhtml_parse.bats` is xml-tree's parser copied with one change: a
  list of siblings is collected last first in a tail-recursive loop and
  put in order by another, so the stack holds the document's depth, not
  its width (a thousand nested elements was already fine). It builds
  xml-tree's own trees (freed by its `free_nodes`), and every chapter
  parse (render, facing page, search, note, read aloud) uses it; the OPF
  and SMIL, which are small, still use xml-tree's. Tested with 9000 and
  30,000 paragraphs, not proved (the stack's size is not in the types).
  The change belongs upstream: bats-lang/xml-tree should parse siblings by
  a loop, and this file then goes. Searched for a limit to say in the
  banner instead, and rejected it: truncating a chapter at a guessed
  count would have hidden text that shows today.
* **A run with no break opportunity was clipped.** `.caf` has
  `overflow-wrap: break-word`. By research: MDN says `break-word` and
  `anywhere` break a run the same way, and differ only in that `anywhere`
  counts the breaks in min-content sizes. `anywhere` was tried first and
  `e2e/wide.spec.js` failed: a table whose cell holds a long run no longer
  made the table wider than the column, so it did not scroll inside its
  own container (#413) but wrapped. `break-word` breaks the run at the
  column's width and leaves a table as wide as its content. (No ebook
  reader's stylesheet was found stating its choice; Readium CSS was
  searched for, with no result.)
* **A page turn cost time in proportion to the chapter.** Profiled with a
  DevTools trace (not guessed) on the 5 MB chapter: a key took 200 to
  280 ms in the page's script, and the hit test was not the cost.
  `#bats-root:has(...) .banner`: Blink re-evaluates a `:has()` whose
  subject is an ancestor of every change over the subject's whole subtree,
  and `#bats-root` holds the chapter's 30,000 nodes, so every change to the
  page's chrome (the indicator's text, the footer's) forced a 16 to 27 ms
  style recalculation at the next measure, four times a turn. The banner's
  place is now a class the views set (`banner_place_set` in
  `src/notice.bats`: `BannerAtTop`, `BannerInLibrary`, `BannerUnderBars`,
  set by `_library_shown`, `_show_reader`, `_chrome_set`, `_chrome_set_off`),
  and the stylesheet keys on `.banner.in-library` and `.banner.under-bars`.
  The two remaining `:has()` rules have small subjects (a button, a
  settings row). A key on the 5 MB chapter went from 206 to 276 ms to 21 to
  31 ms of script. What is left of a turn on a chapter of thousands of
  boxes is the browser's: the hover hit test it makes after the scroll
  (190 ms for 10,000 one-line paragraphs, in the PrePaint of the next
  frame), and, when the sheet of the page being left is slid, the
  prepaint of its copy (170 ms more for the same chapter; a megabyte
  without a space, 100 ms more). Neither is the app's to make cheaper
  (`visibility` on the idle sheet is inherited, so moving it, or hiding it
  another way, was tried and costs the same or breaks
  `e2e/page-turn.spec.js`'s check that an idle sheet is not visible), so a
  chapter too big to slide a copy of turns at once, as under
  prefers-reduced-motion (`_chapter_heavy` in `src/reader.bats`: 6000
  content nodes or 600 KB, between the 300 KB chapter of 2100 nodes that
  page-turn.spec.js measures, which stays animated, and the first that is
  late). That is a choice of this project, from these measurements and
  from RAIL's 100 ms to respond (a first frame that late is not an
  animation); the turn is no longer than the reader's own key. Such a chapter
  keeps no copy made ahead either (`_copy_stale`): the clone of its whole DOM
  was 3 s of script for 30,000 nodes, in which the page did not answer; a
  drag, which does lay a copy, makes one then.
* **The anchor is found by search, not by hit test.** `_anchor_now` took the
  element at a point (`elementFromPoint`, then stepping 40 px at a time),
  and then the first of the next 40 nodes to start on the page. A hit test
  in a multicolumn chapter costs in proportion to the fragments it walks
  (and forced the layout the page was waiting on). Content nodes are
  numbered in document order and the text flows in it, so where they start
  grows with the number (down the page, across it, or back across it, as
  `_page_axis` says): `_first_on_or_after` is a binary search of the nodes
  for the first that does not start before the page (undrawn ones,
  a blank between blocks or a ruby's `rp`, are stepped over, at most 64 in
  a row), by `getBoundingClientRect`, which costs 2 microseconds on a
  clean layout in a 5 MB chapter. When no node starts on the page (it is
  wholly inside one carried over), the anchor is the last drawn node
  before the first that starts after it, as the hit test found one inside
  the carried-over node. A fixed page keeps the hit test (`_anchor_hit`):
  it is one spine item, its nodes are few, and a spread's facing page is
  numbered after it, so the numbers are not in order across the two. The
  place's semantics are unchanged (the kept anchor, a layout that does not
  move the place): only how the first node is found. `_show_page_down`
  asks once per page shown (`_record_position` used to ask twice).
* **A giant run of text was drawn in time that grows with the square of
  its columns (the megabyte word, 17 s to open on a phone).** Found by
  profiling and then by taking Chrome alone: the app's own code was
  negligible (a CPU profile of the click on Two: the wasm under 50 ms, 16.9
  s in one PrePaint), and a page of plain HTML with the same text, columns
  and window did the same (30 px text, 1 MB, two columns: 3361 pages, 18 s
  a frame, 0.7 s of it layout; 2017 pages 5.9 s; 1113 pages 1.7 s). The
  cost is Chrome's per inline run across columns: one paragraph of 1 MB is
  one inline formatting context spread over thousands of fragments, and a
  frame is quadratic in them. The same text as 16 paragraphs of 64 KiB took
  1.1 s, as 64 of 16 KiB 0.8 s; a real paragraph of 1 MB with spaces took
  88 s as one. No CSS tried (contain, content-visibility, will-change,
  translateZ, overflow) changed it. So the app does not give Chrome a run
  longer than a piece: the pieces `_text_spans` already cut a text of 64
  KiB or more into (a text op's limit) are class `run`, shown as blocks
  (`.caf .run`), and are cut after the last white space in their last 512
  bytes (`_text_cut`; a run with no white space is cut at a character, as
  before). Complexity: the frame of a run of n columns was O(n squared)
  and is O(n) in the number of pieces; opening the megabyte word on a
  390 px phone went from 17 s (Two) to 1.5 s, and the opening to 1 s. A
  text node over 64 KiB in mixed content breaks its line at each piece (a
  paragraph break appearing in a 64 KiB run is the price; search counts
  pieces with the same `_text_cut`, so its node numbers agree; a note or
  highlight stored in a text node of 64 KiB or more may find its offset
  moved by up to 512 bytes into the next piece). The open budget the spec
  asserts (`expectOpenBudget`): the time from the card's tap to the
  chapter's indicator, and from the choice of Two, Scroll or One to its
  page indicator, is at most 3 times Chrome's own time to lay out and
  draw a copy of that DOM in that window and arrangement (`bareFrameMs`:
  the copy is put beside the page, laid out, drawn for two frames and
  removed, so a slow runner is slow for both), plus 1 s for what is not
  layout. Measured (phone, this machine): the megabyte word opens in 1.0
  s against 0.8, Two in 1.5 against 1.8, 10,000 paragraphs open in 2.3
  against 1.7. No timeout was raised to get there.
* **The spec's long chapters run without Playwright's trace and
  screenshots** (`heavy` in `e2e/pathological.spec.js`): its snapshotter
  walks every node at every action, 2 to 3 s on a chapter of 30,000, which
  is the harness's cost and made the steps time out. The stall watch
  stays on. `e2e/page-margins.js` now clips a line to the scroll
  containers inside the page (a table is one since #413): a line a table
  holds past its own scrollport is not drawn, so it is not under the
  footer.
* **A table is one box on one page** (#413), so a cell of 200 paragraphs no
  longer spreads over a hundred pages. The spec's old assertion, that the
  chapter with the cell fills about as many pages as the same text in
  plain paragraphs, was true only while a cell was one unbreakable box
  that cut off all but its first column; it is now that the chapter is
  fewer pages than the plain one and the cell scrolls inside its table
  (the table's last paragraph is reached by scrolling it). The threshold
  was wrong, not the code.
## Touch selection (#428)

`e2e/touch-selection.spec.js` plays a long press (Chromium's touch
emulation of the mouse), a handle drag (as the selection it makes: quire
draws no handles, the browser does), a selection across a column gap and
an image, the footnote popup, the toolbar's place, and a tap that ends a
selection. Its header holds the research; the decisions it led to:

* **A selection holds the page.** While text is selected, or was when
  the pointer went down on the page (`_press_selected`; Chrome clears the
  selection on the press), a pan does nothing and a commit puts the page
  back (`_selection_holds`, `_on_gestures`): the finger that drags the
  selection's handles, or one put down on it, never turns the page.
* **A tap that began on a selection only ends it.** `_press_selected` is
  recorded at `pointerdown` on the page; the click that follows turns
  nothing and brings up no bars (the platform's rule for text selection:
  a tap outside clears it and does nothing else; Apple Books, Play Books
  and the Kindle document nothing different).
* **The toolbar is for the chapter's text.** It shows only when the
  selection starts in a content node of the page (`annot_selection_in_page`),
  so text selected in the footnote popup has none: Highlight and Note
  cannot work there, and a control that cannot work is not shown.
* **The toolbar lies over neither the text nor the handles.** It is
  placed from the selection's rectangle on every `selectionchange`
  (`_toolbar_place`, `ui_toolbar_at`, which writes only two numbers as
  the custom properties `--seltb-top` and `--seltb-height`): above the
  selection with an 8 px gap (Flutter's `TextSelectionToolbar` anchors
  above and falls below only where there is no room), else below the end
  handle with 20 px clearance (Firefox for Android moves its floating
  toolbar 20dp off the selection so it does not lie over the bottom
  handles). The stylesheet's `.seltb` clamps the top to the window and the
  safe area. Above is chosen only where it clears the safe area's top: wasm
  cannot read the inset, so a hidden probe (`selection-toolbar-floor`,
  `.seltbfloor`) is as tall as `max(8px, var(--safe-top))` and is measured.
* **Edge of the page.** A selection stops at the page: the page does not
  turn while a handle is held at its edge (Moon+ Reader scrolls on, Kindle
  and Google Books reportedly flip; nothing found documents Apple Books or
  Play Books; a quire page is a CSS column and a selection is one range, so
  a highlight across two pages is two highlights).
* **Tapping a highlight selects it** (`annot_tap_select`, the page's
  click in `src/bin/quire.bats`; bridge's `select_range`, `clear_selection`
  and `selection_available`). A tap between the sides' zones (the side
  zones keep turning the page) finds the highlight of the chapter shown
  that holds the tapped point (the tapped content node and the caret's
  offset there, `caret_position_from_point`), makes its range the selection,
  so the one selection toolbar is up with it, and remembers it by its
  chapter, start node and offset (never by index, which an insertion
  moves). Research: Apple Books and the Kindle apps show a highlight's menu
  on a tap on it (Apple Books: idownloadblog.com/2020/01/22/highlights-notes-apple-books-app/;
  Kindle: tomsguide.com/how-to/how-to-highlight-text-and-make-notes-on-your-kindle);
  a Kobo offers handles on the highlight, which its users call terrible,
  since they will not move while the menu is up
  (mobileread.com/forums/showthread.php?p=3803381). Quire has one toolbar,
  so the tap makes the highlight the selection and the handles are the
  browser's. Highlight, Orange and Underline then replace that annotation's
  range when the selection still overlaps it (else the selection is a new
  highlight, as when a handle was taken elsewhere): `_reshape` deletes and
  adds, so sync passes on a deletion and a new annotation, and the note is
  kept; `undo_offer(HighlightRangeChanged())` puts the old range, its text
  and the kind back (found by the range it has by then). Note on a tapped
  highlight changes the range the same way and opens that highlight's note,
  which cancelling does not delete. The remembered highlight is let go when
  the selection ends. After Highlight, Orange and Underline the selection is
  cleared (`annot_selection_end`), so the text is not left selected under
  the page. A `select_range` that is refused or finds no element is said
  (`HighlightNotSelected`), and a selection that cannot be cleared too
  (`SelectionNotEnded`): every constructor of both atoms is matched.

## A page that stops answering in e2e explains itself (#244)

Every spec takes `test` from `e2e/fixtures.js` (`e2e/global-setup.js`
refuses a spec that does not), whose auto fixture `stallWatch`
(`e2e/stall-capture.js`) arms each page as it is made: a DevTools
session of its own with the debugger enabled and breakpoints inactive,
since a page already stuck in a loop can no longer be attached to or
have its debugger enabled (only `Debugger.pause` and a few others
interrupt running script). It asks each page to evaluate `1` every 2 s;
a page that does not answer within 5 s, and every page of a test 15 s
before its timeout, is captured: the frames `Debugger.pause` stops in
(wasm ones by function and byte offset), a CPU profile when nothing
pauses, which commands the renderer still answers, and the renderers'
CPU time over 1 s. The capture is `stall-capture-<n>.json` in the test's
output (CI's `e2e-stall-captures-<group>` artifact), attached to the test, and
summed up on stderr. `e2e/stall-capture.spec.js` checks it on pages that
loop forever in script and in wasm.
