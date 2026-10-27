prfn _static_run_past_bad {cells:$A.cells}{from,bad_at,n:nat}{leading_spread,spread:spread}
  (leading: UTF8RUN(cells, from, bad_at, leading_spread), bad: UTF8BAD(cells, bad_at + 1), whole: UTF8RUN(cells, from, n, spread), length: $A.CLEN(cells, n)): FALSEP() =
  utf8run_bad_not_complete(leading, bad, whole, length)
