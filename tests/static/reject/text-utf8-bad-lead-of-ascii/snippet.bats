prfn _static_ascii_is_bad {cells:$A.cells}{i:nat} (lead: $A.NTH(cells, i, 65)): UTF8BAD(cells, i) = UTF8BAD_lead(lead)
