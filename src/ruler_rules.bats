(* ruler_rules -- the reading ruler's rules, each colour under its proof: EDGEP, RULED, DIMMED (keyword: reading ruler, #566) *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use builder as B

staload "palette.sats"
staload "palette_proofs.sats"
staload "sheet.sats"
staload "declarations.sats"

(* The selector of the veils in a theme (the light theme's is also the default) *)
fn dim_selector {number:palette} (which: palette_theme(number)): [length:pos | length <= 40] string length =
  case+ which of
  | Light() => ".ruler-veil,.th-light .ruler-veil"
  | Sepia() => ".th-sepia .ruler-veil"
  | Dark() => ".th-dark .ruler-veil"
  | Night() => ".th-night .ruler-veil"
  | Grey() => ".th-grey .ruler-veil"

(* The veil in a theme: the page's ground at strength percent, with no text, written only at a strength proven to leave the dimmed lines legible there (DIMMED) *)
fn dim_rule {number:palette}{strength:nat | strength <= 100}{left:nat | left >= 120}
  (dimmed: DIMMED(number, strength) | sheet: sheet(left, false, false), which: palette_theme(number), strength: int strength)
  : [after:nat | after >= left - 120] sheet(after, false, false) = let
  val sheet = rule(sheet, dim_selector(which))
  val () = raw(sheet, "background-color:color-mix(in srgb,var(--bg) ")
  val sheet = put_number(sheet, strength)
  val () = raw(sheet, "%,transparent);")
in close(sheet) end

(* fixture: the-band-and-the-veils-are *)
(* The band and the veils are laid over the text area (inside the paddings the page keeps clear, so the footer is never dimmed), by the placement the reader writes (reading_ruler.bats, style-ruler); the style chosen is the class of ruler. Neither takes a tap *)
fn ruler_rules {left:nat | left >= 1403} (sheet: sheet(left, false, false)): [after:nat | after >= left - 1403] sheet(after, false, false) = let
  val sheet = rule(sheet, ".ruler")
  val sheet = lay(sheet, Display(), "none")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Left(), "0")
  val sheet = lay(sheet, Right(), "0")
  val sheet = lay(sheet, Top(), "var(--page-top)")
  val sheet = lay(sheet, Bottom(), "var(--page-bottom)")
  val sheet = clips(sheet)
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ruler-band,.ruler-veil")
  val sheet = lay(sheet, Display(), "none")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ruler-underline,.ruler-grey,.ruler-shade,.ruler-lightbox")
  val sheet = lay(sheet, Display(), "block")
  val sheet = close(sheet)
  (* over the text, in its own colour *)
  val sheet = rule(sheet, ".ruler-underline .ruler-band")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, ZIndex(), "1")
  val sheet = underline(E_fg_bg | sheet, RoleText(), RoleGround())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ruler-underline.ruler-down .ruler-band")
  val sheet = underline_right(E_fg_bg | sheet, RoleText(), RoleGround())
  val sheet = close(sheet)
  (* under the text: behind the page, over the reader's ground *)
  val sheet = rule(sheet, ".ruler-grey .ruler-band")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, ZIndex(), "-1")
  val sheet = band(R_ruler | sheet, RoleRuler())
  val sheet = close(sheet)
  (* Shade dims what was read, Lightbox what is above and below the band *)
  val sheet = rule(sheet, ".ruler-shade .ruler-before,.ruler-lightbox .ruler-veil")
  val sheet = lay(sheet, Display(), "block")
  val sheet = lay(sheet, ZIndex(), "1")
  val sheet = close(sheet)
  val sheet = dim_rule(D_light_25 | sheet, Light(), 25)
  val sheet = dim_rule(D_sepia_25 | sheet, Sepia(), 25)
  val sheet = dim_rule(D_dark_40 | sheet, Dark(), 40)
  val sheet = dim_rule(D_night_25 | sheet, Night(), 25)
  val sheet = dim_rule(D_grey_30 | sheet, Grey(), 30)
in sheet end

(* The ruler's rules are a style element of their own (style-ruler-rules), as the sizes' are, so the main sheet keeps its room *)
#pub fn ruler_style (): [l:agz][k:nat | k < 65536] @($A.arr(byte, l, $B.BUILDER_CAP), int k)

implement ruler_style () = let
  val builder = $B.create()
  val sheet: sheet(BUDGET, false, false) = Sheet(builder)
  val sheet = ruler_rules(sheet)
  val+ ~Sheet(builder) = sheet
  val @(bytes, length) = $B.to_arr(builder)
in @(bytes, length) end

end
