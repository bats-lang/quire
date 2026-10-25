prfn _static_single_convert_of_utf16 {cells:$A.cells}{order:byteorder}{mark,n:nat | mark <= n}{octets:bytes}
  (detect: DETECT(cells, SrcUtf16(order), mark), scan: UTF8SCAN(cells, 0, ScannedRefused()), length: $A.CLEN(cells, n), conv: CONV(cells, SrcUtf16(order), mark, n, octets)): TEXTOF(cells, PlanConvert(), TOUT_bytes(octets)) =
  TEXTOF_single_convert{cells}{Cp1252()}{mark, n}{octets}(detect, scan, length, conv)
