prfn _static_past_257 {cells:$A.cells}{i:nat | 257 < i}{first,second:tsrc} (one: DECLSCAN(cells, i, first), two: DECLSCAN(cells, i, second)): EQSRC(first, second) = declscan_functional(one, two)
