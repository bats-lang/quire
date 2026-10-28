(* The content node at a point, with none left out: a point on no node would be taken as one *)
fn _static_unmatched (): bool =
  case+ _node_at(0, 0) of
  | ~RulerNodeAt(node) => true
