prfn _static_unsupported_ascii_refused {cells:$A.cells}{mark:nat} (detect: DETECT(cells, 3, mark), scan: UTF8SCAN(cells, 0, 1)): TEXTOF(cells, 2, TOUT_none) = TEXTOF_unsupported_refused(detect, scan)
