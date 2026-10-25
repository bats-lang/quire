prfn _static_high_at_end_with_room {cells:$A.cells}{source:int | source == 1 || source == 2}{i,n:nat | i + 3 < n} (one: UNIT16(cells, source, i, 55296), length: $A.CLEN(cells, n))
  : STEPOF(cells, source, i, i + 2, 65533) = STEPOF_high_at_end(one, length)
