prfn _static_drop_past_the_end {cells:$A.cells}{count,n:nat | n < count} (length: $A.CLEN(cells, n)): [rest:$A.cells] (DROPPED(cells, count, rest), $A.CLEN(rest, n - count)) = dropped_exists(length)
