(* adaptive_rules -- the spacing scale on the screens and the rules that
   change with the window's width *)

#target wasm begin

#include "share/atspre_staload.hats"
staload "palette.sats"
staload "palette_proofs.sats"
staload "sheet.sats"
staload "declarations.sats"

(* The spacing scale on the screens (#331): the least inset given to the
   page (--space-inset, the e2e walk's minimum); a full screen's rows and
   notes drawn as cards (Material's list item: 8 px above and below, 16
   px at the sides, so no button touches a card's edge) that wrap
   rather than cut a button; a panel opened as a dialog 16 px round
   its content. And the Sync screen's parts: its status card (where,
   how it went, its actions), its footer note, and its sign-in step,
   which hides the screen's list while it is shown *)
#pub fn spacing_rules {left:nat | left >= 1600} (sheet: sheet(left, false, false)): [after:nat | after >= left - 1600] sheet(after, false, false)

implement spacing_rules (sheet) = let
  val sheet = rule(sheet, ":root")
  val () = raw(sheet, "--space-inset:")
  val () = raw(sheet, space_length(space_inset()))
  val () = raw(sheet, ";")
  (* each side's safe area (the system's bars and a cutout over the
     page, #341) and the least inset beyond it, or nothing where the
     side has none: what a screen, panel, sheet or bar pads that side
     by, so nothing of it comes near a bar *)
  val () = raw(sheet, "--safe-top:min(env(safe-area-inset-top)*1000,env(safe-area-inset-top) + var(--space-inset));")
  val () = raw(sheet, "--safe-right:min(env(safe-area-inset-right)*1000,env(safe-area-inset-right) + var(--space-inset));")
  val () = raw(sheet, "--safe-bottom:min(env(safe-area-inset-bottom)*1000,env(safe-area-inset-bottom) + var(--space-inset));")
  val () = raw(sheet, "--safe-left:min(env(safe-area-inset-left)*1000,env(safe-area-inset-left) + var(--space-inset));")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".menu[role=dialog]")
  val sheet = spaced(sheet, Padding(), SpaceLarge())
  val sheet = spaced(sheet, Gap(), SpaceSmall())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".info .srow")
  val sheet = spaced_pair(sheet, Padding(), SpaceSmall(), SpaceLarge())
  val sheet = lay(sheet, BorderRadius(), "12px")
  val sheet = lay(sheet, FlexWrap(), "wrap")
  val sheet = lay(sheet, AlignItems(), "center")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".info-in>.sabout,.info-in>.cnone,.scard")
  val sheet = spaced_pair(sheet, Padding(), SpaceMedium(), SpaceLarge())
  val sheet = lay(sheet, BorderRadius(), "12px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".scard")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = spaced(sheet, Gap(), SpaceSmall())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".swhere")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = close(sheet)
  (* a sign-in step's words, on the screen's own ground *)
  val sheet = rule(sheet, ".stext")
  val sheet = surf(S_fg_bg | sheet, RoleText(), RoleGround())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".snote")
  val sheet = surf(S_muted_bg | sheet, RoleMuted(), RoleGround())
  val sheet = lay(sheet, FontSize(), "13px")
  val sheet = spaced_pair(sheet, Padding(), SpaceTight(), SpaceLarge())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sstep")
  val sheet = lay(sheet, Display(), "flex")
  val sheet = lay(sheet, FlexDirection(), "column")
  val sheet = spaced(sheet, Gap(), SpaceSmall())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".sstep:not([data-hide='1'])~*")
  val sheet = lay(sheet, Display(), "none")
  val sheet = close(sheet)
in sheet end

#pub fn under_480px_rules {left:nat | left >= 480} (sheet: sheet(left, false, false)): [after:nat | after >= left - 480] sheet(after, false, false)

implement under_480px_rules (sheet) = let
  val sheet = media(sheet, "(max-width:480px)")
  val sheet = rule(sheet, ".lib")
  val sheet = lay(sheet, PaddingLeft(), "max(10px,var(--safe-left))")
  val sheet = lay(sheet, PaddingRight(), "max(10px,var(--safe-right))")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".ttl")
  val sheet = lay(sheet, FontSize(), "20px")
  val sheet = lay(sheet, Flex(), "1 1 0")
  val sheet = lay(sheet, MinWidth(), "0")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".bar>.ibtn")
  val sheet = lay(sheet, Order(), "1")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".bar>.btn")
  val sheet = lay(sheet, Order(), "2")
  val sheet = lay(sheet, Padding(), "8px 9px")
  val sheet = lay(sheet, FontSize(), "14px")
  val sheet = close(sheet)
  val sheet = rule(sheet, ".bar>.sfield")
  val sheet = lay(sheet, Order(), "3")
  val sheet = close(sheet)
  (* the page indicator's title and " · page ": read out, not shown
     (the title is in the top bar, and the pages show in full, "1 of 12
     in chapter") *)
  val sheet = rule(sheet, ".pinfo .pgt,.pgw")
  val sheet = lay(sheet, Position(), "absolute")
  val sheet = lay(sheet, Width(), "1px")
  val sheet = lay(sheet, Height(), "1px")
  val sheet = lay(sheet, Margin(), "-1px")
  val sheet = lay(sheet, Overflow(), "hidden")
  val sheet = close(sheet)
  val sheet = media_end(sheet)
in sheet end

#pub fn under_600px_rules {left:nat | left >= 57} (sheet: sheet(left, false, false)): [after:nat | after >= left - 57] sheet(after, false, false)

implement under_600px_rules (sheet) = let
  val sheet = media(sheet, "(max-width:600px)")
  val sheet = rule(sheet, ".caf p")
  val sheet = lay(sheet, TextAlign(), "start")
  val sheet = close(sheet)
  val sheet = media_end(sheet)
in sheet end

end
