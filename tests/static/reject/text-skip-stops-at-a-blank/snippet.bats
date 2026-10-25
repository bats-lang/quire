prfn _static_stop_at_blank {cells:$A.cells}{from,to:nat} (blanks: BLANKS(cells, from, to), cell: $A.NTH(cells, to, 32)): SKIP(cells, from, to) = SKIP_stop(blanks, BYTEAT_in(cell))
