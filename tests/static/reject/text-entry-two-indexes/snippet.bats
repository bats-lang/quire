prfn _static_entry_two_indexes {first,second:nat}{first_label,second_label:bytes}{first_source,second_source:tsrc}
  (one: LABELENTRY(first, first_label, first_source), two: LABELENTRY(second, second_label, second_source)): EQB(first_label, second_label) =
  let prval (same, _) = entry_functional(one, two) in same end
