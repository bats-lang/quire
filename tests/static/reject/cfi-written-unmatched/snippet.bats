(* The answer of a writer, with "does not fit" left out: a caller would take a
   buffer that was too small for a position that is nowhere (#901) *)
fn _static_written_length {bn:nat} (written: cfi_written(bn)): Int =
  case+ written of
  | ~CfiWritten(length) => length
  | ~CfiNowhere() => 0
