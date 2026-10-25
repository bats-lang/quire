prfn _static_single_convert_of_valid {cells:$A.cells}{page:codepage}{mark,n:nat | mark <= n}{octets:bytes}
  (detect: DETECT(cells, SrcTable(page), mark), scan: UTF8SCAN(cells, 0, ScannedAscii()), length: $A.CLEN(cells, n), conv: CONV(cells, SrcTable(page), mark, n, octets)): TEXTOF(cells, PlanConvert(), TOUT_bytes(octets)) =
  TEXTOF_single_convert(detect, scan, length, conv)
