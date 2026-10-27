prfn _static_bom_dropped_from_zero {cells:$A.cells}{n:nat | 3 < n}{spread:spread}{octets:bytes}
  (detect: DETECT(cells, SrcUtf8(), 3), length: $A.CLEN(cells, n), run: UTF8RUN(cells, 3, n, spread), held: HOLDS(cells, 0, octets, n - 3)): TEXTOF(cells, PlanConvert(), TOUT_bytes(octets)) =
  TEXTOF_bom_dropped(detect, length, run, held)
