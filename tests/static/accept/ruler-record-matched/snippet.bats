(* What a pointer record says, every constructor matched *)
fn _static_matched (record: ruler_record): bool =
  case+ record of
  | RulerRecordDown() => true
  | RulerRecordMove() => true
  | RulerRecordUp() => true
  | RulerRecordCancel() => true
  | RulerRecordHidden() => false
  | RulerRecordOther() => false
