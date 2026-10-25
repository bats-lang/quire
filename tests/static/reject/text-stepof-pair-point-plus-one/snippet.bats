prfn _static_pair_point_plus_one {cells:$A.cells}{source:int | source == 1 || source == 2}{i:nat} (one: UNIT16(cells, source, i, 55296), two: UNIT16(cells, source, i + 2, 56320))
  : STEPOF(cells, source, i, i + 4, 65537) = STEPOF_pair(one, two)
