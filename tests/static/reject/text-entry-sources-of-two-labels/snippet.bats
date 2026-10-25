prfn _static_entry_sources {index:nat}{first_label,second_label:bytes}{first_source,second_source:tsrc}
  (one: ENTRY(index, first_label, first_source), two: ENTRY(index, second_label, second_source)): EQSRC(first_source, SrcUtf8()) =
  let prval (_, same) = entry_functional(one, two) in same end
