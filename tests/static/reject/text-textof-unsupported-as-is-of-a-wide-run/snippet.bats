prfn _static_unsupported_as_is_wide {cells:$A.cells}{mark,n:nat}{octets:bytes}
  (detect: DETECT(cells, SrcUnsupported(), mark), length: $A.CLEN(cells, n), run: UTF8RUN(cells, 0, n, SpreadWide()), held: HOLDS(cells, 0, octets, n)): TEXTOF(cells, PlanAsIs(), TOUT_bytes(octets)) =
  TEXTOF_unsupported_as_is(detect, length, run, held)
