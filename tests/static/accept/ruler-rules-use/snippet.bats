(* the ruler's colours each under its own proof (keyword: reading ruler) *)
fn _static_ruler_rules_use {left:nat | left >= 240} (sheet: sheet(left, false, false)): [after:nat | after >= left - 240] sheet(after, false, false) = let
  val sheet = rule(sheet, ".static-ruler")
  val sheet = underline(E_fg_bg | sheet, RoleText(), RoleGround())
  val sheet = band(R_ruler | sheet, RoleRuler())
  val sheet = close(sheet)
in dim_rule(D_dark_40 | sheet, Dark(), 40) end
