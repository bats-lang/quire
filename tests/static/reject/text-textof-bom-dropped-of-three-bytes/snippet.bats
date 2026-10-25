prfn _static_bom_dropped_of_three {cells:$A.cells}{spread:spread}{octets:bytes}
  (detect: DETECT(cells, SrcUtf8(), 3), length: $A.CLEN(cells, 3), run: UTF8RUN(cells, 3, 3, spread), held: HOLDS(cells, 3, octets, 0)): TEXTOF(cells, PlanConvert(), TOUT_bytes(octets)) =
  TEXTOF_bom_dropped(detect, length, run, held)
