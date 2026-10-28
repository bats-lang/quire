(* The device of a pointer record, with the finger or pen left out *)
fn _static_unmatched (device: ruler_device): bool =
  case+ device of
  | RulerDeviceMouse() => false
