prfn _static_skips_a_byte {cells:$A.cells}{i:nat} (lead: $A.NTH(cells, i, 65)): UTF8RUN(cells, i, i + 2, 1) =
  UTF8RUN_ascii(UTF8STEP_one(lead), UTF8RUN_empty())
