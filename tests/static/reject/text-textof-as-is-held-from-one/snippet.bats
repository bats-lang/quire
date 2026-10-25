prfn _static_as_is_from_one {cells:$A.cells}{n:nat}{verdict:int | 0 < verdict}{octets:bytes}
  (detect: DETECT(cells, 0, 0), scan: UTF8SCAN(cells, 0, verdict), length: $A.CLEN(cells, n), held: HOLDS(cells, 1, octets, n)): TEXTOF(cells, 0, TOUT_bytes(octets)) =
  TEXTOF_utf8_as_is(detect, scan, length, held)
