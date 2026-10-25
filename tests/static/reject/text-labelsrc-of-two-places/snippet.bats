prfn _static_labelsrc_two_places {cells:$A.cells}{from,count,other:nat}{first,second:int}
  (one: LABELSRC(cells, from, count, first), two: LABELSRC(cells, other, count, second)): [first == second] void = labelsrc_functional(one, two)
