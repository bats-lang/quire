(* The way back kept with no position to go back to *)
fn _static_kept_empty (): void = let
  val cell = PsKept(ps_nil())
in _ps_put(cell) end
