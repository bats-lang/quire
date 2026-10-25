prfn _static_wide_three {cells:$A.cells}{from,n:nat | from <= n} (length: $A.CLEN(cells, n), run: UTF8RUN(cells, from, n, 3)): UTF8SCAN(cells, from, 3) = UTF8SCAN_whole(length, run)
