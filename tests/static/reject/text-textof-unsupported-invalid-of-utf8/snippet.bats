prfn _static_unsupported_invalid_of_utf8 {cells:$A.cells}{mark:nat} (detect: DETECT(cells, SrcUtf8(), mark), scan: UTF8SCAN(cells, 0, ScannedRefused())): TEXTOF(cells, PlanRefused(), TOUT_none()) =
  TEXTOF_unsupported_invalid{cells}{mark}(detect, scan)
