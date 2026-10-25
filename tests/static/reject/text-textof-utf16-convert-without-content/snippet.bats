prfn _static_utf16_convert_no_content {cells:$A.cells}{order:byteorder}{mark,n:nat | n <= mark}{octets:bytes}
  (detect: DETECT(cells, SrcUtf16(order), mark), length: $A.CLEN(cells, n), conv: CONV(cells, SrcUtf16(order), mark, n, octets)): TEXTOF(cells, PlanConvert(), TOUT_bytes(octets)) =
  TEXTOF_utf16_convert(detect, length, conv)
