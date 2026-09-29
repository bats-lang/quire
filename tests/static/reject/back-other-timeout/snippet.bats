(* The proof for timeout 1, used to show the button as timeout 2's *)
fn _static_other (): void = let
  val (pf | ()) = _timed_arm(1, lam(h) => ())
in _ps_put(PsShown(pf | 2, ps_cons(0, 0, 0, ps_nil()))) end
