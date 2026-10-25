prfn _static_single_convert_of_utf16 {cells:$A.cells}{mark,n:nat | mark <= n}{octets:bytes}
  (detect: DETECT(cells, 1, mark), scan: UTF8SCAN(cells, 0, 0), length: $A.CLEN(cells, n), conv: CONV(cells, 1, mark, n, octets)): TEXTOF(cells, 1, TOUT_bytes(octets)) =
  TEXTOF_single_convert(detect, scan, length, conv)
