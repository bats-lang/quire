(* a scrolling cap over the sheet share: only scrolls and capped write a max-height (#500) *)
fn _static_lay_writes_max_height {left:nat | left >= 40} (sheet: sheet(left, false, true)): [after:nat | after >= left - 40] sheet(after, false, true) =
  lay(sheet, MaxHeight(), "90dvh")
