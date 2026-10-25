prfn _static_output_is_source {cells:$A.cells}{n:nat | 3 < n}{rest:$A.cells} (detect: DETECT(cells, 0, 3), scan: UTF8SCAN(cells, 3, 1), length: $A.CLEN(cells, n), dropped: DROPPED(cells, 3, rest), rest_len: $A.CLEN(rest, n - 3))
  : TEXTOF(cells, 1, TOUT_some(cells)) = TEXTOF_bom_dropped(detect, scan, length, dropped, rest_len)
