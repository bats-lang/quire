prfn _static_labelsrc_two_places {cells:$A.cells}{from,count,other:nat}{first,second:tsrc}
  (one: LABELSRC(cells, from, count, first), two: LABELSRC(cells, other, count, second)): EQSRC(first, second) = labelsrc_functional(one, two)
