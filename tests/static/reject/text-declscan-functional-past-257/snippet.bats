prfn _static_past_257 {cells:$A.cells}{i:nat | 257 < i}{first,second:int} (one: DECLSCAN(cells, i, first), two: DECLSCAN(cells, i, second)): [first == second] void = declscan_functional(one, two)
