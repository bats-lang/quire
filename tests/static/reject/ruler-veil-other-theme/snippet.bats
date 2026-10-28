(* a veil proven for the light theme written for the dark one (keyword: reading ruler) *)
fn _static_ruler_veil_other_theme {left:nat | left >= 120} (sheet: sheet(left, false, false)): [after:nat | after >= left - 120] sheet(after, false, false) =
  dim_rule(D_light_25 | sheet, Dark(), 25)
