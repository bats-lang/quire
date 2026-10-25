prfn _static_unit_two_places {cells:$A.cells}{order:byteorder}{i,j:nat}{first,second:int} (one: UNIT16(cells, order, i, first), two: UNIT16(cells, order, j, second)): [first == second] void =
  unit16_functional(one, two)
