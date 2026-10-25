prfn _static_isencoding_two_places {cells:$A.cells}{i,j:nat}{first,second:bool} (one: ISENCODING(cells, i, first), two: ISENCODING(cells, j, second)): [first == second] void =
  isencoding_functional(one, two)
