prfn _static_past_the_tried {cells:$A.cells}{from,count,tried,index:nat | tried <= index}{label:bytes}{source:tsrc}
  (all: ALLDIFF(cells, from, count, tried), entry: LABELENTRY(index, label, source)): LABELDIFF(cells, from, count, label) = alldiff_get(all, entry)
