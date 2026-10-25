prfn _static_bom_holds_from_zero {cells:$A.cells}{mark:int}{n:nat}{total:bytes} (plan: TEXTOF(cells, PlanConvert(), TOUT_bytes(total)), detect: DETECT(cells, SrcUtf8(), mark), length: $A.CLEN(cells, n)): HOLDS(cells, 0, total, n - 3) =
  textof_bom_holds(plan, detect, length)
