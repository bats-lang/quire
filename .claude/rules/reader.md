---
paths:
  - src/reader*.bats
  - src/settings.bats
  - src/page_size.bats
  - src/annot.bats
  - e2e/touch-selection*
  - e2e/footnotes*
  - e2e/wide*
  - e2e/stability*
  - e2e/display-size*
  - e2e/page-*
---

# The reader: notes, layout, positions and touch selection

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
the system's while a panel is open. `gen-pwa test` serves the app at a port
the kernel picks, and a bare `npx playwright test` at `QUIRE_PORT`
(`playwright.config.js`), so two runs of the suite from two checkouts
do not serve each other's build.
### Display size and the system font scale (#412)
Android's display size at its largest is a window of 320 CSS px wide at a
device pixel ratio of 3.375 (Settings clamps the smallest width to 320 dp:
AOSP's `DensityPreference`; a 1080 x 2400 Pixel is 320 x 711), where its
default is 412 x 915 at 2.625. `e2e/display-size.spec.js` walks every screen
through `fits` (`e2e/fits.js`, shared with `layout.spec.js`) and a chapter's
pages at that size.
The system font scale (130%, 200%) is not played: the WebView scales text by
it unless the embedder calls `setTextZoom` (Chromium's `AwSettings`
`updateFontScaleLocked`), which Quire and Capacitor do not, so on a device the
app's px sizes are multiplied once, by the system. Desktop Chromium's
`--blink-settings=accessibilityFontScaleFactor` is the closest engine
switch, and it was measured not to be the same: it scales the text of a plain
page (`16px` becomes `32px` at 2) through the text autosizer, which skips
narrow blocks, buttons and anything in a box with a fixed height, so it left
every size of Quire's screens, book included, unchanged. A test that passed on
it would pass for nothing, and a CSS stand-in would test the stand-in, so the
two font scale boxes of #412 stay open until a real WebView is driven.
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

* Where a place is (#383): the footer, the bar's label (`scrubber-percent`)
  and its tip say how far into the book in one wording, "6% of book"
  (`_put_book_percent`, over `_put_percent`; "<1%" once reading has begun),
  where the label said "6%" beside the footer's "6% of book". A Contents
  row and an annotation's chapter (its heading in the list, a bookmark's
  row) say where the chapter starts, by `toc_place_of` over src/locator.bats
  (the same `locator_kind` and number as a search hit; `ByPage` in a
  fixed-layout book, `book_fixed`; `locator_thousandth` is the one rule of
  the percent, shared with `_thousandth`). The Contents place is a span
  over the row's right end (`toc-place`, in `toc-line`), not text of the
  button, so a row's name stays its label. The `place_text` datatype of
  the issue's "Prevent" is not made: a flat datatype cannot carry the
  number, and the number's wording is written in one place instead
  (`_put_book_percent`, `locator_put`). An annotation's row goes to its
  place by the whole row (`.hgo`, with a chevron at its end), Delete is
  quiet (`.quiet`: no edge, muted; it has Undo, so it is no equal of Add
  note), and each style's filter has a swatch. `e2e/places.spec.js`.
  Not done, filed as a follow-up: a place for each annotation row (the
  chapter's is shown, not the annotation's own page).

* A search result row (#381) shows the hit in its snippet, the match in
  bold (`.mk`; no new colour pair), and where it is in the book. The
  snippet is cut into three spans (`search-hit-lead`, `-mark`, `-trail`)
  by `hit_at` and `hit_len`, which `hits_cons` carries with the proof
  `hit_at + hit_len <= snippet_len` (`_snippet`, `_hit_in`), so a row
  cannot take a span outside its snippet. The place is a `locator_kind`
  and a number (`src/locator.bats`, shared with Contents in #383):
  `ByPercent`, the thousandths of the book at the hit by the chapters'
  sizes and the hit's content node among the chapter's (`_hit_locator`,
  the footer's scale and `book_weights`), or `ByPage`, the spine item,
  for a fixed-layout book. A page of the current layout is not used: it
  is unknown for a chapter that is not laid out and changes with the
  font (Kindle's Location is fixed for the same reason). Each chapter's
  heading counts its hits ("3 results"). Decided by research (comment on
  #381): Material 3's list item has a trailing supporting text for a
  position; no help page of Apple Books, Kindle or Play Books documents
  the layout of its results.

* Search finds a phrase across inline elements (#437): un<span/>believable,
  a drop cap, `<em>emph</em>asis`, a phrase running out of a page-break
  span. The text of a block's inline nodes is searched as one text
  (`_scan_text`, `_find_in_block` in `src/reader.bats`): a tail of the
  last query length - 1 bytes, each with its content node and UTF-16
  offset, is searched for hits that start in it and end in the next text
  node, then that node for the hits inside it. A hit has a start and an
  end (content node, offset), which are different nodes for a phrase
  across elements, and `mark_range` takes both. Blocks (what `_tag_of`
  does not show inline), `br`, `hr` and images end a phrase; a ruby's
  `rt`, `rtc` and `rp` are neither searched nor a break, so a base reads
  on through its reading (the mark runs over the reading, which is in the
  page). Node numbering is unchanged, so annotation offsets do not move.
  Decided by research: foliate-js joins the strings of its text walker
  and maps a match to a start and an end in different entries; the Calibre
  viewer's manual documents whole-word, contains and accent/space-blind
  modes and nothing on tags; Readium's search architecture page and
  Thorium's pages document nothing on it (a search for them found
  nothing); the W3C find-text draft notes browsers rarely match across
  element boundaries and none across blocks is expected.

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
