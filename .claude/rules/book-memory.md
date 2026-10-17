---
paths:
  - src/pages.bats
  - src/book.bats
  - src/reader.bats
  - src/xhtml_parse.bats
  - src/cut.bats
  - e2e/pathological*.js
  - e2e/giant-text*.js
---

# Book memory, arenas and the pathological structure

## To do: book memory in a rolling window of page arenas

Partly done: the window exists (`src/pages.bats`), and the buffers a chapter or
image is parsed from come from the current page's arena. The rest is the
intended design.

Everything that belongs to a book's content (chapter text, pictures, per-page
layout data) is allocated from arenas (array's `arena_create` / `arena_alloc`),
not with `alloc`, which is bounded at 1 MiB on purpose to limit fragmentation
(array's CLAUDE.md).

* One arena per page, sized for a page with generous limits for images.
* Five arenas live at a time: the current page, 2 before, 2 after. Turning
  forward releases the arena of the page now 3 back and prepares the one now 2
  ahead (back is the mirror image).
* Arenas are created and destroyed whole and never reused piecemeal.

The point of ATS2 here is that the discipline is checked at compile time: a piece
that does not fit its page's arena does not type-check; a page's pieces cannot be
freed on their own or given back to another page's arena; an arena cannot be
released while a piece is in use. The window itself should be in the types too:
the reader state holds exactly the five arenas, indexed by page number.

### The window today

`src/pages.bats`: `page_arena(page, pages)` is the arena of that page of a
chapter, with no piece out, and exists only for `0 <= page < pages`;
`window(page, pages)` holds exactly the arenas of pages page - 2 to page + 2 (a
page is a screenful when scrolled); `window_forward` turns it into
`window(page + 1, pages)` by releasing page - 2's arena and making page + 3's
(`window_back` is the mirror image), so keeping any other arena does not
type-check. Each arena is 4 MiB (`PAGE_BYTES`).

The reader's window lives in a `ref` taken out and put back with `ref_exch_elt`
(it is linear). `_show_page` moves it to the page shown: one page on rotates it,
any other move (a jump, a new chapter, a new page count) releases it and makes
it anew; the library releases it (`window_close`).

A buffer a book's content is parsed from (`piece_new` in `src/book.bats`) is a
piece of the current page's arena when it fits (`page_lend`); the arena leaves
the window while the piece is out (its slot is `Lent`), so the window's arena
never has a piece out, and `page_give_back` returns it, or releases it when the
window has moved on. With no window yet (the first chapter's load) or no room,
the piece is the one piece of an arena of its own; `piece_owner` says which, so
`piece_free` gives it back to the right one. A piece lives only while it is
parsed or written, except the script read aloud, which outlives page turns, and
a narrated chapter's clip table (`clip_table`, `src/overlay.bats`): the one
piece of an arena of its own, at most 1 MiB, kept until the next chapter is
rendered.

**Where content is allocated**: everything read from an archive, a backup, a
dictionary, a catalogue, the sync file (refused over 16 MiB, `SYNC_MAX_BYTES`),
read aloud's script and a narrated chapter's SMIL is a `piece`. `alloc` holds
only the archive's tail and local headers while a book is opened, its central
directory (at most 1 MiB, kept for entry names, `book_index_make`), and small
buffers: element ids, event names, storage keys, paths, titles. The EPUB file
never stays in wasm memory (bridge's file module keeps it on the JS side, read
by ranges; only a book got from a catalogue passes through, in a piece).

## Pathological structure (#423)

`e2e/pathological.spec.js` walks KOReader's slow shapes
(`e2e/pathological-books.js`, each checked by epubcheck): a table cell of many
pages, a 5 MB single-file book, a thousand nested elements, ten thousand short
paragraphs, a megabyte without a space. It measures a pathological chapter
against a plain one of the same length in the same page, so a slower machine
slows both. What it settled:

* **A wide chapter was never shown.** xml-tree's `_parse_nodes` uses a stack frame
  per sibling and wasm's stack is 1 MiB, so about 9000 siblings overflowed it
  silently (a blank reader, no banner). `src/xhtml_parse.bats` is xml-tree's parser
  with one change: a sibling list is collected in a tail-recursive loop, so the
  stack holds the document's depth, not its width. Every chapter parse uses it
  (the OPF and SMIL still use xml-tree's). Tested with 9000 and 30,000 paragraphs,
  not proved. It belongs upstream (bats-lang/xml-tree); this file then goes.
  Truncating a chapter at a guessed count was rejected: it hides text that shows.
* **A run with no break opportunity** uses `overflow-wrap: break-word` on `.caf`;
  `anywhere` made a table whose cell holds a long run wrap instead of scroll
  (#413, `e2e/wide.spec.js` failed).
* **A page turn must not cost time in proportion to the chapter.** Blink
  re-evaluates a `:has()` whose subject is an ancestor of every change over the
  subject's whole subtree, so `#bats-root:has(...) .banner` cost 16 to 27 ms per
  chrome change on a 30,000-node chapter. The banner's place is a class the views
  set (`banner_place_set`, `src/notice.bats`); later states of the same kind are
  attributes set by the layer (`data-below`, `data-menu`, `data-veil`), **never a
  `:has()` on the root** (`tests/static/has_root.py` fails one, #538). What is left
  of a turn on a huge chapter is the browser's (the hover hit test, the prepaint
  of the slid copy), so a chapter too big to slide a copy of turns at once
  (`_chapter_heavy`) and keeps no copy ahead (`_copy_stale`); RAIL's 100 ms to
  respond is the reason for the threshold.
* **Close does not wait for the layout** (#522): Chrome lays out the columns in the
  next frame, as one task of up to 15 s on the megabyte word, and Playwright's
  `toBeHidden` waits behind it. So the app's part is asserted by its attribute
  (`arrange`), the dialog gone waits as long as the layout (`slow`), and a test
  dispatches the click on Two and the Escape in one script. The 15 s is not raised.
* **The anchor is found by binary search, not by hit test** (`_first_on_or_after`
  in `_anchor_now`): a hit test in a multicolumn chapter costs in proportion to the
  fragments it walks. Content nodes are numbered in document order and flow in it,
  so where they start grows with the number (`_page_axis` says which way);
  undrawn ones are stepped over (at most 64 in a row); when no node starts on the
  page the anchor is the last drawn node before the first that starts after it. A
  fixed page keeps the hit test (`_anchor_hit`): its nodes are few and a spread's
  facing page is numbered after it. `_show_page_down` asks once per page shown.
* **A giant run of text was drawn in time quadratic in its columns** (the megabyte
  word, 17 s to open on a phone): it is Chrome's cost per inline run across columns
  (a plain HTML page did the same; no CSS tried changed it). So the app gives Chrome
  no run longer than a piece: a text of 64 KiB or more is cut into pieces (class
  `run`, shown as blocks, `.caf .run`) after the last white space in their last 512
  bytes (`cut_find`, `src/cut.bats`; with none, at a character). A text over 64 KiB
  in mixed content breaks its line at each piece; search counts pieces with the
  same `cut_find`.
  * **The cut is part of the format of a stored place**: a note or highlight in
    such a text is a piece's content node and a UTF-16 offset in that piece. Changing
    `cut_find` moves places stored in the pieces after the first and needs a version
    of the annotations' record to translate by. A place stored before #423 may land
    up to 512 bytes per piece off. Making places independent of the cut (pieces as
    `data-part` parts of one node) was weighed and not taken: the reading place
    would be as coarse as the whole text, and search and read aloud would need the
    UTF-16 length of the pieces before one (#470).
    `e2e/giant-text-highlights.spec.js` fails a changed cut.
  * **The open budget** (`expectOpenBudget`): the time from the card's tap to the
    chapter's indicator, and from the choice of Two, Scroll or One to its page
    indicator, is at most 3 times Chrome's own time to lay out and draw a copy of
    that DOM in that window (`bareFrameMs`) plus 1 s. No timeout was raised to get
    there.
* **The cut is proved a function of the text's cells** (#568). The walks of a
  chapter's text (render's `_text_spans`, search's `_scan_text`, read aloud's
  `_runs_text`, and `_skip_spans` / `_text_count`) number a text's pieces by one
  rule, `src/cut.bats`, stated over the cells of the array read from (array's
  `cborrow`, `cborrow_get` giving `NTH(cs, i, v)`): `BREAKBACK`, `CUTC` and
  `PIECES`, each taking the `NTH` of the cells it was decided from, and each
  functional (`breakback_functional`, `cutc_functional`, `pieces_functional`).
  `tests/static/reject/cut-*` and `pieces-*` reject a cut claimed over other cells,
  a forged cut, and two counts of the same cells. `cut_find` and `pieces_find` read
  the cells and return those proofs; a chapter's piece is lent for this at each load
  (`barr_of_arrx`, `barr_freeze`, `cborrow_view`, array#47).
  * **Proved**: the cut and count that render, search and read aloud take are the
    one relation of the cells they walk. **Tested, not proved**: that the three walks
    read the same bytes (each decodes the chapter from the compressed entry on its
    own, and inflate, the CRC check and `_text_of_content` are not yet proved
    relations of their input cells). The proof is owed (#608; no trusted primitive
    is needed or allowed); until then `e2e/giant-text-highlights.spec.js`,
    `pathological.spec.js` and `search.spec.js` test it.
  * Trusted (array's, tested there): the unsafe core of `barr_of_arrx`,
    `cborrow_view`, `cborrow_get`. The lemmas are audited by the mutation check;
    `white_not_white` and `starts_not_continues` prove `1 == 0` from an impossible
    pair, so they are accepted when mutated to any statement, and each of their
    premises is satisfiable alone.
* **The spec's long chapters run without Playwright's trace and screenshots**
  (`heavy` in `e2e/pathological.spec.js`): its snapshotter walks every node at every
  action (2 to 3 s on 30,000 nodes). The stall watch stays on.
  `e2e/page-margins.js` clips a line to the scroll containers inside the page.
* **A table is one box on one page** (#413): the chapter with a 200-paragraph cell is
  fewer pages than the plain one and the cell scrolls inside its table.
