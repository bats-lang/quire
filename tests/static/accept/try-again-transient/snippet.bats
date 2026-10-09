(* Try again for a transient failure (UnknownError), which has hope *)
fn _static_try_again (): void = ui_try_again_show(HopeTransient() | )
