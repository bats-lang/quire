(* a box scrolled with no cap: only scrolling, clips and scrolls write overflow (#500) *)
fn _static_lay_writes_overflow {left:nat | left >= 40} (sheet: sheet(left, false, true)): [after:nat | after >= left - 40] sheet(after, false, true) =
  lay(sheet, Overflow(), "auto")
