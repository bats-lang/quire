prfn _static_ascii_flagged_wide {cells:$A.cells}{i:nat} (lead: $A.NTH(cells, i, 65)): UTF8RUN(cells, i, i + 1, 2) =
  UTF8RUN_ascii(UTF8STEP_one(lead), UTF8RUN_empty())
