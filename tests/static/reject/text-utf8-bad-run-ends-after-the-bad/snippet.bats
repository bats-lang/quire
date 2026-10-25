prfn _static_run_past_bad {cells:$A.cells}{from,bad_at,n:nat}{leading_wide,wide:int}
  (leading: UTF8RUN(cells, from, bad_at, leading_wide), bad: UTF8BAD(cells, bad_at + 1), whole: UTF8RUN(cells, from, n, wide), length: $A.CLEN(cells, n)): FALSEP() =
  utf8run_bad_not_complete(leading, bad, whole, length)
