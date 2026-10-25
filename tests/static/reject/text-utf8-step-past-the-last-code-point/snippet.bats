prfn _static_past_last {cells:$A.cells}{i:nat} (lead: $A.NTH(cells, i, 244), first: $A.NTH(cells, i + 1, 144), second: $A.NTH(cells, i + 2, 128), third: $A.NTH(cells, i + 3, 128))
  : UTF8STEP(cells, i, i + 4, 2) = UTF8STEP_four(lead, first, second, third)
