prfn _static_after_within {cells:$A.cells}{n,i:nat | i < n} (length: $A.CLEN(cells, n)): BYTEAT(cells, i, ~1) = BYTEAT_after(length)
