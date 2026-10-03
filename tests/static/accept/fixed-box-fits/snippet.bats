(* A fixed page's box, its zoom the fit's *)
fn _static_zoom (): void = let
  val @(box_id, box_id_len) = _box_id(PageBox())
in ui_fixed_box_n(box_id, box_id_len, 600, 800, _fit_zoom(375, 667, 600, 800)) end
