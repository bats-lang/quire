prfn _static_high_alone_before_low {cells:$A.cells}{order:byteorder}{i:nat} (one: UNIT16(cells, order, i, 55296), two: UNIT16(cells, order, i + 2, 56320))
  : STEPOF(cells, SrcUtf16(order), i, i + 2, 65533) = STEPOF_high_alone(one, two)
