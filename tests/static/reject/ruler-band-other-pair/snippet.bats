(* the grey bar given the proof of another pair: only RULED(RULER) is the band's (keyword: reading ruler) *)
fn _static_ruler_band_other_pair {left:nat | left >= 50} (sheet: sheet(left, false, true)): [after:nat | after >= left - 50] sheet(after, false, true) =
  band(S_fg_bg | sheet, RoleRuler())
