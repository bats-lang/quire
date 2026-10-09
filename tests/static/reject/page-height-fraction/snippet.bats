(* A page's height given as the container's, a fraction of a pixel in a
   window that has one: a vertical book's pages would drift down the page *)
fn _static_page_height {left:nat | left >= 40}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 40] sheet(after, media, true) =
  page_height(sheet, ContainerLessInsets())
