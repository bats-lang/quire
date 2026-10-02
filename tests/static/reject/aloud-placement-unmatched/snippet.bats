(* Where a sentence is, with a place forgotten: a sentence past the
   page shown (After) would be said where it is not shown *)
fn _static_unmatched (script: !script): bool =
  case+ _sentence_placement(script, 0) of
  | Before() => false
  | OnPage() => true
