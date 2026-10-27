prfn _static_snoc_letter {cells:$A.cells}{from,to:nat | from <= to} (blanks: BLANKS(cells, from, to), cell: $A.NTH(cells, to, 97)): BLANKS(cells, from, to + 1) = blanks_snoc(blanks, cell)
