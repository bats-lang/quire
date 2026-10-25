prfn _static_single_as_is_of_unsupported {cells:$A.cells}{mark:nat}{verdict:int | 0 < verdict} (detect: DETECT(cells, 3, mark), scan: UTF8SCAN(cells, 0, verdict)): TEXTOF(cells, 0, TOUT_some(cells)) =
  TEXTOF_single_as_is(detect, scan)
