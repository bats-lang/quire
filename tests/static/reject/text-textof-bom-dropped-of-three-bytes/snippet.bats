prfn _static_bom_dropped_of_three {cells:$A.cells}{verdict:int | 0 < verdict}{octets:bytes}
  (detect: DETECT(cells, 0, 3), scan: UTF8SCAN(cells, 3, verdict), length: $A.CLEN(cells, 3), held: HOLDS(cells, 3, octets, 0)): TEXTOF(cells, 1, TOUT_bytes(octets)) =
  TEXTOF_bom_dropped(detect, scan, length, held)
