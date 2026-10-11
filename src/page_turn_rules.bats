(* page_turn_rules -- a page turn's rules: the shade over the incoming
   page at each level of each theme, written only at a strength proven
   (VEILED) to leave the page legible, and the sliding copy *)

#target wasm begin

#include "share/atspre_staload.hats"
staload "palette.sats"
staload "palette_proofs.sats"
staload "sheet.sats"
staload "declarations.sats"

(* The selector of a page turn's shade at a level in a theme (the
   light theme's is also the default) *)
fn shade_selector {number:palette}{level:pos | level <= 4} (which: palette_theme(number), level: int level): [length:pos | length <= 40] string length =
  case+ which of
  | Light() => (case+ level of 1 => ".shade.s1,.th-light .shade.s1" | 2 => ".shade.s2,.th-light .shade.s2"
    | 3 => ".shade.s3,.th-light .shade.s3" | _ => ".shade.s4,.th-light .shade.s4")
  | Sepia() => (case+ level of 1 => ".th-sepia .shade.s1" | 2 => ".th-sepia .shade.s2"
    | 3 => ".th-sepia .shade.s3" | _ => ".th-sepia .shade.s4")
  | Dark() => (case+ level of 1 => ".th-dark .shade.s1" | 2 => ".th-dark .shade.s2"
    | 3 => ".th-dark .shade.s3" | _ => ".th-dark .shade.s4")
  | Night() => (case+ level of 1 => ".th-night .shade.s1" | 2 => ".th-night .shade.s2"
    | 3 => ".th-night .shade.s3" | _ => ".th-night .shade.s4")
  | Grey() => (case+ level of 1 => ".th-grey .shade.s1" | 2 => ".th-grey .shade.s2"
    | 3 => ".th-grey .shade.s3" | _ => ".th-grey .shade.s4")

(* The shade at a level (1 to 4, the strongest last) in a theme: black
   at strength percent, a ground with no text, at a strength proven to
   leave every pair the page shows legible under it (VEILED) *)
fn shade_rule {number:palette}{strength:nat | strength <= 100}{level:pos | level <= 4}{left:nat | left >= 120}
  (veiled: VEILED(number, strength) | sheet: sheet(left, false, false), which: palette_theme(number), level: int level, strength: int strength)
  : [after:nat | after >= left - 120] sheet(after, false, false) = let
  val sheet = rule(sheet, shade_selector(which, level))
  val () = raw(sheet, "background-color:rgba(0,0,0,")
  val sheet = put_number(sheet, strength)
  val () = raw(sheet, "%);font-size:0;")
in close(sheet) end

(* A page turn (reader.bats): the shade over the incoming page, and
   over it page-turn, where the page being left (a copy, in .leaf, on
   the page's own ground, proven) slides off, the gap it leaves showing
   the page beneath (blank, a ground with no text, while a drag holds a
   chapter's first or last page). Its edge casts a shadow on the page
   beneath. Neither takes a tap, which goes through to the page. The
   shade is strongest in the light themes, where a shadow shows; in the
   dark ones it is weaker (Night's highlight is 4.70:1 at rest, so
   there no shade at all leaves it at 4.5:1), and the shadow and the
   slide carry the turn *)
#pub fn page_turn_rules {left:nat | left >= 3600} (sheet: sheet(left, false, false)): [after:nat | after >= left - 3600] sheet(after, false, false)

implement page_turn_rules (sheet) = let
  val sheet = rule(sheet, ".shade")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Inset(), "0")
  val sheet = lay(sheet, ZIndex(), "1")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = lay(sheet, FontSize(), "0")
  val sheet = lay(sheet, Transition(), "background-color 80ms linear")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".turn")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Inset(), "0")
  val sheet = lay(sheet, ZIndex(), "2")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = lay(sheet, PointerEvents(), "none")
  val sheet = close(sheet)
  (* idle, between turns: laid out (its copy ready) but not seen. Hidden
     by visibility, which is inherited: showing and hiding it restyles
     every node of its copy, about 2.5 microseconds each, so a chapter of
     thousands of nodes is not slid at all (_chapter_heavy, #423) *)
  val sheet = rule(sheet, ".turn.idle")
  val sheet = lay(sheet, Visibility(), "hidden")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".turn.to-up,.turn.to-down")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".leaf")
  val sheet = lay(sheet, Flex(), "0 0 100%")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, MinWidth(), "0")
  val sheet = lay(sheet, MinHeight(), "0")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = surf(S_fg_bg | sheet, RoleText(), RoleGround())
  val sheet = lay(sheet, BoxShadow(), "0 0 24px rgba(0,0,0,.4)")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".tgap")
  val sheet = lay(sheet, Flex(), "0 0 100%")
  val sheet = close(sheet)
  (* sliding right or down, the gap is first: the sheet rests at the
     strip's end *)
  val sheet = rule(sheet, ".turn.to-right .tgap,.turn.to-down .tgap")
  val sheet = lay(sheet, Order(), "-1")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".turn.blank .tgap")
  val sheet = fill(sheet, RoleGround())
  val sheet = close(sheet)
  val sheet = shade_rule(V_light_6 | sheet, Light(), 1, 6)
  val sheet = shade_rule(V_light_12 | sheet, Light(), 2, 12)
  val sheet = shade_rule(V_light_18 | sheet, Light(), 3, 18)
  val sheet = shade_rule(V_light_24 | sheet, Light(), 4, 24)
  val sheet = shade_rule(V_sepia_5 | sheet, Sepia(), 1, 5)
  val sheet = shade_rule(V_sepia_10 | sheet, Sepia(), 2, 10)
  val sheet = shade_rule(V_sepia_15 | sheet, Sepia(), 3, 15)
  val sheet = shade_rule(V_sepia_20 | sheet, Sepia(), 4, 20)
  val sheet = shade_rule(V_dark_2 | sheet, Dark(), 1, 2)
  val sheet = shade_rule(V_dark_4 | sheet, Dark(), 2, 4)
  val sheet = shade_rule(V_dark_6 | sheet, Dark(), 3, 6)
  val sheet = shade_rule(V_dark_8 | sheet, Dark(), 4, 8)
  val sheet = shade_rule(V_night_0 | sheet, Night(), 1, 0)
  val sheet = shade_rule(V_night_0 | sheet, Night(), 2, 0)
  val sheet = shade_rule(V_night_0 | sheet, Night(), 3, 0)
  val sheet = shade_rule(V_night_0 | sheet, Night(), 4, 0)
  val sheet = shade_rule(V_grey_2 | sheet, Grey(), 1, 2)
  val sheet = shade_rule(V_grey_4 | sheet, Grey(), 2, 4)
  val sheet = shade_rule(V_grey_6 | sheet, Grey(), 3, 6)
  val sheet = shade_rule(V_grey_8 | sheet, Grey(), 4, 8)
in sheet end

end
