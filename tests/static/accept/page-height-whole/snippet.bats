(* A page's height given as a whole number of pixels *)
fn _static_page_height {left:nat | left >= 40}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 40] sheet(after, media, true) =
  page_height(sheet, RoundedDown())
