(* A page's height given as a whole number of pixels *)
fn _static_page_height (): void = let
  val _ = page_height_rule(RoundedDown())
in () end
