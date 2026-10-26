(* the underline given the proof of another edge: only EDGEP(FG, BG) is the text colour's (keyword: reading ruler) *)
fn _static_ruler_underline_other_edge {left:nat | left >= 48} (sheet: sheet(left, false, true)): [after:nat | after >= left - 48] sheet(after, false, true) =
  underline(E_edge_card | sheet, RoleText(), RoleGround())
