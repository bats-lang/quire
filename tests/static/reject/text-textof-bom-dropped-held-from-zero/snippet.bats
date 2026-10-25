prfn _static_bom_dropped_from_zero {cells:$A.cells}{n:nat | 3 < n}{verdict:int | 0 < verdict}{octets:bytes}
  (detect: DETECT(cells, 0, 3), scan: UTF8SCAN(cells, 3, verdict), length: $A.CLEN(cells, n), held: HOLDS(cells, 0, octets, n - 3)): TEXTOF(cells, 1, TOUT_bytes(octets)) =
  TEXTOF_bom_dropped(detect, scan, length, held)
