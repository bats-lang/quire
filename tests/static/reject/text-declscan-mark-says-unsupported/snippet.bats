prfn _static_mark_says_unsupported {cells:$A.cells}{i,n:nat | i < n; i <= 256} (length: $A.CLEN(cells, n), first: $A.NTH(cells, i, 63), second: BYTEAT(cells, i + 1, 62)): DECLSCAN(cells, i, SrcUnsupported()) =
  DECLSCAN_mark(length, first, second)
