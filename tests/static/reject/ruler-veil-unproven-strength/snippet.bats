(* a veil of a strength no DIMMED proves for the theme (keyword: reading ruler) *)
fn _static_ruler_veil_unproven_strength {left:nat | left >= 120} (sheet: sheet(left, false, false)): [after:nat | after >= left - 120] sheet(after, false, false) =
  dim_rule(D_light_25 | sheet, Light(), 30)
