prfn _static_ascii_of_128 {cells:$A.cells}{page:codepage}{i:nat} (one: $A.NTH(cells, i, 128)): STEPOF(cells, SrcTable(page), i, i + 1, 128) = STEPOF_ascii(one)
