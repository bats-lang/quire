(* Try again for a library the browser blocks (SecurityError): only a
   transient failure has the proof HOPE, so this has none to carry *)
fn _static_try_again (): remedy = TryAgain(HopeTransient() | IsStorageBlocked())
