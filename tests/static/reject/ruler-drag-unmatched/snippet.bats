(* Whether a pointer drags it, with the dragging left out *)
fn _static_unmatched (): bool =
  case+ !_drag of
  | RulerIdle() => false
