prfn _static_nth_past_end {cells:$A.cells}{n,i:nat | n <= i} (length: $A.CLEN(cells, n)): [value:int] $A.NTH(cells, i, value) = nth_exists(length)
