prfn _static_run_scan_two_places {cells:$A.cells}{from,other,n:nat | from <= n}{spread:spread} (run: UTF8RUN(cells, from, n, spread), length: $A.CLEN(cells, n), scan: UTF8SCAN(cells, other, ScannedRefused())): FALSEP() =
  utf8run_refused_not_complete(run, length, scan)
