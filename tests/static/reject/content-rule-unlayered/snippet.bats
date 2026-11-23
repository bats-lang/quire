(* a content rule written with no layer open: an unlayered normal rule would beat every rule of the book (keyword: content-rule-unlayered) *)
fn _static_unlayered {left:nat | left >= 40} (sheet: sheet(left, false, false)): sheet(left - 40, false, true) =
  content_rule(() | sheet, ".caf p")
