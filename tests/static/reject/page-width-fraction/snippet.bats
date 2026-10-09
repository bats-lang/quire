(* A page's width given as the container's less the insets, a fraction of
   a pixel in a window that has one: the page's offsets would drift *)
fn _static_page_width {left:nat | left >= 100}{media:bool}
  (sheet: sheet(left, media, true)): [after:nat | after >= left - 100] sheet(after, media, true) =
  page_width(sheet, ContainerLessInsets())
