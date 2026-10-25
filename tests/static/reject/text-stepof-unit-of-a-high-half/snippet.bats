prfn _static_unit_of_high {cells:$A.cells}{source:int | source == 1 || source == 2}{i:nat} (one: UNIT16(cells, source, i, 55296)): STEPOF(cells, source, i, i + 2, 55296) = STEPOF_unit(one)
