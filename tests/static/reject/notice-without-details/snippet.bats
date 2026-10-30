(* A failure's details with HandedBookNotAdded left out: its banner would
   offer no Copy details, and a report of it would carry nothing (#507) *)
fn _static_details (failed: failure): detail_source =
  case+ failed of
  | LibraryNotAdded() => FromFailureAlone()
