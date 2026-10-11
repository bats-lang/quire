(* The sheet's greatest share, with its scrolling *)
fn _static_scrolls_most {left:nat | left >= 45} (sheet: sheet(left, false, true)): [after:nat | after >= left - 45] sheet(after, false, true) =
  scrolls(sheet, ShareMost())
