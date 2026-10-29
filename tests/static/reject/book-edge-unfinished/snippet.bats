(* A shown edge dropped unfinished: the bar would stay on the page *)
fn _static_edge_dropped (): void =
  case+ _edge_take() of
  | ~EdgeUp(mark, _) => ()
  | other => _edge_put(other)
