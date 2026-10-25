prfn _static_quote_is_not_quote {cells:$A.cells}{i:nat} (cell: $A.NTH(cells, i, 34)): NOQUOTE(cells, 34, i, i + 1) = NOQUOTE_more(cell, NOQUOTE_none())
