---
paths:
  - src/style.bats
  - src/palette*.bats
  - src/sheet.bats
  - src/declarations.bats
  - src/theme*.bats
  - src/ui.bats
  - src/layer.bats
  - src/back.bats
  - src/undo.bats
  - src/modal.bats
  - src/*_rules.bats
  - src/page_size.bats
  - scripts/gen-harmony.py
  - e2e/controls-shown*
  - e2e/layout*
  - e2e/back*
  - e2e/settings-screen*
---

# The interface: what the types guarantee

## The stylesheet is built in Bats, under proofs

The stylesheet is built in modules that each have their own `.sats`, so a
change to one (or a static fixture put into it) re-checks that module and what
stages after it (#462). In order: `src/palette.bats` (roles, `PAL`, the
statements `SURF`, `EDGEP`, `HARMONY`, `VEILED`), `src/palette_proofs.bats`
(their proofs, written by `scripts/gen-harmony.py`: the costly part),
`src/sheet.bats` (builder, rules, spacing scale), `src/declarations.bats` (the
declarations that name a colour), `src/theme_rules.bats`, the screens' rules
(`*_rules.bats`) and `src/style.bats` (`app_style`). A fixture goes into the
module of its area, not into one that holds proofs (`reject/role-unmatched` is
in `palette.bats`). Keep each module's `#pub` declarations stable: bats
re-checks what staloads a `.sats` only when more than line positions change in
it (bats-lang/bats#243).

* **A text colour and its background are only set together** (`surf`), with a
  proof (`SURF`) that the pair reaches 4.5:1 in each of the five themes (css's
  `CONTRAST` over `PAL(t, r, c)`; a role is a `role_value(r)`, never a number).
  Control edges and accents need 3:1 (`EDGEP`). A placeholder is text too
  (`S_muted_card`); a chosen tab keeps the card and draws `underline`, proven
  3:1 (quire#358, WCAG 1.4.11). Grounds without text (`fill`, `tint`) set their
  font size to 0. `textContrastShort` and `stateCueShort`
  (`e2e/controls-shown.js`) measure the rendered page.
* **A theme is written (`theme`) only with a proof (`HARMONY`)** that it follows
  css's harmony rules (`harmony.bats` gives each rule's source). A palette that
  breaks a rule does not type-check.
* **Spacing comes from one scale** (#331): `space(n)` (4, 8, 12, 16, 24 px),
  written by `spaced` and `spaced_pair`. Only the spacing forms write a gap,
  padding or margin, and only `scrolls`, `scrolling`, `clips` and `capped`
  write an overflow or max-height (#500): `lay(sheet, Gap(), "10px")` does not
  type-check (`tests/static/reject/lay-writes-gap`, `-padding`, `-overflow`,
  `-max-height`). A value off the scale is a form named for what it is
  (`spaced_safe`, `pulled`, `auto_margin`, `prose_margin`, `reserve`,
  `page_padding`, ...). `SPACE_INSET` (8 px) is the least a control keeps from
  its container's edges; `insetsShort` and `offScale`
  (`e2e/controls-shown.js`, run by `fits` on every screen the walk reaches)
  fail any that does not. #332 (open) is to prove the insets statically.
* **The page's width and height are a whole number of pixels** (`page_extent`;
  `page_width_rule` and `page_height_rule` in `src/page_size.bats` take a
  `page_extent(1)` only: `tests/static/reject/page-width-fraction`,
  `page-height-fraction`). The reader scrolls to page n by n times the width and
  counts pages by the scroll width, both whole numbers; a fractional window
  (a Pixel 9's 411.43 px) put each page 0.43 px further out and counted a page
  too many. The rule rounds the container down with CSS `round()` (Chrome 125).
  What the proof does not reach is the browser: `e2e/fractional-window.spec.js`.
* **A setting with two states is a switch** (`_switch_row`), never a segmented
  On | Off nor a lone pressed button (quire#363); a segmented group is for three
  or more choices, or two that are not on and off. `onOffPairs` fails a screen
  that has one.
  A switch shows its label alone; its description is read out only (#592,
  keyword switch-note, `.claude/rules/reader-layout.md`).
* **A sign-in field is named by a visible label** (quire#361, WCAG 3.3.2):
  `ui_form_field` makes a `<label for>`; `ui_field` has no such kinds, so a
  password field without a label does not type-check
  (`tests/static/reject/form-field-as-field`). A sync service's step button is
  `Sign in to <service>` (`sign_in_label`); a row that opens a screen ends in a
  chevron drawn by the stylesheet (`.chev::after`), never a character of its
  words (`tests/static/glyphs.py` rejects U+203A in `ui_text_btn`).
  `labelsShown` and `labelInName` check both.
* **The base rules are the only `!important` ones**: every control is at least
  48px square (quire#403; `targetsShort`), text fields use a 16px font (iOS does
  not zoom), and focus shows a 2px ring in the text's own colour.
* **The sheet's size is in its type** (`sheet(r, media, open)`), so it fits the
  64 KiB text it is put in (the budget is 65500 bytes, raised from 64000 by #412, from 64500 by #861 to 65000 and by #860's edge rules to 65500: the costs the forms
  declare are upper bounds), and a rule is opened only outside another and
  closed only once.

## Elements are made through `src/ui.bats`

* Plain elements come from a tag type with no interactive tags; a button, a
  field or an image can only be made by a constructor that names it. A text
  button is named by its text alone (WCAG 2.5.3); an icon button is given its
  name; an icon is a glyph of one monochrome set (a subset of Material Symbols,
  `assets/fonts/material-symbols-subset.woff2`, made by `scripts/icon-font.py`),
  never an emoji (#274); images are decorative (`alt=""`); `ui_audio` has no
  controls and is hidden from assistive technology; a role that needs a name
  (dialog, region, toolbar, menu, group) is given one with it.
* Each element id is made at one place, no numbered id (`nid_make`) can spell
  another, and every id the code names is one it makes: `tests/static/ids.py`
  checks it. An element made again to reset it is made by one function, called
  at startup and at the reset.
* `ui_attr` takes a typed attribute that cannot be a name, a role or a style.
  The inline styles are `ui_place` and `ui_fixed_box_n` (numbers alone, zoom 1
  to 10000 thousandths), so no inline style can set a colour or anything else
  the stylesheet proves.
* **Lists are made only by `ui_list`, `ui_list_nn`, `ui_item_n` and
  `ui_item_nn`** (#690), so every `ul` states `role=list` (Safari with
  VoiceOver drops the semantics of a list whose markers are gone) and the
  tag type still has no list tags. The Contents' levels are lists in the items
  of their parents (`_place`, `_rows` in `src/toc.bats`: an entry deeper than
  one below the deepest open entry is put one level below it), the native
  element, by the first rule of ARIA: no `role=tree` (the APG's tree asks for
  Up/Down/Home/End/type-ahead and open/close, none of which a list of
  buttons that always shows all has) and no `aria-level` (MDN, from the ARIA
  spec: redundant when the nesting says it, and a risk of misinformation).
  `e2e/toc-levels.spec.js` checks the tree with `toMatchAriaSnapshot`; what a
  screen reader says is for quire#692 (Guidepup).
* Listeners are registered only as one table (`regs` in `src/ui.bats`), each
  with its position as its id, and the table's length, in its type, is at most
  127: the bridge's last slot (of 128) is the media query listener's
  (`ui_media_listener`). The platform's typed listeners (`RFullscreen`,
  `RSystemBars`, `RSpeech`, `RInstallOffer`, `RAppLink`, `RFonts`) take slots in
  the same table.

## Nothing is lost at a click, except by emptying the Trash

Emptying is the one irreversible action because it is the one with no visible
effect (it only gives storage back), so nothing a reader needs to do requires
it. Every other action changes what the reader sees and is offered back
(Undo), keeps what it replaces, or can be done again; an action with a visible
effect is never a `harm`.

* Removing a book moves it to the Trash, where it can only be restored;
  archiving, hiding, deleting a highlight or bookmark, resetting the settings
  and a factory reset (`lib_trash_all`, `set_reset_undoable`) are done at once.
  Each is offered back by the Undo toast (`undo_offer` in `src/undo.bats`),
  whose undo runs only from its own button. An offer stays until used, dismissed
  or replaced by another (which makes the earlier one final; quire#364, WCAG
  2.2.1): `undo_offer` takes an `offered(UntilDismissed)`, so a `Brief` offer
  does not type-check (`tests/static/reject/undo-offer-brief`). The toast names
  what was done (`'Keep Me' moved to Trash`, a title over 60 bytes cut at a
  character, `title_put`).
* Emptying the Trash asks a `harm` (`src/ui.bats`, only `HEmptyTrash`, made of
  `{things:pos}`: `tests/static/reject/harm-empty-zero`), the one question with a
  red button. It counts and names what goes ("Delete 2 books forever?", at
  most 3 titles, the dictionaries) and closes any Undo offer first.
* Red is the stylesheet's rule for `[data-harm=y]`, which only `src/ui.bats`
  sets, from a harm (`ui_harm_button`) or a button whose tone is `Danger(h)`. A
  click on a harm's button is dispatched by the harm its id belongs to
  (`_harm_clicked` in `src/bin/quire.bats`) to `lib_ask_harm`, which asks that
  same harm, so a red button always asks about what it names.
* What deletes is private to the module that owns it (deleting a book, emptying
  the Trash: `src/library.bats`; dropping an annotation: `src/annot.bats`; no
  `#pub`). Emptying runs only in `lib_ask_harm`, when `modal_confirm` resolves
  `Accepted`; only the dialog's second button resolves it so (`modal_listen`,
  its answer function is not exported), so other code can dismiss a dialog
  (`modal_dismiss`) but never confirm one.
* The Trash's screen says what it holds ("1 book · 4.0 MB. Kept until you
  empty the Trash.", `_trash_head`); nothing is purged by itself. Restore all
  books (`trash-restore-all`, quire#494) is plain; its Undo (`BooksRestored`)
  puts exactly those books back (`lib_untrash_all`).

## Failures are said, never dropped

What fails is said
(`src/notice.bats`; see `backup-errors.md`). A
write of the reader's own data ends in `save_checked`, which says once a session
that storage may be full; a chapter that cannot be shown leaves the reader on
the page it was on (`_jump_checked`), or, as a book opens, back in the library.
A copy is confirmed by the copy status (`copy-status`), apart from the Undo
toast.

## Overlays, Back and the screens

* The overlays (menus, book info, the reader's panels, the full screens) are a
  `layer` (`src/layer.bats`): shown and hidden only by `layer_open` and
  `layer_close`, which keep the stack. Escape answers the dialog if one is open,
  else closes the top of the stack (`layer_escape`).
* **Back is one model** (#333, `_go_back` in `src/bin/quire.bats`): the dialog
  is answered No, else the top of the stack closes as Escape does, else the
  in-book search's results end, else the book goes back to the library; at the
  library with nothing open it is the platform's (in the app, `app_minimize`,
  not `exitApp`). In a browser `src/back.bats` pushes one history guard entry
  once there is anything to go back from, and never takes a guard back on its
  own (`history.back()` is asynchronous: raced pushes and reloads); a guard left
  behind is taken by the next Back, and with nothing to go back from that Back
  is the platform's (`back_leave`). The page restores its own scroll
  (`history_scroll_restoration`, `ScrollManual`), so going back over a guard never
  moves the library. `e2e/back.spec.js` walks every screen of
  `e2e/walk.js` (also walked by `e2e/layout.spec.js`, so a screen added there is
  covered) and checks Back goes exactly one step from each.
* **Settings** (`LSettings`, `_wire_settings_screen`) follows Android's pattern:
  one screen of groups, each complex area a screen of its own opened from a row
  that shows its state. It opens from the library menu only; in a book the
  reading settings sheet is the one settings place (#342). About Quire
  (`LAbout`) links out only to the home page, privacy policy and terms (no link
  to the source).
* **Sync and the backup** (#501): the library menu has Sync (two taps), and an
  empty library offers "Sync with another device" (`empty-sync`); the backup
  stays in Settings. A prompt after the first book is not used (a nag before
  the reader has anything to lose); Play Books has no setting to find, Moon+
  Reader keeps its backup in Settings. `e2e/settings-screen.spec.js`.
* **Themes in the reading settings are swatches** (`theme_swatch_rules`): each
  wears its theme's class so its "Aa" is the theme's own pair, proven;
  `looksActionable` fails a chevron on something that is not a control.
* **A pushed screen** (Settings, Sync, Dictionaries, About) has a top bar with a
  Back icon button (`ui_screen_bar`, 48 px) and no Done (#502); Back does what
  Escape does. The error banner sits under the bar while one is open
  (`ui_banner_below_bar`, set in `_open_set`). Statistics, Catalogues and
  Collections are centred dialogs and keep their Done.
* The library bar's More options (a gear would say it goes straight to
  Settings, #333) opens the library menu: Settings, About, Catalogues, Reading
  statistics, Hidden, Archived, Trash, Install Quire (while offered) and Close.
  Empty Trash is on the Trash's own screen.
* The home page, privacy policy and terms are plain static HTML in `homepage/`
  (#216), published by `deploy.yml`; not the app's (gen-pwa does not read them,
  the service worker does not keep them). **The privacy policy states what the
  code does: change it with any change to what is stored, what leaves the
  device, or the Google scopes asked for.**
