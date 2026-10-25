prfn _static_single_as_is_of_unsupported {cells:$A.cells}{mark,n:nat}{spread:spread}{octets:bytes}
  (detect: DETECT(cells, SrcUnsupported(), mark), length: $A.CLEN(cells, n), run: UTF8RUN(cells, 0, n, spread), held: HOLDS(cells, 0, octets, n)): TEXTOF(cells, PlanAsIs(), TOUT_bytes(octets)) =
  TEXTOF_single_as_is{cells}{Cp1252()}{mark, n}{spread}{octets}(detect, length, run, held)
