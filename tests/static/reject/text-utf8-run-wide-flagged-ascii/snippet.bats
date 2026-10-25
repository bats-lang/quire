prfn _static_wide_flagged_ascii {cells:$A.cells}{i:nat} (lead: $A.NTH(cells, i, 195), first: $A.NTH(cells, i + 1, 169)): UTF8RUN(cells, i, i + 2, SpreadAscii()) =
  UTF8RUN_wide(UTF8STEP_two(lead, first), UTF8RUN_empty())
