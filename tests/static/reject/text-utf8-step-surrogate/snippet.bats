prfn _static_surrogate {cells:$A.cells}{i:nat} (lead: $A.NTH(cells, i, 237), first: $A.NTH(cells, i + 1, 160), second: $A.NTH(cells, i + 2, 128))
  : UTF8STEP(cells, i, i + 3, SpreadWide()) = UTF8STEP_three(lead, first, second)
