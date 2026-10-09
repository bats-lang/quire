(* A page's width given as a whole number of pixels *)
fn _static_page_width {left:nat | left >= 100}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 100] sheet(after, media, true) =
  page_width(sheet, RoundedDown())
