(* What a pointer record says, with the page hidden left out *)
fn _static_unmatched (record: ruler_record): bool =
  case+ record of
  | RulerRecordDown() => true
