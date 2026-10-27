prfn _static_bom_only_no_mark {cells:$A.cells}{n:nat}{spread:spread} (detect: DETECT(cells, SrcUtf8(), 0), length: $A.CLEN(cells, n), run: UTF8RUN(cells, 0, n, spread)): TEXTOF(cells, PlanRefused(), TOUT_none()) =
  TEXTOF_bom_only(detect, length, run)
