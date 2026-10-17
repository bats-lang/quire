---
paths:
  - src/library*.bats
  - src/app.bats
  - src/bin/quire.bats
  - src/layer.bats
  - e2e/library*
  - e2e/walk.js
  - e2e/settings-screen*
  - e2e/back*
  - e2e/layout*
---

# The library screen

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
  shelf's screen (the other shelves are one entry away). Empty Trash is on
  the Trash's screen, beside what it holds, as Drive's Trash has its Empty
  trash (quire#385). A book opened from a shelf's screen closes to
  the library (`_show_reader`). A shelf's rows offer Unhide, Unarchive (it
  says to import the book's file again: archiving drops the file) and
  Restore (Trash). A row's actions open on its More button and on a long
  press or right click (`contextmenu`), as before.
* **A book's menu is grouped, and Book info reads** (quire#386; Material
  3: "Vertical menu items can be grouped by adding a divider or small
  gap"). The menu is Read (Continue once opened, Read again once
  finished: `lib_reading_state`, the one rule behind the card's word and
  the filter chips; none for a book in the Trash or archived), Book info,
  Collections, a divider (`role=separator`, `.msep`), Hide, Archive, and
  Move to Trash, which is made by `ui_removal_item` from a `removal` (as
  `ui_harm_button` is from a `harm`) and drawn by the stylesheet's
  `[data-removal]` rule with a line above it; it is not red, since Undo
  and Restore bring the book back. Book info has the same Read as its
  primary button, Move to Trash apart from Hide and Archive
  (`ui_removal_button`), and the author in `.info-author`, proven on the
  page's ground (`.ba` is proven on the card's: reusing it left a strip of
  the card's colour behind the author). `strayGrounds` in
  `e2e/controls-shown.js` fails a text element whose own ground is not the
  one behind it unless it is a control or a card. A book whose metadata
  says nothing of its accessibility is told so once ("This book gives no
  accessibility information.") instead of a "No information" line under
  each heading.
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
* **The book menu button is one box in both views** (#495): a 48 by 48
  square, `align-self: center` in the list (the card row stretches its
  children, which made it as tall as the card) and over the cover's corner
  in the grid; Material 3's trailing icon button is a 48dp target round a
  24dp glyph, centred in a one- or two-line list item and in the corner of a
  media card, never stretched. `cardMoreBoxes` (`e2e/controls-shown.js`)
  measures it, and `e2e/layout.spec.js` fails if the list's and the grid's
  boxes differ.
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
scrolls the copy to the place and shows it (the copy's images share the page's
blob URLs, which bridge revokes only once no image still loading holds them,
quire#532, `e2e/progress.spec.js`): on a 300 KB chapter its
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

A book's picture is shown full screen in the viewer (#382; opened by a
double tap on it or a long press, #365; `src/image_viewer.bats`). It is
fitted whole to the screen on the bars' dark ground (`RoleBar`, dark in
every theme; a picture is best seen on a dark ground, and the Close and
Zoom buttons are `RoleBarText` on `RoleBarHigh`, proven), not shown at its
inline size. The picture's box is the scroller's own size (`ui_picture_box`,
the one inline style besides a place and a fixed page's box:
`ui_fixed_box_n` with literal ids) at a zoom in thousandths of the fit;
`object-fit: contain` fits the picture in it, so the fit needs no
knowledge of the picture's size, and a zoomed box is larger than the
scroller, which scrolls it: a pan is a scroll (`ui_scroll_set`). The zoom
is held to 1 to 4 times the fit by `viewer_clamp`, whose result type is
`[zoom | 1000 <= zoom <= 4000]`, and every zoom reaching the page passes
through it (a zoom of 0 or a box past `ui_fixed_box_n`'s limits does not
type-check). A pinch is the gestures package's own (`GPinch`, a pinch
region 2 on the scroller, `image_zoom_axes`: none, so its `touch-action`
is none and the browser's pinch is not used; the scale is of the zoom
the pinch began at, the point of the picture under the fingers' middle
stays under it); one finger's drag is the viewer's own, read from the
raw pointer records (`viewer_pointer`: nothing to classify, every move
is a pan, a mouse is not dragged: its wheel and scroll bars are), and a
second finger ends it. A double tap (`dblclick`) zooms to 2.5 times the
fit where it is made, and the next goes back to the fit; it is instant,
so it is the same under reduced motion. The Zoom in and Zoom out buttons
(1.5 times, about the middle) are the single-pointer way (WCAG 2.5.1).
Resizing fits the picture again. By research (issue #382): Apple Books
and Kobo zoom a picture by pinch and double tap; PhotoSwipe, the web's
usual viewer, fits the picture, zooms to 2.5 times the fit on a double
tap and at most 4 times the fit (photoswipe.com/adjusting-zoom-level).
`e2e/image-viewer.spec.js` plays each, the pinch and the pan as touch
pointer events on the scroller.

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
(`spacing_rules` in `src/adaptive_rules.bats`): that side's inset and the spacing
scale's least inset beyond it, so none of its controls or text comes
near a system bar (#341, `e2e/safe-area.spec.js`). A spread's columns are at least
40vw, so two fit beside a cutout. A sheet's height is in `dvh`, and the
typography sheet's head (`.shead`), with Close, is held at its top as
it scrolls. `e2e/layout.spec.js` sets the insets through DevTools.

The visible reading area is given once, as the reader view's (`.rv`)
variables in `src/reader_rules.bats` (#296): the running footer sits 8px above
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

A bookmarked page shows its mark once the bars hide (#388): a ribbon
(`bookmark-mark`, `.bmk`, clipped by `clip-path`) in the page's top-right
corner, inside the `--page-top` band, in the accent (proven on the ground as
text is, `S_accent_bg`), shown by `.chrome-off .bmk-on`; `annot_star`, the one
place the bookmark's state reaches the screen, matches a `bookmark_state`
(`Marked | Unmarked`) to set the star and the mark together. Kindle and Kobo
draw theirs in that corner; with the bars up the star says it. The bottom bar
has Previous chapter and Next chapter beside the page turns (`chapter-previous`,
`chapter-next`, `reader_chapter_step`), shown where there is a chapter to go
to and not in a fixed-layout book (its chapters are its pages), following the
reading direction as the page turns do (`.bot.rtl` orders): the next chapter is
two taps from the page, three through Contents. `e2e/page-marks.spec.js`.

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
Latin and digits are turned, the default `text-orientation:mixed` (JLREQ: an English word is rotated 90 degrees; only a short number stands upright, as tate-chu-yoko, usually a number of two digits; no browser supports `text-combine-upright: digits`, and Chromium's `all` needs the run in an element of its own: see Text parts below), and `_page_axis` (`Across`, `AcrossBack`, `Down`) is what counts, finds and
shows pages, by scrollTop for `Down`. Such a book is always paged, one
column a screen, a drag does not follow the finger (a committed one
turns the page), and the settings of the page's layout and of its
words' spacing and breaking are hidden while it is open. A paragraph's
margins are logical (`margin-block`, and the Paragraph spacing setting
as `margin-block-end`), so set vertically the space after it is beside
it and its lines keep their length; that row stays. Taps, keys and
swipes keep the meaning of a book read right to left.

**Text parts (#391).** Set vertically, each run of one or two ASCII digits
in a text (`_tcy_find`: not one in a longer number, not one against a
Latin letter, which is a word, and not a digit of a character reference)
is wrapped by `_tcy_parts` in a *text part*, a span of the class `tcy`
that the stylesheet sets `text-combine-upright: all` (inside
`.caf.vertical` and `.caf.vertical-lr` only, so no horizontal book has the
rule), the text between the runs in parts of their own. A part has the id
`t<number>` and the attribute `data-part` (`_part_add`), and it takes no
content node number: the content node is still one span, `c<N>`, whose
text is the whole text, so a note, a highlight, a place, a search hit and
read aloud keep their node numbers and UTF-16 offsets (the numbering
code in search, read aloud and `_skip_spans` is unchanged, and a search
for "第1章" still matches across the parts). Bridge's `data-part` is
what makes that so: a position in a part is an offset into the text of
its *owner*, the nearest ancestor with no `data-part`, and a click's
target or the element at a point is the owner (bridge's `ownerOf`,
`textPointAt`, `textOffsetOf`; `mark_range`, `select_range`,
`measure_text_offset`, `caret_position_from_point`,
`get_selection_range`, `element_at_point` and an event's target). By
research: JLREQ sets a number of 1-2 digits upright in one cell and a
longer one turned (an English word is turned too); CSS Writing Modes 3
has `text-combine-upright: all` for an element and `digits <n>` which no
browser has (MDN); Manabi Reader normalises a book's legacy
`-webkit-text-combine` the same way; a book's own CSS is dropped here,
so there is none to honour. Not wrapped: a number of 3 or more digits, a
decimal's digits are each a run ("3.5" is two), and a fullwidth digit
is upright already. Chrome scales a run to its cell by the font it was laid out in and does not do it again when the reading face arrives after, so a page opened again looked different from the page it was (`e2e/relaunch.spec.js`): a vertical book switches combining off and on again (`_tcy_refit`, the style `style-tcy`, a layout between) as a chapter is rendered, in `_relayout` and 150 ms after a face arrives (the browser lays text out with the face after the event). `e2e/vertical.spec.js` plays it, and bridge's
`tests/dynamic/decoders` the offsets and targets.

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
runs (10 s, `BACK_SHOWN`) the button goes but the positions are kept
(`PsKept`, #384: Apple Books reaches "previous location" from a control
that does not expire, KOReader keeps it until used), unless a later jump
has armed a later timeout. It goes sooner when a page is turned or the
bars are brought up (`_chrome_set`), also keeping them; Contents shows
"Back to <chapter> · page N" (`contents-back`) while a position is kept,
and pressing it pops it as the button does. Opening or closing a book
forgets them (`reader_stack_clear`). The first-book hint (#384) says
both gestures (`gesture`: `TapSides | TapMiddle`, `gesture_hint`), lies
in the band the text keeps clear of (`hint_band`: `TopBand | BottomBand`,
no centre case) and is up for 8 s after the bars first hide.
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
