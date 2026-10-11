(* A sheet over 60% of the window: the page would keep under 40% *)
fn _static_over_share {left:nat | left >= 45} (sheet: sheet(left, false, true), share: sheet_share(85)): [after:nat | after >= left - 45] sheet(after, false, true) =
  scrolls(sheet, share)
