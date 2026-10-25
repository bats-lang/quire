prfn _static_refused_has_bytes {cells:$A.cells}{mark:nat}{octets:bytes} (detect: DETECT(cells, 0, mark), scan: UTF8SCAN(cells, mark, 0)): TEXTOF(cells, 2, TOUT_bytes(octets)) =
  TEXTOF_utf8_invalid(detect, scan)
