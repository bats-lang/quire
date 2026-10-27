prfn _static_ascii_of_wide {cells:$A.cells}{from,n:nat | from <= n} (length: $A.CLEN(cells, n), run: UTF8RUN(cells, from, n, SpreadWide())): UTF8SCAN(cells, from, ScannedAscii()) =
  UTF8SCAN_ascii{cells}{from, n}(length, run)
