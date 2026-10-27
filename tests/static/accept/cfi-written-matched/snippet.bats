(* The answer of a writer, all three matched *)
fn _static_written_length {bn:nat} (written: cfi_written(bn)): Int =
  case+ written of
  | ~CfiWritten(length) => length
  | ~CfiNowhere() => 0
  | ~CfiNoRoom() => 0
