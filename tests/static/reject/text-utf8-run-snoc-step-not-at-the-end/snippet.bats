prfn _static_snoc_elsewhere {cells:$A.cells}{from,to:nat | from <= to}{spread:spread} (run: UTF8RUN(cells, from, to, spread), lead: $A.NTH(cells, to + 1, 65))
  : UTF8RUN(cells, from, to + 2, spread) = utf8run_snoc_ascii(run, UTF8STEP_one(lead))
