prfn _static_two_byte_is_ascii {cells:$A.cells}{i:nat} (lead: $A.NTH(cells, i, 195), first: $A.NTH(cells, i + 1, 169)): UTF8STEP(cells, i, i + 2, 1) = UTF8STEP_two(lead, first)
