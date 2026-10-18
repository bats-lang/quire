---
paths:
  - src/reader*.bats
  - src/settings.bats
  - src/page_size.bats
  - src/annot.bats
  - src/locator.bats
  - src/toc.bats
  - e2e/touch-selection*
  - e2e/footnotes*
  - e2e/wide*
  - e2e/stability*
  - e2e/display-size*
  - e2e/page-*
---

# The reader: notes, layout, positions and touch selection

## The place, and what keeps it

**A place is a content node and the page that holds it**, as an EPUB CFI or a
Readium locator names a text position, not a page. A layout made anew (the
counts, a resize, the type) shows the page of the node the place is kept by
(`_anchor_kept`: the one a jump took the reader to, else the first paragraph
that begins on the page last moved to) and keeps that node until the reader
moves, never the node at the top of the page it then shows, so layouts one after
another do not move the place back (quire#305, #412). Where page breaks fall is
the layout's. `e2e/stability.spec.js` changes each of theme, font, size,
spacings, margins, columns and the window (paged, two columns, scrolled,
vertical, fixed-layout), several in a row, kills the app after each, and
expects the paragraph on the page shown; a book converted from each of QLB1 to
QLB6 opens at its stored place (`e2e/legacy-library.js`).

* A chapter's pages are counted again as it is shown, for 3 s (`_settle`), and
  whenever a load of the page's fonts ends (`RFonts`): the reading face can
  arrive after those 3 s.
* **The place survives the app's bars shown or hidden** (quire#356). The app is
  drawn edge to edge, so full screen changes the reading area only through
  `env(safe-area-inset-*)`: the window does not resize and no `resize` comes.
  The activity reports the bars at each insets dispatch (`batsNative.systemBars`,
  `RSystemBars`), and when what is shown changes
  (`screen_system_bars_changed`) the chapter is laid out again once the area
  settles (`_relayout_for_bars`; it does not hide bars the system brought back).
  `e2e/layout.spec.js`, "the place stays when the reading area changes".
* Scrolled, a hand scroll within one screenful is a move too (#485): the place
  is the node now at the top of what is seen (`reader_scrolled`, `_scroll_set`),
  and a layout made anew shows that node at the top (`_show_target`).
* Keys: the arrows, Page Up and Down, Space (Shift for back), the volume keys
  when the reader chooses (the app's), MediaTrackNext and MediaTrackPrevious (a
  page turner's multimedia mode; the others in the field send the arrows or Page
  Up and Down). Enter follows the focused link and is no page key. Keys are not
  the page's while a text field or a panel has the focus; a volume key is the
  system's while a panel is open.
* `gen-pwa test` serves the app at a port the kernel picks, a bare `npx
  playwright test` at `QUIRE_PORT`, so two runs from two checkouts do not serve
  each other's build.
* Display size: Android's largest is 320 CSS px wide at ratio 3.375 (default 412
  x 915 at 2.625); `e2e/display-size.spec.js` walks every screen and a chapter's
  pages at that size. The system font scale (130%, 200%) is not played: the
  WebView applies it itself, and desktop Chromium's
  `--blink-settings=accessibilityFontScaleFactor` was measured not to scale
  Quire's screens (a test on it would pass for nothing); the two font scale
  boxes of #412 stay open until a real WebView is driven.

## Where a book opens the first time (#409)

A book never read opens where it says reading starts, not at its cover:
`toc_start_dest` (`src/toc.bats`) gives the chapter and fragment of the first
`bodymatter` entry of the nav document's `landmarks` nav (`nav_part`'s
`PartStart`), else, for EPUB 2, of the OPF's `<guide>` `<reference type="text">`
(`find_guide_text`; its fragment is not kept). A start that names no chapter of
the book gives none and the book opens at its first spine item, saying nothing.
`reader_open_at` takes `unread`, set by `_open_book` only when the place is the
first chapter's first page, no move has been dated (`place_modified` 0) and no
minute is read, so a book once read opens at its kept place. The chapters,
contents and fonts are made ready first (`_book_prepare`) so the cover is never
shown before the jump; the jump is not dated. **The landmarks are not listed in
Contents** (Apple Books lists none, Calibre's viewer none; publishers put the
contents page and index in the table of contents too). `e2e/landmarks.spec.js`
plays `e2e/landmark-books.js`; `e2e/epubcheck.spec.js` checks every book there
with epubcheck (5.2.1, pinned with its SHA-256 in `check.yml`; `EPUBCHECK_JAR`
names the jar locally): a valid book must pass, one invalid on purpose may give
only the errors its entry lists.

## Content that is wide, structured or styled

* **Note popups** (#414): a note opens as its text in one popup (`footnote`),
  gathered from the chapter's XHTML by the element's id (an `aside`, `div`, `li`
  or none, `hidden` or not); a block ends in a space, an inline element does
  not; a note over 4 KiB (`NOTE_CAPACITY`) ends in an ellipsis cut at a whole
  character. The popup has no links in it (an iBooks popover collapsed on them);
  the note's own links work where the note is, which Go to note reaches. **No
  unmarked footnote is detected** (a heuristic opens a popup for a "see 3"
  cross-reference): an unmarked link is a link. `e2e/footnotes.spec.js` plays
  `e2e/note-books.js`.
* **A table is its own scroll container** (#413, `.caf table`: `overflow: auto`),
  at most as wide as the column and as tall as the reading area, since a block
  that scrolls cannot be split between columns (a taller table lost every row
  past the page's foot). `pre` wraps (`pre-wrap`) and continues over the pages.
  Verse keeps its `<br/>` lines and no-break-space indents; indents made of the
  book's CSS are not kept (#411). `e2e/wide.spec.js` plays `e2e/wide-books.js`.
* **No part of a book's own styling reaches the page** (#411): the CSS (`<style>`,
  style attribute, `!important`, media rule) and the obsolete presentational
  attributes (`<font>`, `bgcolor`, `width`) are dropped, so a book's sizes,
  colours, margins, alignment, line height and font cannot fight the reader's
  settings, and no theme has a light slab. This is the opposite of Readium CSS
  (Thorium), on purpose. What only CSS hid (`display:none`) is shown; the
  `hidden` attribute is kept (`_pass_attrs` gives it the class
  `hidden-by-book`). `e2e/publisher.spec.js`.
* **The print page list** (#415): the Pages tab lists the entries as the book
  gives them (not sorted, duplicates kept); an entry whose chapter the book lacks
  is listed and leads nowhere (the panel stays), one whose fragment is missing
  goes to its chapter, an empty list shows no tab. The footer names the latest
  page the screen reaches from the break's `title`, else its `aria-label`
  (`epub:type="pagebreak"` or `role="doc-pagebreak"`); a break with neither
  names no page. `e2e/pagelist.spec.js`.
* **EPUB 2 packages** (#416) open as EPUB 3 ones: contents are the NCX
  (`navPoint`s in document order whatever their `playOrder`; no `content` leads
  nowhere, no label is "Untitled"), the cover is the manifest item a `<meta
  name="cover">` names, the author the first `dc:creator` as written, XHTML
  1.1's named entities are decoded, a DTBook or OEB 1 spine item is read as XML
  and its text shown, a Hebrew book whose spine names no direction reads right
  to left. A row of the contents or page list that leads nowhere keeps the panel
  up (`reader_goto_entry`, `reader_goto_page`). `e2e/epub2.spec.js`.
* **Book images** are filled once the chapter is rendered: each `src` is
  resolved against the chapter's directory, its entry read into an arena piece
  (inflated into another when deflated) and handed to the element as a blob URL;
  an SVG `<image>` the same way.
* **Ruby** is kept as itself (`_tag_of`), `rp` not shown. The Ruby row (Show /
  Hide, byte 19 of the "S2" record, `ruby` in the backup) is held apart from the
  settings record in memory, since each setter writes the record whole (quire#210),
  and offered once a chapter has shown a ruby (`_ruby_seen`); Hide adds
  `.caf rt,.caf rtc{display:none}` to `style-type`. Search (`_scan_node`) does not
  match inside `rt`, `rtc` or `rp` but counts their content nodes as render
  does, so a hit or annotation after a ruby keeps its node number.

## Where a place is, and search

* **One wording** (#383): the footer, the bar's label (`scrubber-percent`) and
  its tip say "6% of book" (`_put_book_percent`; "<1%" once reading has begun). A
  Contents row and an annotation's chapter say where the chapter starts, by
  `toc_place_of` over `src/locator.bats` (the same `locator_kind` and number as a
  search hit; `ByPage` in a fixed-layout book; `locator_thousandth` is the one
  rule of the percent). The Contents place is a span (`toc-place`), not text of
  the button, so a row's name stays its label. Not done: a place for each
  annotation row (the chapter's is shown).
* **A search result row** (#381) shows the hit in its snippet, the match in bold
  (`.mk`), cut into three spans by `hit_at` and `hit_len`, which `hits_cons`
  carries with the proof `hit_at + hit_len <= snippet_len`, so a row cannot take
  a span outside its snippet. The place is a `locator_kind`: `ByPercent` (the
  thousandths of the book at the hit, by the chapters' sizes, `_hit_locator`) or
  `ByPage`. A page of the current layout is not used: it is unknown for a chapter
  not laid out and changes with the font. Each chapter's heading counts its hits.
* **Search finds a phrase across inline elements** (#437). The text of a block's
  inline nodes is searched as one text (`_scan_text`, `_find_in_block` in
  `src/reader.bats`): a tail of the last query length - 1 bytes, each with its
  content node and UTF-16 offset, is searched for hits that start in it and end
  in the next text node. A hit has a start and an end (content node, offset),
  and `mark_range` takes both. Blocks (what `_tag_of` does not show inline),
  `br`, `hr` and images end a phrase; a ruby's `rt`, `rtc` and `rp` are neither
  searched nor a break. Node numbering is unchanged, so annotation offsets do
  not move.

## Touch selection (#428)

`e2e/touch-selection.spec.js` plays a long press, a handle drag (the browser
draws the handles, not quire), a selection across a column gap and an image, the
footnote popup, the toolbar's place and a tap that ends a selection. Decisions:

* **A selection holds the page.** While text is selected, or was when the pointer
  went down on the page (`_press_selected`; Chrome clears the selection on the
  press), a pan does nothing and a commit puts the page back
  (`_selection_holds`, `_on_gestures`).
* **A tap that began on a selection only ends it**: the click that follows turns
  nothing and brings up no bars.
* **The toolbar is for the chapter's text**: it shows only when the selection
  starts in a content node of the page (`annot_selection_in_page`); a control that
  cannot work is not shown.
* **The toolbar lies over neither the text nor the handles.** It is placed from
  the selection's rectangle on every `selectionchange` (`_toolbar_place`,
  `ui_toolbar_at`, which writes only `--seltb-top` and `--seltb-height`): above
  with an 8 px gap, else below the end handle with 20 px clearance; `.seltb`
  clamps to the window and the safe area. Wasm cannot read the inset, so a hidden
  probe (`selection-toolbar-floor`) is as tall as `max(8px, var(--safe-top))` and
  is measured.
* **A selection stops at the page**: the page does not turn while a handle is
  held at its edge; a highlight across two pages is two highlights.
* **Tapping a highlight selects it** (`annot_tap_select`, the page's click in
  `src/bin/quire.bats`; bridge's `select_range`, `clear_selection`). A tap
  between the sides' zones finds the highlight holding the tapped point
  (`caret_position_from_point`), makes its range the selection (so the one
  toolbar is up with it) and remembers it by chapter, start node and offset,
  never by index. Apple Books and the Kindle apps show a highlight's menu on a
  tap; Kobo's handles are disliked because they will not move while the menu is
  up. Highlight, Orange and Underline then replace that annotation's range when
  the selection still overlaps it (`_reshape` deletes and adds, so sync passes on
  a deletion and a new annotation; the note is kept; `undo_offer(
  HighlightRangeChanged())` puts the old range back); Note changes the range the
  same way and opens that highlight's note. After Highlight, Orange and
  Underline the selection is cleared (`annot_selection_end`). A `select_range`
  that is refused or finds no element is said (`HighlightNotSelected`, and
  `SelectionNotEnded`).
