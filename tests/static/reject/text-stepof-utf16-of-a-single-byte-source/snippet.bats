prfn _static_unit_of_single_source {cells:$A.cells}{i:nat}{unit:int | unit < 55296} (one: UNIT16(cells, 4, i, unit)): STEPOF(cells, 4, i, i + 2, unit) = STEPOF_unit(one)
