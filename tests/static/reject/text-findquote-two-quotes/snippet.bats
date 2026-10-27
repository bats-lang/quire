prfn _static_two_quotes {cells:$A.cells}{from,first_to,second_to:nat | from <= first_to; from <= second_to}
  (one: FINDQUOTE(cells, 34, from, first_to), two: FINDQUOTE(cells, 39, from, second_to)): [first_to == second_to] void = findquote_functional(one, two)
