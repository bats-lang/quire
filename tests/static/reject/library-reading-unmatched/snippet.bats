(* The library's reading with the unreadable case forgotten: a file
   handed over then would be neither imported nor kept (#262) *)
fn _static_unmatched (reading: library_reading): void =
  case+ reading of
  | ~LibraryRead(pf | ) => _external_wait(pf | 1)
