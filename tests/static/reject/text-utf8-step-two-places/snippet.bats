prfn _static_two_places {cells:$A.cells}{i,j:nat}{first_to,second_to,first_wide,second_wide:int}
  (one: UTF8STEP(cells, i, first_to, first_wide), other: UTF8STEP(cells, j, second_to, second_wide)): [first_to == second_to] void =
  utf8step_functional(one, other)
