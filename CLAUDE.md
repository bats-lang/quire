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
  in `src/sync.bats`), refused over 16 MiB (`SYNC_MAX_BYTES`).

Each piece lives only while it is parsed or written: nothing is kept
between page turns yet, since pages are CSS columns of the chapter's
DOM.

With `alloc`:

* `src/book.bats` (`book_index_make`): the archive's tail and each
  entry's local header while the book is opened, and its central
  directory (at most 1 MiB), kept while the book is open for its
  entries' names.
* `src/book_cards.bats` (import): the OPF path (`opf_path_buf`, under
  65536 bytes as a zip name is) and a title buffer (`tbuf`).
* `src/reader.bats`: the OPF's name (for its directory), the chapter
  path (`ch_buf`), and title and text copies (`exact`, `tbuf`).
* The EPUB file itself never stays in wasm memory: file-input keeps it
  on the JS side, it is read by ranges, and it is saved to and restored
  from IndexedDB there (`$FI.idb_put`, `$FI.idb_get`). Only a book got
  from a catalogue passes through, in an arena piece, since the bridge's
  fetch hands its bytes to wasm and `file_store` takes them back.
* Everything else (`src/bin/quire.bats`, the small buffers in
  `reader.bats`) is element ids, event names and storage keys: UI, not
  book content; it stays on `alloc`.

### Offline dictionaries

`src/dictionary.bats` keeps the StarDict dictionaries Look up reads
without a connection (`src/stardict.bats` reads their bytes: the
.ifo's keys, the headwords' order, an article as text). Like an EPUB,
a dictionary's files never enter wasm memory to stay: they are stored
from the JS side (file-input's `idb_put`) and read back by ranges. Its
import checks the .ifo and the .idx's size, every record of the .idx
and .syn, and a .dict.dz's chunk table, and stores a table ('X') of
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
is kept is a `store` (only `WebDav(url, user, password)` now): its
credentials are stored on this device only, by the store's kind
("sync" names the kind, "sync-webdav" holds the WebDAV ones), never in
the backup. The merge and its tries call only `store_read` (the file,
none yet, or a failure) and `store_write` (written, a conflict, or a
failure); WebDAV's read is a GET whose ETag is the version, its write
a PUT with If-Match (a 412 is the conflict). A sync reads, merges and
writes (again after a conflict, up to 3 tries), and only once the file
is written does this device take the merge, so a failed sync changes
nothing here. It runs when the app opens, when a book is opened, when
the page is hidden, and from the screen's Sync now (`LSync`,
`sync-screen`, opened from the library menu; Turn off goes through
Undo).

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
bytes on the JS side (file-input's `file_store`) and imports them as a
picked file is (`import_fetched`), so a book already there is asked
about. Where the fetch fails (in a browser, a page without CORS), Get
gives way to a download link (`ui_download_nn`) "then import it". A
page that cannot be read says why: not readable by a browser, not
found (404), needs a sign-in (401, 403), or not a catalogue.

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
  held apart from the settings record, which one field more would make
  too large to copy without memmove, which wasm is not given)
  is offered once a chapter of the open book has shown a ruby
  (`_ruby_seen`); Hide adds `.caf rt,.caf rtc{display:none}` to
  `style-type`. Search (`_scan_node`) does not match inside `rt`, `rtc`
  or `rp`, but counts their content nodes as render makes them, so a
  hit or an annotation after a ruby keeps its node number.

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
  images are decorative (`alt=""`); a role that needs a name (dialog,
  region, toolbar, menu, group) is given one with it.
* Each element id is made at one place in the code, no numbered id
  (`nid_make`, a prefix and a number) can spell another, and every id
  the code names is one it makes: `tests/static/ids.py` checks the
  source (the constructors, `ui_harm_id`, and helpers that pass an id
  on), in CI through `tests/static/run.sh`. An element made again to
  reset it (a search field, a file input) is made by one function,
  called at startup and at the reset.
* `ui_attr` takes a typed attribute that cannot be a name, a role or a
  style. The one inline style is a place (`ui_place`: left or width,
  in tenths of a percent up to 100%), so no inline style can set a
  colour or anything else the stylesheet proves.

Nothing is lost at a click, except by emptying the Trash:

* Removing a book moves it to the Trash (shelf 3), where it can only be
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
annotation (`src/annot.bats`) have no `#pub`. Emptying runs only as the
action handed to the dialog by `lib_ask_empty_trash`, and the dialog
runs it only from its second button's click: the dialog registers
that listener itself (`modal_listen`) and its answer function is not
exported, so other code can dismiss a dialog (`modal_dismiss`) but
never confirm one. A destructive question's title, text, button verb
and red marking all come from one `harm` value.

The overlays (the menus, book info and the reader's panels) are a
`layer` (`src/layer.bats`), whose element ids only that module knows:
they are shown and hidden only by `layer_open` and `layer_close`, which
keep the stack of open overlays, last opened on top. Escape answers the
dialog if one is open, and otherwise closes the top of that stack
(`layer_escape`), whatever opened it.

The page turns by a horizontal drag, recognized by the gestures package
(its classifier and drag state machine are proven there): bridge's
`listen_gestures` on the reader view (`OnGestures("reader")`) sends batched
pointer records, `_gesture_batch` in `src/bin/quire.bats` feeds them to
the recognizer, a pan scrolls the page with the finger (`reader_pan`), a
commit turns it and a cancel puts it back. The page (`page`, region 1,
`data-gesture-region`) takes touch and pen only, so a mouse drag still
selects text; its CSS touch-action comes from the same axes the region
is declared with (`page_turn_axes` in `src/style.bats`). A drag's end
suppresses the click the browser sends after it (`_dragged`). The shim
captures a mouse pointer only once it has moved more than 4 px: capture
at pointerdown would send the click to the reader view instead of the
button under it, so no button in the reader could be clicked.

A book is set vertically as Readium sets it, from its OPF (the book's
CSS is dropped): `vertical-rl` when its spine reads right to left and
its language is Chinese, Japanese or Korean, `vertical-lr` for
Mongolian in its script (mn-Mong) read left to right (`spine_vertical`
in `src/epub_xml.bats`, kept in `_vertical` in `src/reader.bats`).
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
