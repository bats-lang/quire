(* reading_settings_rules -- the reading settings' sheet: its tabs, rows,
   switches and the drawings of where taps turn pages *)

#target wasm begin

#include "share/atspre_staload.hats"
staload "palette.sats"
staload "palette_proofs.sats"
staload "sheet.sats"
staload "declarations.sats"

(* The reading settings' switches and stacked rows (quire#300): a
   switch is a button the row's width, its name at the start and a drawn
   track at the end, whose knob sits at the start, in the edge's colour,
   while it is off, and at the end, in the accent's text colour on a
   track filled with the accent, while it is on (aria-pressed), so its
   state shows in its look, not only to assistive technology (WCAG
   1.4.1). Track and knob are graphics that say a state, so each keeps
   3:1 against what is around it (WCAG 1.4.11): the edge on the card
   (E_edge_card), the accent on the card (E_accent_card), the knob on
   the accent (S_accentfg_accent). A bar's toggle on is marked too. A
   stacked row puts a label, its
   control the whole width (a select is never cut to "Syste...") and a
   line saying what it does, one under another *)
#pub fn switch_rules {left:nat | left >= 2000} (sheet: sheet(left, false, false)): [after:nat | after >= left - 2000] sheet(after, false, false)

implement switch_rules (sheet) = let
  prval _ = E_edge_card
  prval _ = E_accent_card
  val sheet = rule(sheet, ".sgroup")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, Gap(), "12px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".srow.stack")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, AlignItems(), "stretch")
  val sheet = lay(sheet, Gap(), "4px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".stack .slabel")
  val sheet = lay(sheet, Width(), "auto")
  val sheet = close(sheet)
  (* a select is never narrower than its chosen option: in a row too
     narrow for its label and its selects (Speed and voice at 320 px),
     the last ones go to the next line instead *)
  val sheet = rule(sheet, ".srow:has(>.ssel)")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ssel")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = close(sheet)
  (* a list row's button (a dictionary's or a catalogue's Remove) keeps
     its word whole; the name beside it wraps instead (320 px) *)
  val sheet = rule(sheet, ".srow>.btn")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".stack .ssel")
  val sheet = lay(sheet, MaxWidth(), "none")
  val sheet = lay(sheet, Width(), "100%")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sabout")
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sbtn.switch")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, JustifyContent(), "space-between")
  val sheet = lay(sheet, Gap(), "12px")
  val sheet = lay(sheet, Width(), "100%")
  val sheet = lay(sheet, Padding(), "8px 0")
  val sheet = lay(sheet, TextAlign(), "start")
  val sheet = lay(sheet, FontSize(), "15px")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".switch .track")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = lay(sheet, Position(), "relative")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, Width(), "44px")
  val sheet = lay(sheet, Height(), "24px")
  val sheet = lay(sheet, BoxSizing(), "border-box")
  val sheet = lay(sheet, BorderRadius(), "12px")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = fill(sheet, RoleCard())
  val sheet = line(sheet, AllSides(), 2, RoleEdge())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".switch .knob")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, Top(), "3px")
  val sheet = lay(sheet, Left(), "3px")
  val sheet = lay(sheet, Width(), "14px")
  val sheet = lay(sheet, Height(), "14px")
  val sheet = lay(sheet, BorderRadius(), "50%")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = fill(sheet, RoleEdge())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".switch[aria-pressed=true] .track")
  val sheet = fill(sheet, RoleAccent())
  val sheet = line(sheet, AllSides(), 2, RoleAccent())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".switch[aria-pressed=true] .knob")
  val sheet = lay(sheet, Left(), "23px")
  val sheet = fill(sheet, RoleAccentText())
  val sheet = close(sheet)
  (* a bar's toggle (Read aloud, the narration's, the bookmark) on: the
     bar's highlight, as under a finger, and a bar of its text's colour
     under it, which a hover does not have *)
  val sheet = rule(sheet, ".top .ibtn[aria-pressed=true],.bot .ibtn[aria-pressed=true]")
  val sheet = surf(S_barfg_barhi | sheet, RoleBarText(), RoleBarHigh())
  val sheet = line(sheet, BottomSide(), 3, RoleBarText())
  val sheet = close(sheet)
in sheet end

(* The reading settings' sheet's tabs (app.bats's _settings), a line of
   their own under its title and Close, sharing it by their names'
   widths, and its panels, a column of rows as the sheet is; and its
   choices of where taps turn pages: a line each, a drawing of the
   page's zones beside the choice's name and what it does. The drawing is the
   page's ground framed by an edge, the back zone the line's colour and
   the forward zone the accent (no text: their font size is 0); a book
   read right to left has it mirrored (.taps.rtl). The drawing and the
   line take no taps, so a tap on them is the button's *)
#pub fn reading_settings_rules {left:nat | left >= 4800} (sheet: sheet(left, false, false)): [after:nat | after >= left - 4800] sheet(after, false, false)

implement reading_settings_rules (sheet) = let
  val sheet = rule(sheet, ".shead")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".shead .tabs")
  val sheet = lay(sheet, Flex(), "1 0 100%")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".shead .tab")
  val sheet = lay(sheet, Flex(), "1 1 auto")
  val sheet = lay(sheet, Padding(), "8px 4px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tabpanel")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, Gap(), "10px")
  val sheet = close(sheet)
  (* the panels, one over another in one cell, as tall as the tallest
     (#301): the one not chosen keeps its room, unseen, and so is
     neither focused nor read out *)
  val sheet = rule(sheet, ".tabpanels")
  val sheet = lay(sheet, Display(), "grid")
  val sheet = lay(sheet, GridTemplate(), "auto/minmax(0,1fr)")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tabpanels>.tabpanel")
  val sheet = lay(sheet, GridArea(), "1/1")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tabpanel.unchosen")
  val sheet = lay(sheet, Visibility(), "hidden")
  val sheet = close(sheet)
  (* a Settings row's button keeps its name on one line, and the state
     beside it (the Sync row's) wraps instead *)
  val sheet = rule(sheet, ".srow>.rowbtn")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = close(sheet)
  (* a row that opens a screen ends in a chevron, drawn and not part of its
     name (the empty alternative text), so the name is the row's words
     alone (WCAG 2.5.3, quire#361) *)
  val sheet = rule(sheet, ".chev::after")
  val () = raw(sheet, "content:\"\\203A\" / \"\";margin-left:8px;")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".srow.tapsrow")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = lay(sheet, AlignItems(), "stretch")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tapsrow .slabel")
  val sheet = lay(sheet, Width(), "auto")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seg.taps")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seg button.tapbtn")
  val sheet = lay(sheet, Display(), "grid")
  val sheet = lay(sheet, GridTemplate(), "\"m n\" auto \"m a\" auto/32px 1fr")
  val sheet = lay(sheet, Gap(), "2px 12px")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = lay(sheet, TextAlign(), "start")
  val sheet = lay(sheet, Padding(), "8px 12px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tapmap")
  val sheet = lay(sheet, GridArea(), "m")
  val sheet = lay(sheet, Position(), "relative")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, Width(), "32px")
  val sheet = lay(sheet, Height(), "48px")
  val sheet = lay(sheet, BoxSizing(), "border-box")
  val sheet = lay(sheet, BorderRadius(), "4px")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, FontSize(), "0")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = fill(sheet, RoleGround())
  val sheet = line(sheet, AllSides(), 1, RoleEdge())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tzb,.tzf")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, FontSize(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tzb")
  val sheet = fill(sheet, RoleLine())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tzf")
  val sheet = fill(sheet, RoleAccent())
  val sheet = close(sheet)
  (* sides: a quarter at each side, the middle the bars' *)
  val sheet = rule(sheet, ".sides .tzb")
  val sheet = lay(sheet, Inset(), "0 75% 0 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sides .tzf")
  val sheet = lay(sheet, Inset(), "0 0 0 75%")
  val sheet = close(sheet)
  (* forward: under the top eighth (the bars'), a quarter back, the
     rest forward *)
  val sheet = rule(sheet, ".forward .tzb")
  val sheet = lay(sheet, Inset(), "12.5% 75% 0 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".forward .tzf")
  val sheet = lay(sheet, Inset(), "12.5% 0 0 25%")
  val sheet = close(sheet)
  (* one hand: the top third back, the bottom third forward *)
  val sheet = rule(sheet, ".onehand .tzb")
  val sheet = lay(sheet, Inset(), "0 0 66.6% 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".onehand .tzf")
  val sheet = lay(sheet, Inset(), "66.6% 0 0 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".taps.rtl .sides .tzb")
  val sheet = lay(sheet, Inset(), "0 0 0 75%")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".taps.rtl .sides .tzf")
  val sheet = lay(sheet, Inset(), "0 75% 0 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".taps.rtl .forward .tzb")
  val sheet = lay(sheet, Inset(), "12.5% 0 0 75%")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".taps.rtl .forward .tzf")
  val sheet = lay(sheet, Inset(), "12.5% 25% 0 0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tapabout")
  val sheet = lay(sheet, GridArea(), "a")
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
in sheet end

end
