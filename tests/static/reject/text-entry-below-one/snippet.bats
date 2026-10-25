prfn _static_entry_below_one {index:nat}{label:bytes}{source:tsrc} (entry: ENTRY(index, label, source)): [index < 1] void = entry_below_count(entry)
