(* A turn's sheet shown with the copy _copy_ready gives, then hidden *)
fn _static_copy_fresh (): void = let
  val () = _sheet_show(_copy_ready(), SlideLeft(), BeneathPage())
in _sheet_hide() end
