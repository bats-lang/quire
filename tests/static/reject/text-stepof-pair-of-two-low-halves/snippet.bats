prfn _static_pair_of_lows {cells:$A.cells}{source:int | source == 1 || source == 2}{i:nat} (one: UNIT16(cells, source, i, 56320), two: UNIT16(cells, source, i + 2, 56320))
  : STEPOF(cells, source, i, i + 4, 65536) = STEPOF_pair(one, two)
