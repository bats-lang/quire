prfn _static_pair_point_plus_one {cells:$A.cells}{order:byteorder}{i:nat} (one: UNIT16(cells, order, i, 55296), two: UNIT16(cells, order, i + 2, 56320))
  : STEPOF(cells, SrcUtf16(order), i, i + 4, 65537) = STEPOF_pair(one, two)
