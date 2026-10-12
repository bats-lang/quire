(* theme_swatch_rules -- the reading settings' theme choice as a swatch a
   theme (quire#501): each button wears its theme's own class (th-light,
   th-sepia, ...), which sets the palette's variables on it, so its text
   on its card is that theme's pair, proven in every theme (S_fg_card),
   and a chosen swatch has the theme's accent as a line round it and an
   underline, proven on the card (E_accent_card). The word is the
   button's name (aria-label); the swatch shows "Aa" in the theme's text
   colour, a sample of the type on the page *)

#target wasm begin

#include "share/atspre_staload.hats"
staload "palette.sats"
staload "palette_proofs.sats"
staload "sheet.sats"
staload "declarations.sats"

#pub fn theme_swatch_rules {left:nat | left >= 600} (sheet: sheet(left, false, false)): [after:nat | after >= left - 600] sheet(after, false, false)

implement theme_swatch_rules (sheet) = let
  prval _ = E_accent_card
  val sheet = rule(sheet, ".seg button.themesw")
  val sheet = lay(sheet, Flex(), "none")
  val sheet = lay(sheet, Width(), "56px")
  val sheet = lay(sheet, Height(), "56px")
  val sheet = lay(sheet, BorderRadius(), "8px")
  val sheet = lay(sheet, FontSize(), "20px")
  val sheet = lay(sheet, FontWeight(), "bold")
  val sheet = spaced(sheet, Padding(), SpaceTight())
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = line(sheet, AllSides(), 1, RoleLine())
  val sheet = underline(E_accent_card | sheet, RoleAccent(), RoleCard())
  val sheet = close(sheet)
  val sheet = rule(sheet, ".seg button.themesw::before")
  val () = raw(sheet, "content:\"Aa\";")
  val sheet = close(sheet)
  (* the chosen theme: the swatch ringed in its accent *)
  val sheet = rule(sheet, ".seg button.themesw[aria-pressed=true]")
  val sheet = surf(S_fg_card | sheet, RoleText(), RoleCard())
  val sheet = line(sheet, AllSides(), 3, RoleAccent())
  val sheet = close(sheet)
in sheet end

end
