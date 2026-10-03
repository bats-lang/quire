(* Every turn ended: a drag's sheet put back, a turn's lifted *)
fn _static_turn_ended (): void =
  case+ _turn_take() of
  | ~TurnHeld(sheet, _, _, _) => _sheet_put_back(sheet)
  | ~TurnReturning(sheet, _, _, _, _) => _sheet_put_back(sheet)
  | ~TurnWaiting(sheet, _, _, _) => _sheet_lift(sheet)
  | ~TurnSliding(sheet, _, _, _, _) => _sheet_lift(sheet)
  | ~TurnStill() => ()
