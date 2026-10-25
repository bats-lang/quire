prfn _static_two_places {cells:$A.cells}{i,j:nat}{first,second:int} (one: BYTEAT(cells, i, first), other: BYTEAT(cells, j, second)): [first == second] void =
  byteat_functional(one, other)
