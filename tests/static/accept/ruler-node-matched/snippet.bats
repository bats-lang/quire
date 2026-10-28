(* The content node at a point, every constructor matched *)
fn _static_matched (): bool =
  case+ _node_at(0, 0) of
  | ~RulerNodeNone() => false
  | ~RulerNodeAt(node) => true
