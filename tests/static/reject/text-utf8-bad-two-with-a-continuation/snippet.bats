prfn _static_good_continuation {cells:$A.cells}{i:nat} (lead: $A.NTH(cells, i, 195), first: $A.NTH(cells, i + 1, 169)): UTF8BAD(cells, i) =
  UTF8BAD_two(lead, BYTEAT_in(first))
