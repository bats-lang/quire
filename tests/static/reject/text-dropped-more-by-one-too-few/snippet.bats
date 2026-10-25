prfn _static_one_too_few {cell:int}{cells,rest:$A.cells} (dropped: DROPPED(cells, 1, rest)): DROPPED($A.ccons(cell, cells), 1, rest) = DROPPED_more(dropped)
