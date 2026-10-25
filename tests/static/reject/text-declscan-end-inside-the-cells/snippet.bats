prfn _static_end_inside {cells:$A.cells}{i,n:nat | i < n} (length: $A.CLEN(cells, n)): DECLSCAN(cells, i, SrcUtf8()) = DECLSCAN_end(length)
