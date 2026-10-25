prfn _static_snoc_elsewhere {cells:$A.cells}{from,to:nat | from <= to}{wide:int} (run: UTF8RUN(cells, from, to, wide), lead: $A.NTH(cells, to + 1, 65))
  : UTF8RUN(cells, from, to + 2, wide) = utf8run_snoc(run, UTF8STEP_one(lead))
