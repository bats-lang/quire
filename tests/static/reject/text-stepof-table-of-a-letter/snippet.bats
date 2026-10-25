prfn _static_table_of_a_letter {cells:$A.cells}{i:nat}{point:int} (one: $A.NTH(cells, i, 65), table: TABLEAT(6, 65, point)): STEPOF(cells, 6, i, i + 1, point) = STEPOF_table(one, table)
