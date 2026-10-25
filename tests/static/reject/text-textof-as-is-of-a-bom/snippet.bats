prfn _static_as_is_of_bom {cells:$A.cells}{n:nat}{spread:spread}{octets:bytes}
  (detect: DETECT(cells, SrcUtf8(), 3), length: $A.CLEN(cells, n), run: UTF8RUN(cells, 0, n, spread), held: HOLDS(cells, 0, octets, n)): TEXTOF(cells, PlanAsIs(), TOUT_bytes(octets)) =
  TEXTOF_utf8_as_is(detect, length, run, held)
