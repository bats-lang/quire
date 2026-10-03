(* A fixed page zoomed to nothing: a zoom is 1 to 10000 thousandths *)
fn _static_zoom (): void = let
  val @(box_id, box_id_len) = _box_id(PageBox())
in ui_fixed_box_n(box_id, box_id_len, 600, 800, 0) end
