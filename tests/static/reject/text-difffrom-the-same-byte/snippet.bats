prfn _static_same_byte {cells:$A.cells}{from:nat}{rest:bytes} (cell: $A.NTH(cells, from, 97), lower: LOWER(97, 97)): DIFFFROM(cells, from, bcons(97, rest)) = DIFFFROM_head(cell, lower)
