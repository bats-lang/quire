prfn _static_valid_first {cells:$A.cells}{i:nat} (lead: $A.NTH(cells, i, 224), first: $A.NTH(cells, i + 1, 160)): UTF8BAD(cells, i) =
  UTF8BAD_three_first(lead, BYTEAT_in(first))
