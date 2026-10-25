prfn _static_utf16_convert_no_content {cells:$A.cells}{source:int | source == 1 || source == 2}{mark,n:nat | n <= mark}{octets:bytes}
  (detect: DETECT(cells, source, mark), length: $A.CLEN(cells, n), conv: CONV(cells, source, mark, n, octets)): TEXTOF(cells, 1, TOUT_bytes(octets)) =
  TEXTOF_utf16_convert(detect, length, conv)
