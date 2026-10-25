prfn _static_single_conv_other_length {cells:$A.cells}{page:codepage}{mark:int}{n:nat}{total:bytes}
  (plan: TEXTOF(cells, PlanConvert(), TOUT_bytes(total)), detect: DETECT(cells, SrcTable(page), mark), length: $A.CLEN(cells, n)): CONV(cells, SrcTable(page), mark, n + 1, total) =
  textof_single_conv(plan, detect, length)
