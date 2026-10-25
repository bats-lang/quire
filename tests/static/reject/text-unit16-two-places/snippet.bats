prfn _static_unit_two_places {cells:$A.cells}{source:int}{i,j:nat}{first,second:int} (one: UNIT16(cells, source, i, first), two: UNIT16(cells, source, j, second)): [first == second] void =
  unit16_functional(one, two)
