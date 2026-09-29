(* The button shown with no position to go back to *)
fn _static_empty (): void = let
  val (pf | g) = _back_arm()
in _ps_put(PsShown(pf | g, ps_nil())) end
