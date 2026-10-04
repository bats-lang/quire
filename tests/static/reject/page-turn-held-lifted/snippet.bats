(* A drag's sheet taken away as a turn's: the page would be left
   showing the page the drag was going to, not its place *)
fn _static_turn_held_lifted (): void =
  case+ _turn_take() of
  | ~TurnHeld(sheet, _, _, _) => _sheet_lift(sheet)
  | other => _turn_put(other)
