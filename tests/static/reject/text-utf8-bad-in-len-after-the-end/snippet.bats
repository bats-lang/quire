prfn _static_bad_after_the_end {cells:$A.cells}{i,n:nat} (bad: UTF8BAD(cells, i), length: $A.CLEN(cells, n)): [i + 1 < n] void = utf8bad_in_len(bad, length)
