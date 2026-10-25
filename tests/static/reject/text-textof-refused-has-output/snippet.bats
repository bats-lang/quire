prfn _static_refused_has_output {cells:$A.cells}{mark:nat} (detect: DETECT(cells, 0, mark), scan: UTF8SCAN(cells, mark, 0)): TEXTOF(cells, 2, TOUT_some(cells)) = TEXTOF_utf8_invalid(detect, scan)
