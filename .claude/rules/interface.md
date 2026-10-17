---
paths:
  - src/style.bats
  - src/palette*.bats
  - src/sheet.bats
  - src/declarations.bats
  - src/theme*.bats
  - src/ui.bats
  - src/layer.bats
  - src/undo.bats
  - src/modal.bats
  - src/*_rules.bats
  - src/page_size.bats
  - scripts/gen-harmony.py
  - e2e/controls-shown*
  - e2e/layout*
---

# The interface: what the types guarantee

## What the types guarantee about the interface

The stylesheet is built in Bats, not written as CSS, in modules that each
have their own `.sats`, so a change to one (or a static fixture put into
it) re-checks that module and what stages after it, not all of it
(#462; `style.bats` was 3478 lines and 7 to 18 minutes a change). In
order: `src/palette.bats` (the roles, `PAL`, and the statements `SURF`,
`EDGEP`, `HARMONY`, `VEILED`), `src/palette_proofs.bats` (their proofs,
written by `scripts/gen-harmony.py`, each an exported `prval` with a
`primplement`: the costly part), `src/sheet.bats` (the builder, rules,
layout declarations, the spacing scale), `src/declarations.bats` (the
declarations that name a colour, under their proofs),
`src/theme_rules.bats` (the themes and the base rules), the screens'
rules (`shell_rules`, `overlay_rules`, `reader_rules`, `page_turn_rules`,
`panel_rules`, `reading_settings_rules`, `adaptive_rules`) and
`src/style.bats`, which puts them in order (`app_style`). A fixture goes
into the module of its area, not into one that holds proofs
(`reject/role-unmatched` is in `palette.bats`). Keep each module's `#pub`
declarations stable: bats re-checks what staloads a `.sats` only when
more than line positions change in it (bats-lang/bats#243):

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
  are cards inset 8 / 16 px (`spacing_rules`), a panel opened as a dialog
  16 px, a dialog 24 px. #332 is to prove the insets statically.
* Only the spacing forms write a gap, padding or margin, and only
  `scrolls`, `scrolling`, `clips` and `capped` write an overflow or a
  max-height (#500): those properties are not in `lay`'s `prop` (they are
  `spacing_prop`, which only the forms take), so `lay(sheet, Gap(), "10px")`
  does not type-check (`tests/static/reject/lay-writes-gap`, `-padding`,
  `-overflow`, `-max-height`). A value is a step of the scale (`SpaceNone`
  to `SpaceExtraLarge`: `spaced`, `spaced_pair`), or a form named for what
  it is: a safe-area inset (`spaced_safe`, `reserve_safe`), a margin pulled
  out (`pulled`), automatic (`auto_margin`, `centred`), the book's em
  (`prose_margin`), room kept for something drawn in the padding
  (`reserve`: a chevron, a page number, an outline's indent, the Undo
  toast), the reader's own variables (`page_padding`, `safe_area_margin`).
  Values that were off the scale moved to the nearest step (2 to 4, 6 to
  8, 10 to 12, 14 to 16), a few pixels. `offScale` in `e2e/controls-shown.js`
  holds every visible element's gaps to the scale on every screen the walk
  reaches. The sheet's budget is 64000 bytes (it was 60000): the costs the
  forms declare are upper bounds, and the sheet stays under 65536.
* The page's width and height are a whole number of pixels (`page_extent`,
  indexed by whether it is whole; `page_width_rule` and `page_height_rule`
  (`src/page_size.bats`, a module of its own so its fixtures check in a
  minute, where a snippet in the old `style.bats` cost 7 to 18) give the `.caf`
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
  constructor says what an Undo would undo. `offered` is a `datavtype`:
  `MovedToTrash` carries the book's title, and the toast names it
  (`'Keep Me' moved to Trash`, a title over 60 bytes cut at a character
  and ended with an ellipsis, `title_put` in `src/titles.bats`; quire#385,
  Material 3's snackbar says what was done).
* A factory reset moves every book to the Trash and resets the
  settings (`lib_trash_all`, `set_reset_undoable`), with one Undo that
  puts back each book's shelf and the settings.
* Emptying the Trash is the one irreversible action, and the one
  question with a red button: the dialog (`src/modal.bats`) asks a
  `harm` (`src/ui.bats`), which has only `HEmptyTrash`, made of the
  number of things the Trash holds, `{things:pos}`: the Trash cannot be
  asked about when it is empty (`tests/static/reject/harm-empty-zero`).
  The question counts and names what goes (quire#385, M3's dialogs pose a
  specific question; Gmail and Drive say "Delete forever"): "Delete 2
  books forever?", the text naming at most 3 titles and the dictionaries
  ("'A', 'B' and 'C' will be deleted for good ..."), the red button
  "Delete forever". It closes any Undo offer first, since what that would
  put back is gone.
* Red is the stylesheet's rule for `[data-harm=y]`, which only
  `src/ui.bats` sets, and only from a harm: on the harm's button
  (`ui_harm_button`, whose id and label are the harm's; the Trash's
  Empty Trash, beside its summary) and on a button whose tone is
  `Danger(h)` (the dialog's, for `Harmful(h)`). A click on a harm's
  button is dispatched by the harm its id belongs to (`_harm_clicked` in
  `src/bin/quire.bats`, which counts what the Trash holds first) to
  `lib_ask_harm`, which asks that same harm, so a red button always asks
  about what it names.
* The Trash's screen says what it holds (quire#385): under its title a
  line "1 book · 4.0 MB. Kept until you empty the Trash." (the books
  and the dictionaries in it, the books' file sizes; `_trash_head` in
  `src/library.bats`, which asks `dict_trash_count` for the dictionaries) with Empty Trash beside it, there only while the
  Trash holds something. Nothing is purged by itself: that would be an
  irreversible action the reader did not take. A book in the Trash has
  Restore first in its menu.
  Restore all books (`trash-restore-all`, quire#494; Windows' Recycle Bin
  has "Restore all items" beside its empty button, Drive and Gmail only
  select-all then restore) comes before Empty Trash, plain since nothing is
  lost: `lib_restore_all` puts every book of the Trash on the shelf, as a
  single Restore does, and returns the Trashed books' shelves, so the offer
  `BooksRestored` (Undo) puts exactly those books back in the Trash
  (`lib_untrash_all`) and its end lets them go (`lib_shelved_free`). It
  says "books": the dictionaries in the Trash have their own Restore.

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
added to it, and the screen says why and offers what fits (#374, below); a book's record that is newer or not Quire's is
shown nowhere, said once and never written over; one that lost a group, or
that is under other ids than its key, or is cut in its framing (#614), is used, and one with no header to read
is read from the version before it when there is one, else shown nowhere (#510). A backup that could not
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

Where sync and the backup are (#501): sync is how a new phone gets places,
shelves and notes, so the library menu has a Sync item (two taps from the
library, `MenuSync`, opening the Sync screen over the library, whose Escape
or Back returns to it) and an empty library offers "Sync with another
device" (`empty-sync`) beside Import and Get free books; the backup stays
in Settings (three taps), with a line under the first group saying that sync
keeps places, shelves and notes the same on the devices, that a backup holds
them in a file, and that neither holds the books' files. By research: Play
Books syncs through the Google account with no setting to find, Moon+ Reader
keeps its backup in Settings; a prompt after the first book is not used (a
nag before the reader has anything to lose). `e2e/settings-screen.spec.js`
checks both depths and the empty library's offer.

The reading settings' themes are swatches (#501, `theme_swatch_rules`): each
fixed theme is a button that wears its theme's class (`th-sepia`), so its
variables are that palette's and its sample "Aa" on its card is the theme's
own pair, proven in every theme (`S_fg_card`), the chosen one ringed in its
accent and underlined (`E_accent_card`); its name is its `aria-label`. Auto
(the clock's) is a word. `looksActionable` (`e2e/controls-shown.js`, in
`fits`) fails a chevron on something that is not a control, one that is
not drawn, or one without a control's pointer.

A pushed screen (Settings, Sync, Dictionaries, About: class `info`, opened
from a row that ends in a chevron) has a top bar, not a Done at its foot
(#502; Android's settings and Material 3's small top app bar have a
navigation icon and the title, iOS pushes a screen with a back item and
keeps Done for a sheet): `ui_screen_bar` makes a Back icon button (48 px,
named "Back", the `SettingsBack`, `SyncBack`, `DictionariesBack` and
`AboutBack` controls) and the screen's title, outside what scrolls
(`.tbar`), so it stays at the top. Back does what Escape does (with a
service's sign-in step open on Sync it ends the step), and the first focus
of a screen is its Back. The error banner (z-index over the screens, so its
Dismiss, Copy details and Report are pressed) sits under the bar while one is
open (`ui_banner_below_bar`, `data-below`, set where the stack of overlays
changes, `_open_set` in `src/layer.bats`): over the top of the screen it had
covered Back (found by sync-dropbox-android.spec on #544). Statistics, Catalogues and Collections are
centred dialogs and keep their Done (`dismiss_label(DismissScreen)`).
`e2e/settings-screen.spec.js` checks the four bars, that none has a Done, that
the bar stays put as the screen scrolls, and that Back closes it.

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
browser offers it) and Close. Empty Trash is not in it: it is on the
Trash's own screen.
