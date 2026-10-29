(* A failure's next step with StorageFull left out: a banner for it
   would say what happened and nothing to do about it (#360) *)
fn _static_remedy (failed: failure): remedy =
  case+ failed of
  | PartNotRead() => ImportAgain()
