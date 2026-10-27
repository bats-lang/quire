prfn _static_two_ends {cells:$A.cells}{from,first_to,second_to:nat | from <= first_to; from <= second_to}{first_spread,second_spread:spread}
  (one: UTF8RUN(cells, from, first_to, first_spread), other: UTF8RUN(cells, from, second_to, second_spread)): EQSPREAD(first_spread, second_spread) =
  utf8run_functional(one, other)
