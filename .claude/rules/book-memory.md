---
paths:
  - src/pages.bats
  - src/book.bats
  - src/reader.bats
  - src/xhtml_parse.bats
  - e2e/pathological*.js
  - e2e/giant-text*.js
---

# Book memory, arenas and the pathological structure

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
  Every later state of the same kind is an attribute set by the layer
  (`data-below`, `data-menu`, `data-veil`), never a `:has()` on the root:
  `tests/static/has_root.py` fails one (#538; #556's two rules were found
  by it when its queue run met them).
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
* **Close does not wait for the layout, and the layout can outlast a check
  (#522).** Choosing Two on the megabyte word and pressing Escape: the
  dialog's `data-hide` flips within milliseconds of the key (measured with a
  MutationObserver and a longtask observer, then with Chrome's CPU throttled
  25 times: the flip came 6 ms before a single 15.7 s task, the columns' layout,
  which the click made dirty and Chrome does in the next frame). Playwright's
  `toBeHidden` needs the page laid out to say so, so on a loaded runner it
  waited behind that task and failed at 15 s twice (#518, #533). So the
  app's part is asserted by its attribute (`arrange`), the dialog gone from the
  screen waits as long as the layout it follows (`slow`), and a test dispatches
  the click on Two and the Escape in one script, so no frame lies between them,
  and finds the dialog already hidden. The 15 s is not raised: the hide is
  checked with no layout in the way.
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
  bytes (`cut_find`, src/cut.bats; a run with no white space is cut at a character, as
  before). Complexity: the frame of a run of n columns was O(n squared)
  and is O(n) in the number of pieces; opening the megabyte word on a
  390 px phone went from 17 s (Two) to 1.5 s, and the opening to 1 s. A
  text node over 64 KiB in mixed content breaks its line at each piece (a
  paragraph break appearing in a 64 KiB run is the price; search counts
  pieces with the same `cut_find`, so its node numbers agree). A stored
  note or highlight in such a text is a piece's content node and a UTF-16
  offset in that piece's text (bridge's `get_selection_range` gives offsets
  into the text of the element with the id, which is the piece), and the cut
  is a function of the text alone, so a place stored by this build is found
  exactly by it again, after a reload, a restored backup and a sync
  (`e2e/giant-text-highlights.spec.js`: highlights at the end of a piece, at
  the start of the next, across a cut and inside a third, paged, scrolled and
  in two columns, with accents and an emoji in the words; a last test restores
  places stored by this build and they must paint the same words, so a
  changed cut fails there). The cut is part of the format of a stored place:
  changing `cut_find` moves the places stored in the pieces after the first
  of a text over 64 KiB (the first starts where the text does) and needs a
  version of the annotations' record to translate by. A place stored by a
  build before #423 (pieces cut at a character, not at white space) is read
  against these pieces and may land up to 512 bytes per piece from where it
  was made, in the second and later pieces of such a text; no version of the
  record says which cut a place was stored with. Making places independent
  of the cut (the pieces as `data-part` parts of one content node, as the
  digits of vertical text are) was weighed and not taken: one content node
  per text would make the reading place, a content node and the page that
  holds it, as coarse as the whole text (a megabyte paragraph one place), and
  search and read aloud would need the UTF-16 length of the pieces before
  one for their offsets (#470). The open budget the spec
  asserts (`expectOpenBudget`): the time from the card's tap to the
  chapter's indicator, and from the choice of Two, Scroll or One to its
  page indicator, is at most 3 times Chrome's own time to lay out and
  draw a copy of that DOM in that window and arrangement (`bareFrameMs`:
  the copy is put beside the page, laid out, drawn for two frames and
  removed, so a slow runner is slow for both), plus 1 s for what is not
  layout. Measured (phone, this machine): the megabyte word opens in 1.0
  s against 0.8, Two in 1.5 against 1.8, 10,000 paragraphs open in 2.3
  against 1.7. No timeout was raised to get there.
* **The cut is a function of the text's cells, proved (#568).** The three
  walks of a chapter's text (render's `_text_spans`, search's `_scan_text`,
  read aloud's `_runs_text`, and the blank or math text each skips with
  `_skip_spans` and `_text_count`) number a text's pieces by one rule,
  `src/cut.bats`, stated over the cells of the array the text is read from
  (array's `cborrow`, whose `cborrow_get` gives `NTH(cs, i, v)` with each
  byte): `BREAKBACK(cs, offset, at, floor, back)` (the cut after the last
  space, tab or line feed at or before a cell, looking back no further than
  a floor), `CUTC(cs, offset, text_len, cut)` (the first piece's length:
  after that white space in the last 512 bytes, else the longest prefix
  that ends before a UTF-8 character's start) and `PIECES(cs, offset,
  text_len, count)` (the text is count pieces, each cut off by `CUTC`).
  Each constructor takes the `NTH` of the cells it was decided from, so
  none is made over cells other than the ones read
  (`tests/static/reject/cut-claimed-over-other-cells`,
  `cut-break-after-a-byte-that-is-not-white`, `cut-break-at-another-cell`,
  `pieces-counted-over-other-cells`, `pieces-forged-cut`), and each is
  functional (`breakback_functional`, `cutc_functional`,
  `pieces_functional`, by induction, with array's `nth_functional`): two
  cuts, or two counts, of the same cells and offset are equal
  (`reject/cut-two-lengths-of-the-same-cells`,
  `pieces-two-counts-of-the-same-cells`, `accept/cut-same-cells-same-count`).
  `cut_find` and `pieces_find` read the cells and return those proofs; the
  walkers take `bytes: !cborrow(l, n, cs)` beside the plain `data: !borrow`,
  and an `<img>`'s over-long alt text is cut by `cut_find` too, so no walk
  steps by another rule (the 65533 step of #568's first part is gone). A
  chapter's piece is lent for this at each load (render, facing page,
  search, the annotations' node count, read aloud): array's `barr_of_arrx`
  gives the cells and keeps the piece's owner, `barr_freeze` the
  `cfrozen`/`cborrow`, `cborrow_view` (array 2026.10.15.3267, array#47) the
  plain borrow of the same bytes that `xhtml_parse`, `_load_images` and the
  page read through, counted in the freeze so `barr_thaw` is refused while
  the view is out (`reject/cut-view-out-at-thaw`), and the view is given
  back, then the cells, before the thaw and `barr_to_arrx`
  (`accept/cut-found-from-the-cells`). `_utf8_start` no longer calls arith's
  `band`: a byte starts a character when it is under 128 or at least 192.
  **Proved**: that the cut, and the count of pieces, that render, search and
  read aloud take are the one relation of the cells they walk, and that two
  walks over the same cells, or the same cborrow, cannot get two. **Tested,
  not proved**: that the three walks read the same bytes. Render, search and
  read aloud each decode the chapter from the compressed entry on their own
  (separate pieces, so separate existential cells `cs`), and nothing in the
  types says that inflate, the CRC check and `_text_of_content` give the same
  bytes each time: that needs inflate (the zip package) and the text
  conversion (`src/text_encoding.bats`) as proved relations of their input
  cells, with functional lemmas, which they are not yet. The proof is owed
  (#608; no trusted primitive is needed or allowed), and until it is proved
  it is tested (`e2e/giant-text-highlights.spec.js`,
  `e2e/pathological.spec.js`, `e2e/search.spec.js`). **Trusted** (array's, tested there): the unsafe
  core of `barr_of_arrx`, `cborrow_view` (an identity on the pointer) and
  `cborrow_get` (reads the byte it says). The functional lemmas and the
  relations are audited by the mutation check (`mutation_check.py`, GMP):
  every statement of `breakback_functional`, `cutc_functional` and
  `pieces_functional` made false is rejected; the two lemmas `white_not_white`
  and `starts_not_continues`, which prove `1 == 0` from a pair that cannot
  both hold (a byte that is white space and is not; one that starts a
  character and continues one), are accepted when mutated to any other
  statement, as every statement is true of an impossible pair, and each of
  their premises is satisfiable alone. `cut.bats` checks in 2 s.
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
