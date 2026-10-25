prfn _static_unit_two_on {cells:$A.cells}{order:byteorder}{i,n:nat}{unit:int} (one: UNIT16(cells, order, i, unit), length: $A.CLEN(cells, n)): [i + 2 < n] void = unit16_in_len(one, length)
