prfn _static_two_places {cells:$A.cells}{i,j:nat}{to:int}{spread:spread} (step: UTF8STEP(cells, i, to, spread), bad: UTF8BAD(cells, j)): FALSEP() = utf8step_not_bad(step, bad)
