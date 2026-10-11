(* a padding given as a free length, off the spacing scale (#500) *)
fn _static_lay_writes_padding {left:nat | left >= 40} (sheet: sheet(left, false, true)): [after:nat | after >= left - 40] sheet(after, false, true) =
  lay(sheet, Padding(), "10px 14px")
