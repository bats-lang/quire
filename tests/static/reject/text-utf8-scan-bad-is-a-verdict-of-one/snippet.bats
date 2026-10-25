prfn _static_bad_is_one {cells:$A.cells}{from,bad_at:nat | from <= bad_at}{leading_wide:int} (leading: UTF8RUN(cells, from, bad_at, leading_wide), bad: UTF8BAD(cells, bad_at))
  : UTF8SCAN(cells, from, 1) = UTF8SCAN_bad(leading, bad)
