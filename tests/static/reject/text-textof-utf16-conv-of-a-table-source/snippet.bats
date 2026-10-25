prfn _static_utf16_conv_table {cells:$A.cells}{mark,n:nat}{total:bytes}
  (plan: TEXTOF(cells, 1, TOUT_bytes(total)), detect: DETECT(cells, 4, mark), length: $A.CLEN(cells, n)): CONV(cells, 4, mark, n, total) = textof_utf16_conv(plan, detect, length)
