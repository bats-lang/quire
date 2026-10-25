prfn _static_bom_dropped_of_bare_mark {cells:$A.cells}{rest:$A.cells} (detect: DETECT(cells, 0, 3), scan: UTF8SCAN(cells, 3, 1), length: $A.CLEN(cells, 3), dropped: DROPPED(cells, 3, rest), rest_len: $A.CLEN(rest, 0))
  : TEXTOF(cells, 1, TOUT_some(rest)) = TEXTOF_bom_dropped(detect, scan, length, dropped, rest_len)
