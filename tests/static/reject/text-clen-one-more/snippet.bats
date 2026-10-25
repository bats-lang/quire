prfn _static_one_more {cells:$A.cells}{first,second:nat} (one: $A.CLEN(cells, first), other: $A.CLEN(cells, second)): [first + 1 == second] void = clen_functional(one, other)
