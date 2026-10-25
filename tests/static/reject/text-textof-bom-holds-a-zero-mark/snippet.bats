prfn _static_bom_holds_zero {cells:$A.cells}{n:nat}{total:bytes} (plan: TEXTOF(cells, 1, TOUT_bytes(total)), detect: DETECT(cells, 0, 0), length: $A.CLEN(cells, n)): HOLDS(cells, 3, total, n - 3) =
  textof_bom_holds(plan, detect, length)
