prfn _static_not_unsupported_refusal {cells:$A.cells}{mark:int}{total:bytes} (plan: TEXTOF(cells, 2, TOUT_bytes(total)), detect: DETECT(cells, 3, mark)): FALSEP() =
  textof_not_unsupported(plan, detect)
