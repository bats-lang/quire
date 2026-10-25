prfn _static_bom_dropped_is_as_is {cells:$A.cells}{n:nat | 3 < n}{spread:spread}{octets:bytes}
  (detect: DETECT(cells, SrcUtf8(), 3), length: $A.CLEN(cells, n), run: UTF8RUN(cells, 3, n, spread), held: HOLDS(cells, 3, octets, n - 3)): TEXTOF(cells, PlanAsIs(), TOUT_bytes(octets)) =
  TEXTOF_bom_dropped(detect, length, run, held)
