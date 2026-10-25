prfn _static_truncated_with_room {cells:$A.cells}{order:byteorder}{i,n:nat | i + 1 < n}{first:int} (one: $A.NTH(cells, i, first), length: $A.CLEN(cells, n))
  : STEPOF(cells, SrcUtf16(order), i, i + 1, 65533) = STEPOF_truncated(one, length)
