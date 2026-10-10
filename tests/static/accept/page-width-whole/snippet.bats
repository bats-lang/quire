(* A page's width given as a whole number of pixels *)
fn _static_page_width (): void = let
  val _ = page_width_rule(RoundedDown())
in () end
