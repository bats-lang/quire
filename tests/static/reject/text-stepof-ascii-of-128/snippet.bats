prfn _static_ascii_of_128 {cells:$A.cells}{source:int | 4 <= source; source <= 17}{i:nat} (one: $A.NTH(cells, i, 128)): STEPOF(cells, source, i, i + 1, 128) = STEPOF_ascii(one)
