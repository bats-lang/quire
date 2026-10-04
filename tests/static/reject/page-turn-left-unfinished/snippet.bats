(* A sliding turn dropped unfinished: the page being left would stay
   over the page, which has moved on *)
fn _static_turn_dropped (): void =
  case+ _turn_take() of
  | ~TurnSliding(sheet, _, _, _, _) => ()
  | other => _turn_put(other)
