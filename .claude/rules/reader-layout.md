---
paths:
  - src/reader*.bats
  - src/reading_ruler.bats
  - src/ruler_rules.bats
  - e2e/reading-ruler*
  - src/settings.bats
  - src/image_viewer.bats
  - src/page_size.bats
  - src/epub_xml.bats
  - src/bin/quire.bats
  - e2e/page-turn*
  - e2e/image-viewer*
  - e2e/vertical*
  - e2e/spreads*
  - e2e/page-marks*
  - e2e/page-margins*
  - e2e/safe-area*
  - e2e/fractional-window*
  - e2e/relaunch*
---

# The reader's chrome: gestures, page turns, reading area, writing modes and spreads

## Gestures and page turns

* **The page turns by a horizontal drag**, recognized by the gestures package
  (its classifier and state machine are proven there). Bridge's `listen_pointer`
  on the reader view sends each raw pointer record; `_gesture_record`
  (`src/bin/quire.bats`) hands it to the package's pointer source
  (`gestures_raw`), which answers with gesture events and actions
  (`CapturePointer`, done by `ui_pointer_capture`; `WantFrame`, bridge's
  `animation_frame` then `gestures_frame`, at most `FRAME_ROUNDS` in a row). A
  pan scrolls the page with the finger (`reader_pan`), a commit turns it, a
  cancel puts it back. The page (`page`, region 1) takes touch and pen only, so
  a mouse drag still selects text; its CSS `touch-action` comes from the same
  axes the region is declared with (`page_turn_axes` in `src/style.bats`). A
  drag's end suppresses the click that follows (`_dragged`). The source captures
  a mouse pointer only after 4 px of movement: capture at pointerdown would send
  the click to the reader view instead of the button under it.
* **Every page turn is animated** (#246): tap, key, button, reading aloud, drag.
  A copy of the page is kept in an overlay (`page-turn`, idle: laid out but
  `visibility:hidden`), made by `ui_copy_inert` (bridge's CLONE_NODE, then the
  copy's tabindex and gesture region removed, `inert` set: quire's policy, not
  bridge's) and again `COPY_SETTLE_MS` after the page last changed, so a turn only
  scrolls the copy to the place and shows it (the copy's images share the page's
  blob URLs, quire#532). A turn shows only a `fresh_copy`, which only
  `_copy_ready` gives, so no turn shows a chapter or a layout gone. The page
  itself goes to the incoming page at once, so the place, the indicator and the
  arenas' window move as before. 280 ms, eased out (`e2e/page-turn.spec.js` budgets the first frame). Under
  `prefers-reduced-motion: reduce`, and in a chapter too big to slide a copy of
  (`_chapter_heavy`, #423: 6000 content nodes or 600 KB), a turn is instant and
  no copy is kept ahead.
* The turn is a `turn_cell` (`TurnStill`, `TurnHeld`, `TurnReturning`,
  `TurnWaiting`, `TurnSliding`), each holding a linear `turn_sheet(HELD | SLID)`
  whose constructors are local: a sliding sheet ends only by `_sheet_lift`, a
  held one only by `_sheet_put_back` or `_sheet_commit`, so no turn, interrupted
  or late, leaves the copy over the page or the page between two places
  (`tests/static` `page-turn-*`). The shade's levels are proven in each theme
  (`VEILED`, written by `scripts/gen-harmony.py`): under it the text keeps 7:1.

## The reading area

* The reader is fixed to the window (`.rv`, not `vh`, which an Android WebView can
  make taller than what it shows), and the page keeps out of the safe area on
  every side (#275): paddings above and below (`env(safe-area-inset-top)`,
  `-bottom`), margins at the sides, so no text is under a camera cutout in either
  orientation. Every other screen, panel, sheet, dialog, toast and bar pads the
  sides it can touch by `--safe-*` (`spacing_rules` in
  `src/adaptive_rules.bats`; #341, `e2e/safe-area.spec.js`). A spread's columns
  are at least 40vw. `e2e/layout.spec.js` sets the insets through DevTools.
* **The visible reading area is given once**, as `.rv`'s variables in
  `src/reader_rules.bats` (#296): the footer sits 8px above the bottom inset
  (`--footer-bottom`), 16px tall (`--footer-height`), and the page's paddings
  (`--page-top`, `--page-bottom`) keep the text half a line (at least 12px) clear
  of the footer and the top inset. A column is the page's height less those
  paddings; a vertical page's gap and a picture's largest height are the same
  paddings. Pages are counted across by the page's scroll width. Scrolled, the
  same variables are the page's margins (`_put_scrolled` in `src/settings.bats`),
  so text is clipped there, never drawn under the footer or a system bar, and a
  turn (`_step`) scrolls the area's height less one line.
  The e2e fixture measures this (`e2e/page-margins.js`) at the end of every test in the
  phone-sized projects (`MARGIN_PROJECTS`) whenever a reflowed page is shown with the bars down.
* **The reader's bottom bar follows the reading direction** (quire#359): the
  book's `reading_direction` (`LeftToRight | RightToLeft`, `_direction_set`)
  gives the bar (`.bot.rtl`) and the scrubber (`.trk.rtl`) their class and swaps
  the page-turn buttons' arrows; every drawing along the reading axis takes
  `_drawn_at`, and a drag's x is turned back by `_track_at`. `expectBarFollows`
  (`e2e/helpers.js`) checks it; `vertical.spec.js` needs a Japanese font (CI installs
  `fonts-noto-cjk`).
* **A bookmarked page shows its mark once the bars hide** (#388): a ribbon
  (`bookmark-mark`, `.bmk`) in the page's top-right corner, in the accent (proven
  as text is, `S_accent_bg`); `annot_star`, the one place the bookmark's state
  reaches the screen, matches a `bookmark_state` to set the star and the mark
  together. The bottom bar has Previous chapter and Next chapter beside the page
  turns (`reader_chapter_step`), not in a fixed-layout book. `e2e/page-marks.spec.js`.
* **The page's width and height are whole pixels** (`page_extent`; see
  `interface.md`); `e2e/fractional-window.spec.js` walks a fractional window.
* **The back button a jump leaves never stays up**: `ps_cell` holds the positions
  it offers, and its only shown state, `PsShown`, needs a proof `TIMED(g)` that a
  timeout numbered g is armed; `TIMED`'s constructor is local to `_timed_arm`, and
  `_ps_put` is the only code that shows or hides the button. When the timeout runs
  (10 s, `BACK_SHOWN`) the button goes but the positions are kept (`PsKept`, #384:
  Apple Books and KOReader keep "previous location"), unless a later jump armed a
  later timeout. Contents shows "Back to <chapter> · page N" (`contents-back`)
  while a position is kept. Opening or closing a book forgets them
  (`reader_stack_clear`). The first-book hint says both gestures
  (`gesture_hint`), lies in the band the text keeps clear of (`hint_band`) and is
  up for 8 s after the bars first hide. `tests/static` holds code that must not
  type-check (a forged `TIMED`, another timeout's proof) and code that must
  (`_back_offer`).

## The picture viewer (#382)

A book's picture is shown full screen (`src/image_viewer.bats`; a double tap on it
or a long press, #365) fitted whole on the bars' dark ground (`RoleBar`, dark in
every theme; its buttons `RoleBarText` on `RoleBarHigh`, proven). The picture's
box is the scroller's own size (`ui_picture_box`) at a zoom in thousandths of the
fit; `object-fit: contain` fits it, so the fit needs no knowledge of the picture's
size, and a pan is a scroll (`ui_scroll_set`). **The zoom is held to 1 to 4 times
the fit by `viewer_clamp`** (`[zoom | 1000 <= zoom <= 4000]`) and every zoom
reaching the page passes through it. A pinch is the gestures package's own
(`GPinch`, region 2, `image_zoom_axes` none, so the browser's pinch is not used);
one finger's drag is the viewer's own (`viewer_pointer`; a second finger ends it;
a mouse is not dragged, its wheel and scroll bars are). A double tap zooms to 2.5
times the fit where it is made, the next goes back; Zoom in and Zoom out buttons
(1.5 times) are the single-pointer way (WCAG 2.5.1). (PhotoSwipe: 2.5 times on a double tap, at most 4.) `e2e/image-viewer.spec.js`.

## The reading settings sheet (#288, #301)

`typography-panel` (the bottom bar's Reading settings) holds every reading setting
in tabs within one sheet: Look (theme, font, size, spacings, ruby, dimmed images),
Page (pages or scrolled, pages on screen, margins, justify, hyphenation, the
screen), Turning (Tap to turn pages, each with a drawing of its zones, mirrored
for a book read right to left; in the app, Turn pages with volume keys) and Read
aloud (where the platform speaks or the book is narrated), with Reset to defaults
under them all. The tabs (`sheet_tab`) follow WAI-ARIA's tabs pattern
(`_sheet_tab_key`); the sheet opens on Look and its head stays at its top. **The
sheet is as tall as its tallest tab**: the panels lie in one grid cell
(`.tabpanels`), the ones not chosen `.unchosen` (`visibility: hidden`), so
switching tabs moves neither the sheet nor its tabs. Their controls are one `typography_control` datatype.

## Split screen and foldables (#412)

* **The window is the reader's size, whatever it is.** A split-screen half
  (412 by 450 CSS px: the android project's width at half its height) and
  an unfolded foldable (841 by 701) lay the library, the book menu, the
  reader with its bars and the reading settings' Look, Page and Turning
  tabs out without overflow
  (`fits`, `e2e/layout.spec.js`, "a split-screen half lays out ..."). The
  place stays on the page when the window goes from full to a half and back,
  with Auto and Two, and when a foldable goes from folded (411 by 797) to
  unfolded and back, with Auto, Two and One (the same spec, "the place stays
  when the window goes ..." and "a foldable folded and unfolded keeps the
  place").
* **Auto shows a spread only in a landscape window of 60em (960 px).** A
  folded or unfolded foldable is one page at Auto; Two and One are the
  reader's own choice and are kept at either size.
* **The fold is not read (decided, #412).** Quire does not read CSS viewport
  segments (`env(viewport-segment-*)`, `horizontal-viewport-segments`) nor
  any fold position from the platform. Research: the segments API is listed
  as supported from Chrome 138 (Chrome for Android), with Firefox and Safari
  unsupported; MDN's browser-compat-data records Android WebView, which the app
  runs in, as mirroring Chrome (so from 138; inferred from the data, not tested
  here), so whether a WebView hands the app a fold as a segment is unknown;
  Android's own guidance (Jetpack WindowManager's
  `FoldingFeature`) splits content into two areas only in book posture on a
  device that is half opened, and avoids text across a fully occluded fold
  (dual-screen devices); today's single-screen foldables have a flat fold
  (`OcclusionType.NONE`), so the unfolded screen is a larger window whose two
  columns meet at the middle, where a spine would be. Kindle on a
  Pixel Fold shows a spread on the inner screen, split at the hinge like
  facing pages (Pocket Tactics and Android Authority, 2023), Kindle's Android spreads are in landscape only for some books, and
  no documentation of Kobo, Apple Books or Google Play Books at a fold was
  found. A change of the rule needs a device that has the fold as a segment
  (a dual-screen device) and the WebView's support for the segments.
* **The system font scale and display size of Android are not played here**
  (see the reader rules: the WebView applies its own text zoom and desktop
  Chromium cannot play it).

## Writing modes, fixed layout and spreads

* **A book is set vertically as Readium sets it, from its OPF** (the book's CSS is
  dropped): `vertical-rl` when its spine reads right to left and its language is
  Chinese, Japanese or Korean, `vertical-lr` for Mongolian in its script.
  `spine_vertical` (`src/epub_xml.bats`) answers a `writing_mode`;
  `src/reader.bats` keeps it in `_vertical`. CSS columns follow the inline axis,
  which then runs down, so pages go down: the page's class is `caf vertical` (not
  `rtl`, whose `direction` would turn that axis upward), and `_page_axis`
  (`Across`, `AcrossBack`, `Down`) is what counts, finds and shows pages. Such a
  book is always paged, one column a screen, a drag does not follow the finger,
  and the settings of the page's layout and of word spacing and breaking are
  hidden. Margins are logical (`margin-block`). Taps, keys and swipes keep the
  meaning of a book read right to left.
* **Text parts (#391).** Set vertically, each run of one or two ASCII digits (not
  in a longer number, not against a Latin letter, not a character reference's
  digit: `_tcy_find`) is wrapped by `_tcy_parts` in a span of class `tcy`
  (`text-combine-upright: all`, inside `.caf.vertical` and `.caf.vertical-lr`
  only). A part has the id `t<number>` and `data-part` (`_part_add`) and **takes
  no content node number**: the content node is still one span `c<N>` whose text
  is the whole text, so notes, highlights, places, search hits and read aloud
  keep their node numbers and UTF-16 offsets. Bridge's `data-part` makes that so:
  a position in a part is an offset into the text of its *owner*, the nearest
  ancestor with no `data-part`. Not wrapped: 3 or more digits, a decimal's digits
  are each a run, a fullwidth digit (upright already). Chrome scales a run to its
  cell by the font it was laid out in and does not do it again when the reading
  face arrives, so a vertical book switches combining off and on again
  (`_tcy_refit`) as a chapter is rendered, in `_relayout` and 150 ms after a face
  arrives (`e2e/relaunch.spec.js`). `e2e/vertical.spec.js`.
* **A fixed-layout book** (`rendition:layout` pre-paginated) is shown a spine
  item a page. `src/epub_xml.bats` reads the OPF's layout (`opf_layout`) and each
  itemref's own (`itemref_layout_n`, which outranks the book's) as a
  `rendition_layout`, and a page's viewport meta (`xhtml_viewport`). The reader
  (`_layout`, `_is_fixed`) renders a fixed page into a box (`page-box`;
  `_render_into` says which element a chapter's top-level nodes go into, so
  content nodes are numbered as ever), laid out as its viewport (else the last
  fixed page's, in `_page_size`; else the view's) and scaled with CSS `zoom` to
  fit whole (`_fixed_fit`, at every layout). The page (`caf fixed`) is the whole
  reader view, one page, never scrolled or in columns, and horizontal whatever
  `_vertical` is (`_writing`). The indicator counts spine items. It is not
  restyled: only the theme and what the reader does are offered, with Columns,
  which say its spreads (`_rows_set`).
* **Spreads.** Fixed pages are shown two at a time as the Columns setting says
  (Two always, One never) and at Auto as `rendition:spread` says
  (`rendition_spread`; `SpreadLandscape` and `SpreadAuto` when the view is wider
  than tall, as Apple Books and Thorium do: `_spreads_wanted`). Each itemref's
  `page-spread-*` is kept with its chapter (`page_spread`) and
  `book_chapter_slots` places the pages as Apple Books does: a page takes the side
  it asks for, else the side after the page before it; the first fixed page (or
  the first after a reflowed one) is alone on the right (left, read right to
  left); a centred page is alone. `_shape_of` makes the page shown a
  `spread_shape` (`Single`, `AloneLeft`, `AloneRight`, `WithNext`,
  `WithPrevious`). The facing page is rendered into `facing-box` (`_facing_open`),
  its content nodes going on from the page's, and cannot be selected (`.facing`),
  so what is marked or read aloud is the page's. A turn moves a spread at a time.

## The reading ruler (keyword: reading ruler, #566)

A band over the text that holds the eye to one line, for readers who lose their place; offered as a
preference (Off to begin with), not as a claim: the evidence is for reading speed, and weaker for
comprehension (Niklaus, Cai, Bylinskii and Wallace, *Digital Reading Rulers*, CHI 2023: 177 readers, 91 with
dyslexia; Grey Bar, Shade and Underline raised the speed of readers with dyslexia by about 10 to 20 words a
minute, readers with dyslexia preferred Lightbox, no style was preferred by all, so the paper recommends
offering several). Comparable software: Kindle's Reading Ruler (colour, opacity, style and size; on Android
it asks for continuous scrolling), Immersive Reader's Line focus (1, 3 or 5 lines, the rest dimmed, arrow keys
move it) and Moon+ Reader (6 styles); KOReader, Thorium, Apple Books and Play Books have none (searched).

* **Styles** (`reading_ruler`: `RulerOff | RulerUnderline | RulerGreyBar | RulerShade | RulerLightbox`, a
  segmented group in the Look tab) and, for the grey bar and the lightbox, the lines held (`ruler_lines`: one,
  three, five, as Immersive Reader). A device setting like the brightness: byte "R" and two bytes at the end
  of the "S2" record, `readingRuler` and `readingRulerLines` in the backup, reset with the settings and put
  back by Undo (`set_reset_undoable`).
* **Colours are the theme's, proven** (`src/ruler_rules.bats`, a style element of its own,
  `style-ruler-rules`, since the main sheet's budget is full). The underline is the text's own colour,
  `underline(E_fg_bg | ...)` (`EDGEP`, the participants' ask). The grey bar is the role `RULER` (a ground under
  the text, in `PAL` and `HARMONY`), written only by `band(R_ruler | ...)`: `RULED` proves the body's text and a
  link on it in every theme at the levels `HARMONY` and `SURF` ask. Shade and Lightbox are the page's ground as
  a veil over the lines, `dim_rule(D_<theme>_<strength> | ...)`: `DIMMED` proves, per theme and strength, that
  the dimmed text, a link and the text on a highlight stay readable (`BLEND` is the rounding of the blend,
  `DIMS` the pair). The page turn's black shade (`VEILED`) was not reused: its proven strengths in the dark
  themes are 8% and none at night, which dims nothing there; a veil of the ground dims text toward the page in
  every theme and is proven the same way. Dimmed, not hidden: the reader may glance back.
  `scripts/gen-harmony.py` writes the proofs; `tests/static/solver/gen_blend.py` the fixtures of `BLEND`.
* **Where it sits** (`src/reading_ruler.bats`): over the text area (`#ruler`, inside the page's paddings, so
  the footer is never dimmed), on a line found from a point by the caret the browser gives there and the place
  of that character (`caret_position_from_point`, `measure_text_offset`); the band is the line's height around
  the glyph box. The reader tells the module its view (`ruler_view`: paged across, paged right to left, scrolled,
  a column set vertically from the right or from the left, none for a fixed layout) at every page it shows
  (`_place_shown`, `reader_scrolled`). A page turn puts it on the page's first line; scrolled it keeps its height
  and snaps to the whole line there (a line the margin cuts is not one); a spread holds the column the line is
  in; a vertical book's ruler lies along the column (`ruler-down`). The band is as many lines as the setting,
  from the line it is on in the way the book is read. Taken as a limit: a line with a larger font than the text
  (a heading) is held at the text's line height.
* **Moving it.** A tap between the sides' zones on another line moves it there (the single-pointer way, WCAG
  2.5.7); a tap on its own line brings up the bars as before, so the bars are summoned by a tap on the ruler's
  line while it is on. A finger or pen that goes down on the band drags it from line to line
  (`ruler_pointer`, before the gestures see the record, so the page does not turn); a mouse's drag selects text,
  and a scrolled page's drag scrolls the text under the ruler (Kindle's way). Reading aloud and a narrated book's
  clips put it on the line of the sentence or clip (`ruler_follow`). No new keys (the arrows are page keys). It is
  `aria-hidden` and takes no focus: a screen reader has its own.
* **Under a panel.** A point under the reading settings' sheet hits the sheet, so a ruler that could not be
  placed there is placed a moment after the panel closes (`ruler_retry`, from `_open_set` in `layer.bats`).
* **Not** in a fixed-layout page (its lines are the publisher's art) or the image viewer.
* Tests: `e2e/reading-ruler.spec.js` (each style on the line it should be at 1, 3 and 5 lines, the first line
  after a turn, tap, drag, read aloud, scrolled and vertical, the contrasts as the browser computes them in the
  five themes, the setting kept, in the backup, reset and Undone, the paragraph kept with the ruler on);
  `tests/static/reject/ruler-*` (a colour pair without its proof does not type-check).
