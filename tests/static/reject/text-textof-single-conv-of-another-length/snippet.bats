prfn _static_single_conv_other_length {cells:$A.cells}{source,mark:int | 4 <= source; source <= 17}{n:nat}{total:bytes}
  (plan: TEXTOF(cells, 1, TOUT_bytes(total)), detect: DETECT(cells, source, mark), length: $A.CLEN(cells, n)): CONV(cells, source, mark, n + 1, total) = textof_single_conv(plan, detect, length)
