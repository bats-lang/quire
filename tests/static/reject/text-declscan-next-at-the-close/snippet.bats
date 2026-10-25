prfn _static_next_at_close {cells:$A.cells}{i,n:nat | i < n; i <= 256}{source:int}
  (length: $A.CLEN(cells, n), first: BYTEAT(cells, i, 63), second: BYTEAT(cells, i + 1, 62), plain: ISENCODING(cells, i, false), rest: DECLSCAN(cells, i + 1, source)): DECLSCAN(cells, i, source) =
  DECLSCAN_next(length, first, second, plain, rest)
