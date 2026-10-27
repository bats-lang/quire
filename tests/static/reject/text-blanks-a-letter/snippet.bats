prfn _static_letter_is_blank {cells:$A.cells}{i:nat} (cell: $A.NTH(cells, i, 97)): BLANKS(cells, i, i + 1) = BLANKS_more(cell, BLANKS_none())
