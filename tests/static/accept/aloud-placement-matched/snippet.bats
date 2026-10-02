(* Where a sentence is, every place matched *)
fn _static_matched (script: !script): bool =
  case+ _sentence_placement(script, 0) of
  | Before() => false
  | OnPage() => true
  | After() => false
