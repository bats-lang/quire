prfn _static_bad_is_ascii {cells:$A.cells}{from,bad_at:nat | from <= bad_at}{leading_spread:spread} (leading: UTF8RUN(cells, from, bad_at, leading_spread), bad: UTF8BAD(cells, bad_at))
  : UTF8SCAN(cells, from, ScannedAscii()) = UTF8SCAN_bad(leading, bad)
