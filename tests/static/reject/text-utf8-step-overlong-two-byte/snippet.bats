prfn _static_overlong {cells:$A.cells}{i:nat} (lead: $A.NTH(cells, i, 192), first: $A.NTH(cells, i + 1, 128)): UTF8STEP(cells, i, i + 2, 2) = UTF8STEP_two(lead, first)
