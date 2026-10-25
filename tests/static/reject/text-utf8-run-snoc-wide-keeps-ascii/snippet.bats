prfn _static_snoc_wide_keeps_ascii {cells:$A.cells}{from,to:nat | from <= to} (run: UTF8RUN(cells, from, to, SpreadAscii()), lead: $A.NTH(cells, to, 195), first: $A.NTH(cells, to + 1, 169))
  : UTF8RUN(cells, from, to + 2, SpreadAscii()) = utf8run_snoc_wide(run, UTF8STEP_two(lead, first))
