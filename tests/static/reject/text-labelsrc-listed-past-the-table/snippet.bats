prfn _static_listed_past_the_table {cells:$A.cells}{from,count:nat}{index:nat | LABEL_COUNT <= index}{label:bytes}{source:int}
  (entry: ENTRY(index, label, source), is: LABELIS(cells, from, count, label)): LABELSRC(cells, from, count, source) = LABELSRC_listed(entry, is)
