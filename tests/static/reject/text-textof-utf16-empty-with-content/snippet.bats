prfn _static_utf16_empty_with_content {cells:$A.cells}{source:int | source == 1 || source == 2}{mark,n:nat | mark < n} (detect: DETECT(cells, source, mark), length: $A.CLEN(cells, n))
  : TEXTOF(cells, 2, TOUT_none) = TEXTOF_utf16_empty(detect, length)
