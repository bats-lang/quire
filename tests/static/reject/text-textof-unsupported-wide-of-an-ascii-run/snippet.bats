prfn _static_unsupported_wide_ascii {cells:$A.cells}{mark,n:nat} (detect: DETECT(cells, SrcUnsupported(), mark), length: $A.CLEN(cells, n), run: UTF8RUN(cells, 0, n, SpreadAscii())): TEXTOF(cells, PlanRefused(), TOUT_none()) =
  TEXTOF_unsupported_wide(detect, length, run)
