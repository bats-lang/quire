prfn _static_dropped_two_counts {cells:$A.cells}{count:nat}{first,second:$A.cells} (one: DROPPED(cells, count, first), two: DROPPED(cells, count + 1, second)): EQCELLS(first, second) =
  dropped_functional(one, two)
