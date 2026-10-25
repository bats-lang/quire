prfn _static_utf16_empty_with_content {cells:$A.cells}{order:byteorder}{mark,n:nat | mark < n} (detect: DETECT(cells, SrcUtf16(order), mark), length: $A.CLEN(cells, n))
  : TEXTOF(cells, PlanRefused(), TOUT_none()) = TEXTOF_utf16_empty(detect, length)
