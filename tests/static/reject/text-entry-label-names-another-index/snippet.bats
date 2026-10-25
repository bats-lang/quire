prfn _static_label_another_index {first,second:nat}{label:bytes}{first_source,second_source:tsrc}
  (one: LABELENTRY(first, label, first_source), two: LABELENTRY(second, label, second_source)): EQI(first, second + 1) = entry_label_injective(one, two)
