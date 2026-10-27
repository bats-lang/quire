prfn _static_refused_has_bytes {cells:$A.cells}{mark:nat}{octets:bytes} (detect: DETECT(cells, SrcUtf8(), mark), scan: UTF8SCAN(cells, mark, ScannedRefused())): TEXTOF(cells, PlanRefused(), TOUT_bytes(octets)) =
  TEXTOF_utf8_invalid(detect, scan)
