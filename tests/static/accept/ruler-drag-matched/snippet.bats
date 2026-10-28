(* Whether a pointer drags it, every constructor matched *)
fn _static_matched (): bool =
  case+ !_drag of
  | RulerIdle() => false
  | RulerDragging() => true
