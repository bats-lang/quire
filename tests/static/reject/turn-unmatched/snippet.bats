(* A page turn's outcome with one forgotten: reading would not stop
   where nothing turns *)
fn _static_turned (result: turned): bool =
  case+ result of
  | TurnedPage() => true
  | TurnedChapter() => true
