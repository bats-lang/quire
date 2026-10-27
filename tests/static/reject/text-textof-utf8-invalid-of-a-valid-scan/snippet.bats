prfn _static_invalid_of_valid {cells:$A.cells}{mark:nat} (detect: DETECT(cells, SrcUtf8(), mark), scan: UTF8SCAN(cells, mark, ScannedAscii())): TEXTOF(cells, PlanRefused(), TOUT_none()) =
  TEXTOF_utf8_invalid(detect, scan)
