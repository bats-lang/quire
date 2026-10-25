prfn _static_utf16_convert_without_content {cells:$A.cells}{source:int | source == 1 || source == 2}{mark,n:nat | n <= mark} (detect: DETECT(cells, source, mark), length: $A.CLEN(cells, n))
  : TEXTOF(cells, 1, TOUT_later) = TEXTOF_utf16_convert(detect, length)
