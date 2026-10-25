prfn _static_two_places {cells:$A.cells}{i,j:nat}{first_to,second_to:int}{first_spread,second_spread:spread}
  (one: UTF8STEP(cells, i, first_to, first_spread), other: UTF8STEP(cells, j, second_to, second_spread))
  : (EQI(first_to, second_to), EQSPREAD(first_spread, second_spread)) = utf8step_functional(one, other)
