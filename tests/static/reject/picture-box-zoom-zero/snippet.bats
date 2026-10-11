(* A picture zoomed to nothing: a zoom is 1 to 10000 thousandths *)
fn _static_zoom (): void = let
  val width = 600
in ui_picture_box("image-full", width, 800, 0) end
