(* a gap given as a free length: only spaced and spaced_pair write one (#500) *)
fn _static_lay_writes_gap {left:nat | left >= 40} (sheet: sheet(left, false, true)): [after:nat | after >= left - 40] sheet(after, false, true) =
  lay(sheet, Gap(), "10px")
