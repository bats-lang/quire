prfn _static_single_convert_of_valid {cells:$A.cells}{source:int | 4 <= source; source <= 17}{mark,n:nat | mark <= n}{octets:bytes}
  (detect: DETECT(cells, source, mark), scan: UTF8SCAN(cells, 0, 1), length: $A.CLEN(cells, n), conv: CONV(cells, source, mark, n, octets)): TEXTOF(cells, 1, TOUT_bytes(octets)) =
  TEXTOF_single_convert(detect, scan, length, conv)
