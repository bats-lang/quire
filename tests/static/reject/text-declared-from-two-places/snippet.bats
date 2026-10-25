prfn _static_declared_two_places {cells:$A.cells}{i,j:nat}{first,second:tsrc} (one: DECLARED(cells, i, first), two: DECLARED(cells, j, second)): EQSRC(first, second) =
  declared_functional(one, two)
