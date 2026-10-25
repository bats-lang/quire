prfn _static_past_the_table {cells:$A.cells}{from,count:nat}{tried:nat | LABEL_COUNT <= tried}{label:bytes}{source:int}
  (all: ALLDIFF(cells, from, count, tried), entry: ENTRY(tried, label, source), diff: LABELDIFF(cells, from, count, label)): ALLDIFF(cells, from, count, tried + 1) = ALLDIFF_more(all, entry, diff)
