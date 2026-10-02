(* The search bar's buttons with its close forgotten: a click on it
   would do nothing *)
fn _static_search_nav (control: search_nav_control): void =
  case+ control of
  | SearchPrevious() => reader_search_step(~1)
  | SearchNext() => reader_search_step(1)
