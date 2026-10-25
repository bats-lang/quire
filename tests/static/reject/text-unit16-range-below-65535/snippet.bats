prfn _static_unit_below_65535 {cells:$A.cells}{source:int}{i:nat}{unit:int} (one: UNIT16(cells, source, i, unit)): [unit < 65535] void = unit16_range(one)
