(* Every edge ended: a shown one cleared *)
fn _static_edge_ended (): void =
  case+ _edge_take() of
  | ~EdgeUp(mark, _) => _edge_clear(mark)
  | ~EdgeNone() => ()
