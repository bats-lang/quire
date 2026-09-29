(* A proof that a timeout is armed, made without arming one *)
fn _static_forged (): void = _ps_put(PsShown(TimedArmed() | 5, ps_cons(0, 0, 0, ps_nil())))
