prfn _static_skip_two_places {cells:$A.cells}{from,other,first_to,second_to:nat | from <= first_to; other <= second_to}
  (one: SKIP(cells, from, first_to), two: SKIP(cells, other, second_to)): [first_to == second_to] void = skip_functional(one, two)
