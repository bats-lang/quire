prfn _static_declared_two_places {cells:$A.cells}{i,j:nat}{first,second:int} (one: DECLARED(cells, i, first), two: DECLARED(cells, j, second)): [first == second] void =
  declared_functional(one, two)
