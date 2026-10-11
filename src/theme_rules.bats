(* theme_rules -- the themes and the base rules

   A theme is written (theme_rule) only with a proof (HARMONY) that it
   follows css's harmony rules, over the colours PAL gives; the base
   rules are the ones the guarantees rest on, the only !important in
   the sheet. *)

#target wasm begin

#include "share/atspre_staload.hats"
staload "palette.sats"
staload "palette_proofs.sats"
staload "sheet.sats"
staload "declarations.sats"

(* The rule's selector of a theme (the light theme's is also the root's) *)
fn theme_selector {which:palette} (which: palette_theme(which)): [length:nat | length <= 20] string length =
  case+ which of
  | Light() => ":root,.th-light" | Sepia() => ".th-sepia" | Dark() => ".th-dark" | Night() => ".th-night"
  | Grey() => ".th-grey"

fn declare_role {left:nat | left >= 30}{role:colour_role}{colour:nat | colour < 16777216}
  (sheet: sheet(left, false, true), role: role_value(role), colour: int colour): [after:nat | after >= left - 30] sheet(after, false, true) = let
  val () = raw(sheet, "--")
  val () = raw(sheet, role_name(role))
  val () = raw(sheet, ":")
  val () = put_colour(sheet, colour)
  val () = raw(sheet, ";")
in sheet end

(* .th-<name>{--role:#rrggbb;...} for a theme: each colour is the one
   PAL gives, so the proofs above are about these *)
#pub fn theme_rule {theme_number:palette}{left:nat | left >= 740}
  {bg_colour,fg_colour,muted_colour,card_colour,line_colour,
   edge_colour,bar_colour,barfg_colour,accent_colour,accentfg_colour,
   hl_colour,barhi_colour,banner_colour,bannerfg_colour,mark_colour,
   markfg_colour,danger_colour,hl2_colour:nat |
   bg_colour < 16777216; fg_colour < 16777216; muted_colour < 16777216;
   card_colour < 16777216; line_colour < 16777216; edge_colour < 16777216;
   bar_colour < 16777216; barfg_colour < 16777216; accent_colour < 16777216;
   accentfg_colour < 16777216; hl_colour < 16777216; barhi_colour < 16777216;
   banner_colour < 16777216; bannerfg_colour < 16777216; mark_colour < 16777216;
   markfg_colour < 16777216; danger_colour < 16777216; hl2_colour < 16777216}
  (bg_from_pal: PAL(theme_number, BG, bg_colour), fg_from_pal: PAL(theme_number, FG, fg_colour),
   muted_from_pal: PAL(theme_number, MUTED, muted_colour), card_from_pal: PAL(theme_number, CARD, card_colour),
   line_from_pal: PAL(theme_number, LINE, line_colour), edge_from_pal: PAL(theme_number, EDGE, edge_colour),
   bar_from_pal: PAL(theme_number, BAR, bar_colour), barfg_from_pal: PAL(theme_number, BARFG, barfg_colour),
   accent_from_pal: PAL(theme_number, ACCENT, accent_colour), accentfg_from_pal: PAL(theme_number, ACCENTFG, accentfg_colour),
   hl_from_pal: PAL(theme_number, HL, hl_colour), barhi_from_pal: PAL(theme_number, BARHI, barhi_colour),
   banner_from_pal: PAL(theme_number, BANNER, banner_colour), bannerfg_from_pal: PAL(theme_number, BANNERFG, bannerfg_colour),
   mark_from_pal: PAL(theme_number, MARK, mark_colour), markfg_from_pal: PAL(theme_number, MARKFG, markfg_colour),
   danger_from_pal: PAL(theme_number, DANGER, danger_colour), hl2_from_pal: PAL(theme_number, HL2, hl2_colour),
   harmony: HARMONY(theme_number) |
   sheet: sheet(left, false, false), which: palette_theme(theme_number),
   bg_colour: int bg_colour, fg_colour: int fg_colour, muted_colour: int muted_colour,
   card_colour: int card_colour, line_colour: int line_colour, edge_colour: int edge_colour,
   bar_colour: int bar_colour, barfg_colour: int barfg_colour, accent_colour: int accent_colour,
   accentfg_colour: int accentfg_colour, hl_colour: int hl_colour, barhi_colour: int barhi_colour,
   banner_colour: int banner_colour, bannerfg_colour: int bannerfg_colour, mark_colour: int mark_colour,
   markfg_colour: int markfg_colour, danger_colour: int danger_colour, hl2_colour: int hl2_colour): [after:nat | after >= left - 740] sheet(after, false, false)

implement theme_rule (bg_from_pal, fg_from_pal, muted_from_pal, card_from_pal, line_from_pal, edge_from_pal, bar_from_pal, barfg_from_pal, accent_from_pal, accentfg_from_pal, hl_from_pal, barhi_from_pal, banner_from_pal, bannerfg_from_pal, mark_from_pal, markfg_from_pal, danger_from_pal, hl2_from_pal, harmony | sheet, which, bg_colour, fg_colour, muted_colour, card_colour, line_colour, edge_colour, bar_colour, barfg_colour, accent_colour, accentfg_colour, hl_colour, barhi_colour, banner_colour, bannerfg_colour, mark_colour, markfg_colour, danger_colour, hl2_colour) = let
  val sheet = rule(sheet, theme_selector(which))
  val sheet = declare_role(sheet, RoleGround(), bg_colour)
  val sheet = declare_role(sheet, RoleText(), fg_colour)
  val sheet = declare_role(sheet, RoleMuted(), muted_colour)
  val sheet = declare_role(sheet, RoleCard(), card_colour)
  val sheet = declare_role(sheet, RoleLine(), line_colour)
  val sheet = declare_role(sheet, RoleEdge(), edge_colour)
  val sheet = declare_role(sheet, RoleBar(), bar_colour)
  val sheet = declare_role(sheet, RoleBarText(), barfg_colour)
  val sheet = declare_role(sheet, RoleAccent(), accent_colour)
  val sheet = declare_role(sheet, RoleAccentText(), accentfg_colour)
  val sheet = declare_role(sheet, RoleHighlight(), hl_colour)
  val sheet = declare_role(sheet, RoleBarHigh(), barhi_colour)
  val sheet = declare_role(sheet, RoleBanner(), banner_colour)
  val sheet = declare_role(sheet, RoleBannerText(), bannerfg_colour)
  val sheet = declare_role(sheet, RoleMark(), mark_colour)
  val sheet = declare_role(sheet, RoleMarkText(), markfg_colour)
  val sheet = declare_role(sheet, RoleDanger(), danger_colour)
  val sheet = declare_role(sheet, RoleSecondHighlight(), hl2_colour)
in close(sheet) end

(* The rules the guarantees rest on; the only !important in the sheet *)
#pub fn base_rules {left:nat | left >= 1700} (sheet: sheet(left, false, false)): [after:nat | after >= left - 1700] sheet(after, false, false)

implement base_rules (sheet) = let
  val () = raw(sheet, "[data-hide='1'],[hidden]{display:none!important}")
  (* 44 x 44 targets: every button and field, everything given a
     control's role, and the app's links out (ui_link_out); links in a
     book's text are inline targets, which WCAG leaves to the text they
     sit in *)
  val () = raw(sheet, "button,input,select,textarea,[role=button],[role=menuitem],[role=tab],[role=slider],[role=option],[role=switch],.linkout")
  val () = raw(sheet, "{min-height:48px!important;min-width:48px!important;box-sizing:border-box}")
  (* 16px in text fields, so iOS does not zoom into them *)
  val () = raw(sheet, "input,select,textarea{font-size:16px!important}")
  (* focus: 2px inside the edge in the control's own proven colour *)
  val () = raw(sheet, ":focus-visible{outline:2px solid currentColor!important;outline-offset:-2px!important}")
  (* text fields: fg on card with a 3:1 edge (S_fg_card, E_edge_card) *)
  prval _ = S_fg_card
  prval _ = E_edge_card
  val () = raw(sheet, "input:not([type=range]):not([type=file]),textarea,select")
  val () = raw(sheet, "{color:var(--fg)!important;background-color:var(--card)!important;border:1px solid var(--edge)!important}")
  (* a placeholder is text like any other (quire#357): muted on the
     field's own card, proven in every theme (SURF), and drawn in full,
     where a browser's default fades it below the proof *)
  val sheet = rule(sheet, "input::placeholder,textarea::placeholder")
  val sheet = surf(S_muted_card | sheet, RoleMuted(), RoleCard())
  val () = raw(sheet, "opacity:1;")
  val sheet = close(sheet)
  (* a search field's own clear button is too small a target *)
  val () = raw(sheet, "input[type=search]::-webkit-search-cancel-button{display:none}")
  (* a button is a surface like any other: fg on card until a rule
     says otherwise *)
  prval _ = S_fg_card
  val () = raw(sheet, "button{font:inherit;cursor:pointer;color:var(--fg);background-color:var(--card);border:0}")
in sheet end

end
