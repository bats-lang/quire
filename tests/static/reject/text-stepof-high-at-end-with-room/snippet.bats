prfn _static_high_at_end_with_room {cells:$A.cells}{order:byteorder}{i,n:nat | i + 3 < n} (one: UNIT16(cells, order, i, 55296), length: $A.CLEN(cells, n))
  : STEPOF(cells, SrcUtf16(order), i, i + 2, 65533) = STEPOF_high_at_end(one, length)
