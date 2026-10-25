prfn _static_bom_only_no_mark {cells:$A.cells}{n:nat}{verdict:int | 0 < verdict} (detect: DETECT(cells, 0, 0), scan: UTF8SCAN(cells, 0, verdict), length: $A.CLEN(cells, n)): TEXTOF(cells, 2, TOUT_none) =
  TEXTOF_bom_only(detect, scan, length)
