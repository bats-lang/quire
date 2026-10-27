prfn _static_utf16_convert_of_table {cells:$A.cells}{order:byteorder}{mark,n:nat | mark < n}{octets:bytes}
  (detect: DETECT(cells, SrcUtf16(order), mark), length: $A.CLEN(cells, n), conv: CONV(cells, SrcTable(Cp1252()), mark, n, octets)): TEXTOF(cells, PlanConvert(), TOUT_bytes(octets)) =
  TEXTOF_utf16_convert{cells}{order}{mark, n}{octets}(detect, length, conv)
