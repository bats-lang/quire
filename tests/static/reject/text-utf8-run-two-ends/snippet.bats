prfn _static_two_ends {cells:$A.cells}{from,first_to,second_to:nat | from <= first_to; from <= second_to}{first_wide,second_wide:int}
  (one: UTF8RUN(cells, from, first_to, first_wide), other: UTF8RUN(cells, from, second_to, second_wide)): [first_wide == second_wide] void =
  utf8run_functional(one, other)
