prfn _static_holds_past_end {cells:$A.cells}{i,count,n:nat | n < i + count} (length: $A.CLEN(cells, n)): [octets:bytes] HOLDS(cells, i, octets, count) = holds_exists(length)
