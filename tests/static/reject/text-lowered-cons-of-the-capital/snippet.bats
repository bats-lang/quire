prfn _static_capital_not_lowered {cells:$A.cells}{from:nat}{rest:bytes} (cell: $A.NTH(cells, from, 65), lower: LOWER(65, 97), rest_lowered: LOWERED(cells, from + 1, rest))
  : LOWERED(cells, from, bcons(65, rest)) = LOWERED_cons(cell, lower, rest_lowered)
