prfn _static_pair_of_lows {cells:$A.cells}{order:byteorder}{i:nat} (one: UNIT16(cells, order, i, 56320), two: UNIT16(cells, order, i + 2, 56320))
  : STEPOF(cells, SrcUtf16(order), i, i + 4, 65536) = STEPOF_pair(one, two)
