(* An import's outcome told with the kept book forgotten: answering
   "skip" would leave nothing said, and the outcome unfreed *)
fn _static_outcome_text (outcome: import_outcome): string =
  case+ outcome of
  | ~Added(_) => "Added to your library."
  | ~Failed() => "This book could not be imported."
