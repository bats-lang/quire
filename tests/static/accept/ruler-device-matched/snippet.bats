(* The device of a pointer record, every constructor matched *)
fn _static_matched (device: ruler_device): bool =
  case+ device of
  | RulerDeviceMouse() => false
  | RulerDeviceTouchOrPen() => true
