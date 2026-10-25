prfn _static_mark_past_256 {cells:$A.cells}{i,n:nat | i < n; 256 < i} (length: $A.CLEN(cells, n), first: $A.NTH(cells, i, 63), second: BYTEAT(cells, i + 1, 62)): DECLSCAN(cells, i, SrcUtf8()) =
  DECLSCAN_mark(length, first, second)
