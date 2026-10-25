prfn _static_continuation_alone {cells:$A.cells}{i:nat} (lead: $A.NTH(cells, i, 128)): UTF8STEP(cells, i, i + 1, SpreadAscii()) = UTF8STEP_one(lead)
