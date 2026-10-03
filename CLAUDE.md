# quire

## Decisions are made by research, not left to the human

No task is ever "left to the human" unless an agent physically cannot do
it (a permission it was denied, access it does not have, a secret it
cannot see). Every other question, design choices included (which
layout, which wording, which default), is settled by research (what
other apps do, what their users and reviewers say, what studies and
guidelines say) and best judgement, written down where it is decided
(the issue or the PR), and then done. The quality rules below (the
proofs, the static tests, the e2e suite) still hold: when a choice
would break one, choose another that keeps it.

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
`fetch-depth: 2`), and `tests/version/same.sh` checks that it is the
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
under "dicts"; a removal is offered back by the Undo toast, and its
files are deleted when the offer is made final. The backup lists the
dictionaries' names and languages, not their files.

### Sync

`src/sync.bats` keeps places, shelves, collections, annotations and
reading time the same on the reader's devices, through one file,
`quire-sync.json`, in the backup's JSON format plus each record's
stamps, a `deleted` list per book and a `devices` list. Where the file
is kept is a `store` (`WebDav(url, user, password)`, or `Android`,
below): its credentials are stored on this device only, by the store's
kind ("sync" names the kind, "sync-webdav" holds the WebDAV ones,
"sync-android" the account's address), never in the backup. The merge and its tries call only `store_read` (the file,
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
"WebDAV · synced 2 min ago" ("Android · ..."), or how the last sync
failed.

A change is dated by a stamp (`src/clock.bats`): a hybrid logical
clock, minutes since 2025 times 64 plus a count, after every stamp made
or seen here (the browser gives the time only to the minute), written
in the file as milliseconds. Shelves, collections (by name) and being
finished take the latest change; the place, the furthest (the open
book's is offered by a toast instead); the reading log and each book's
time are each device's own (its entry in `devices`), summed for display
(`stats_elsewhere_*`, `minutes_elsewhere`). An annotation's id is the
SHA-256 of what never changes in it (bookmark or highlight, chapter,
start, end, minute made), so it is never stored and two devices that
restored one backup give it the same id; the latest change wins, and a
deletion (`deleted`, kept 180 days, `QA3`) wins over a change made
before it. A book only another device has is kept as an orphan ("o").

**Use Android** (#184), in the app only (bridge's
`google_token_available`): the store `Android(account)`, the file in
the app data folder of the device's Google account's Drive
(`src/drive.bats`: a listing for its id and version, then its bytes; a
write checks the version is still the one read, else it is a
conflict, and replaces the bytes, or makes the file in
`appDataFolder`). The access token for `drive.appdata` comes from
bridge's `google_token_get` (Capawesome's Google Sign-In, which shows
Google's sheet each time it is asked), so it is asked for only when
the reader acts (Use Android, Sync now) and kept in memory while the
app runs (`_token`); a sync the app makes by itself without one, or
one Drive refuses (401), says "Tap Sync now to sign in to Google
again". No account, a cancel, and a build with no client each say so;
Turn off signs out. The client ID is public and not compiled in:
`scripts/sync-clients.sh` writes the repository variable
`GOOGLE_WEB_CLIENT_ID` (checked) into `sync-clients.json` beside the
app, read by `src/sync_clients.bats`; with none, Use Android says it is
not set up. With no store chosen, the app keeps the file for Android's
Auto Backup (`STORE_BACKUP`, bridge's `backup_file` in `backup/` of
the app's files, the only thing pwa's backup rules keep): each sync
point merges it and writes it there, and the file a reinstall
restores is merged at the first launch like any sync file; a store's
write writes it too. `e2e/sync-android.spec.js` plays both plugins
and Drive's API.

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
The typography panel offers, for a narrated book, its speed (0.5× to
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
  and so are the brightness and the rotation lock: in the backup
  (`readingSpeed`, `voices`, `brightness`, `rotationLocked`) and reset
  with the settings, Undo putting them back (`set_reset_undoable`;
  `screen_controls_apply` sets the screen again). Going to the library, opening
  another book, or the page going away (`pagehide`) stops reading.
* **The screen** (`src/screen_controls.bats`, the typography panel's
  Screen row): Full screen (`fullscreen_*`, pressed as
  `listen_fullscreen` says), Lock rotation (`orientation_*`, a
  `rotation` kept with the settings and locked again as the app
  starts), and Brightness (`brightness_*`, the app only: a
  `brightness_choice`, the system's or 10 to 100%, kept with the
  settings and set again as the app starts).
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
  the library menu says whether it is (`storage_persisted` at startup).
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
  are what the Android activity calls.

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
`tests/static/case_plus.py` fails on any plain `case` (ATS2 checks only
`case+`), in CI through `tests/static/run.sh`.

## What the types guarantee about the interface

The stylesheet is built in `src/style.bats`, not written as CSS:

* A text colour and its background are only ever set together
  (`surf`), with a proof (`SURF`) that the pair reaches 4.5:1 in each
  of the five themes. The proof is css's `CONTRAST` over the palette
  (`PAL`): a table of every sRGB channel's linear light (`LIN`, made by
  css's `scripts/gen-contrast.py`) bounds each colour's luminance, so
  a pair that falls short does not type-check. Control edges and
  accents need 3:1 (`EDGEP`). Grounds without text (`fill`, `tint`)
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
* The base rules are the only `!important` ones: every control is at
  least 44px square, text fields use a 16px font (so iOS does not zoom
  in), and focus shows a 2px ring in the text's own colour.
* The sheet's size is in its type (`sheet(r, st)`: r bytes left), so it
  always fits the 64 KiB text it is put in.

Elements are made through `src/ui.bats`:

* Plain elements come from a tag type with no interactive tags; a
  button, a field or an image can only be made by a constructor that
  names it. A text button is named by its text alone, so its name
  holds what it shows (WCAG 2.5.3); an icon button is given its name;
  images are decorative (`alt=""`); an audio element (`ui_audio`) has no
  controls and is hidden from assistive technology; a role that needs a name (dialog,
  region, toolbar, menu, group) is given one with it.
* Each element id is made at one place in the code, no numbered id
  (`nid_make`, a prefix and a number) can spell another, and every id
  the code names is one it makes: `tests/static/ids.py` checks the
  source (the constructors, `ui_harm_id`, and helpers that pass an id
  on), in CI through `tests/static/run.sh`. An element made again to
  reset it (a search field, a file input) is made by one function,
  called at startup and at the reset.
* `ui_attr` takes a typed attribute that cannot be a name, a role or a
  style. The inline styles are a place (`ui_place`: left or width,
  in tenths of a percent up to 100%) and a fixed page's box
  (`ui_fixed_box_n`: width and height, 1 to 10000 px, and a zoom of 1
  to 10000 thousandths, so a zoom of 0 does not type-check), each
  written from numbers alone, so no inline style can set a colour or
  anything else the stylesheet proves.

Nothing is lost at a click, except by emptying the Trash:

* Removing a book moves it to the Trash (the shelf `Trash`), where it can only be
  restored; archiving, hiding, deleting a highlight or bookmark and
  resetting the settings are done at once. Each is offered back by the
  Undo toast (`undo_offer` in `src/undo.bats`), whose undo runs only
  from its own button, whose listener the module registers
  (`undo_listen`). An earlier offer is made final when another takes
  its place or the toast goes.
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
whole (the library, settings, statistics, reading speed, catalogues,
dictionaries, sync's state, a book's annotations) that could not be
read is not saved this session (`src/storage.bats`: its save checks
`storage_savable`), books are not added to an unread library, and an
unread book's annotations cannot be made; the banner says so. A backup
that could not read a book's notes is not made.

The overlays (the menus, book info, the reader's panels and the full
screens: Settings, Sync) are a `layer` (`src/layer.bats`), whose
element ids only that module knows: they are shown and hidden only by
`layer_open` and `layer_close`, which keep the stack of open overlays,
last opened on top. Escape answers the dialog if one is open, and
otherwise closes the top of that stack (`layer_escape`), whatever
opened it: from Sync, Escape goes back to Settings, and another closes
Settings.

The Settings screen (`LSettings`, `settings-screen`, made by `app.bats`
and wired by `_wire_settings_screen` in `src/bin/quire.bats`) follows
Android's settings pattern: one screen of groups, each complex area a
screen of its own opened from a row that shows its state. It opens
from the library menu's Settings and from the reader's top bar (the
gear after Search: the bottom bar, with Contents and Typography, has
no room left for it on a phone), and holds Sync ›, Dictionaries ›, the backup
(Export backup, and Restore backup: the input `backup-file`), the daily
reading goal (also in the statistics panel; `stats_goal_show` marks
both), Reset settings and Factory reset, each with its Undo, and
About Quire › (`LAbout`, `about-screen`): the app's name and links out
of the app (`ui_link_out_https`, an address dom's `set_url_literal`
sets) to the home page, privacy policy, terms and source. A
restore or a factory reset from the reader goes back to the library
first.

The home page, privacy policy and terms are plain static HTML in
`homepage/` (#216), published by `deploy.yml` beside the app at
`https://bats-lang.github.io/quire/homepage/` (`privacy.html`,
`terms.html`). They are not the app's: gen-pwa does not read them, the
Android project does not hold them, and the service worker (bridge's
`produce_service_worker`) answers only files directly in its scope, so
it neither answers nor keeps them (`e2e/about.spec.js`). The privacy
policy states what the code does: change it with any change to what is
stored, what leaves the device, or the Google scopes asked for.

The library menu keeps Install, the storage notes, Settings, About
Quire (the same About screen, so the library reaches it without
Settings), Reading statistics, Catalogues, Empty Trash (the red harm
item) and Close. While Settings is open over the reader, keys are its own, not
page turns.

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
`_page_axis` (`Across`, `AcrossBack`, `Down`) is what counts, finds and
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

Listeners are registered only as one table (`regs` in `src/ui.bats`),
each with its position as its id, so no two share an id, and the
table's length, in its type, is at most 127: the bridge's last slot
(of 128) is the media query listener's (`ui_media_listener`), which
shares the bridge's table, so no listener of the table can take it.
The platform's typed listeners take their slots in the same table:
full screen's (`RFullscreen`), speech's (`RSpeech`) and the install
offer's (`RInstallOffer`), each given its event as bridge decodes it.
