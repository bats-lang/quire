prfn _static_step_two_places {cells:$A.cells}{source:tsrc}{i,j:nat}{first_to,second_to,first_point,second_point:int}
  (one: STEPOF(cells, source, i, first_to, first_point), two: STEPOF(cells, source, j, second_to, second_point)): [first_point == second_point] void = stepof_functional(one, two)
