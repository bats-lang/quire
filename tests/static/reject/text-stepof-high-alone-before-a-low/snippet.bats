prfn _static_high_alone_before_low {cells:$A.cells}{source:int | source == 1 || source == 2}{i:nat} (one: UNIT16(cells, source, i, 55296), two: UNIT16(cells, source, i + 2, 56320))
  : STEPOF(cells, source, i, i + 2, 65533) = STEPOF_high_alone(one, two)
